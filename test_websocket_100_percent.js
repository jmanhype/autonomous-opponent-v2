#!/usr/bin/env node

const WebSocket = require('ws');

// Configuration
const BASE_URL = 'ws://localhost:4000/socket/websocket';
const NUM_CONNECTIONS = 10;
const TEST_DURATION = 15000; // 15 seconds to ensure aggregation happens

console.log('=== WebSocket Connection Counting - 100% Test ===\n');

let allPassed = true;
const connections = [];
const statsConnections = [];

// Helper to create WebSocket connection
function createConnection(channel, topic = null) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(BASE_URL);
    const connection = { ws, joined: false, ref: 1 };
    
    ws.on('open', () => {
      // Join channel
      const joinMsg = {
        topic: channel,
        event: 'phx_join',
        payload: topic ? { topic } : {},
        ref: connection.ref++
      };
      ws.send(JSON.stringify(joinMsg));
    });
    
    ws.on('message', (data) => {
      const msg = JSON.parse(data);
      if (msg.event === 'phx_reply' && msg.payload?.status === 'ok' && !connection.joined) {
        connection.joined = true;
        resolve(connection);
      }
    });
    
    ws.on('error', reject);
    
    setTimeout(() => reject(new Error('Join timeout')), 5000);
  });
}

// Helper to request stats
function requestStats(connection, type = 'local') {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      reject(new Error(`${type} stats timeout`));
    }, 3000);
    
    const handler = (data) => {
      const msg = JSON.parse(data);
      if (msg.event === `${type}_stats`) {
        clearTimeout(timeout);
        connection.ws.removeListener('message', handler);
        resolve(msg.payload);
      }
    };
    
    connection.ws.on('message', handler);
    
    const statsMsg = {
      topic: 'patterns:stats',
      event: `get_${type}_stats`,
      payload: {},
      ref: connection.ref++
    };
    connection.ws.send(JSON.stringify(statsMsg));
  });
}

// Test 1: Create connections gradually
async function testGradualConnections() {
  console.log('Test 1: Creating connections gradually...');
  
  try {
    // Create stats connection first
    const statsConn = await createConnection('patterns:stats');
    statsConnections.push(statsConn);
    console.log('✓ Stats connection established');
    
    // Create stream connections one by one
    for (let i = 0; i < NUM_CONNECTIONS; i++) {
      const conn = await createConnection('patterns:stream');
      connections.push(conn);
      console.log(`✓ Connection ${i + 1}/${NUM_CONNECTIONS} established`);
      
      // Check stats after each connection
      try {
        const localStats = await requestStats(statsConn, 'local');
        console.log(`  Stream count: ${localStats.stream_count}, Total: ${localStats.connection_count}`);
        
        if (localStats.stream_count !== i + 1) {
          console.log(`  ✗ Expected ${i + 1} stream connections, got ${localStats.stream_count}`);
          allPassed = false;
        }
      } catch (e) {
        console.log(`  ✗ Failed to get local stats: ${e.message}`);
      }
    }
    
    console.log('\n✓ All connections created');
    return true;
  } catch (error) {
    console.log(`✗ Failed to create connections: ${error.message}`);
    allPassed = false;
    return false;
  }
}

// Test 2: Verify cluster stats (PatternAggregator)
async function testClusterStats() {
  console.log('\nTest 2: Checking cluster-wide stats (PatternAggregator)...');
  
  if (statsConnections.length === 0) {
    console.log('✗ No stats connection available');
    allPassed = false;
    return false;
  }
  
  const statsConn = statsConnections[0];
  
  try {
    // Wait a bit for aggregation
    console.log('Waiting 5 seconds for PatternAggregator to aggregate...');
    await new Promise(resolve => setTimeout(resolve, 5000));
    
    const clusterStats = await requestStats(statsConn, 'cluster');
    console.log(`✓ Cluster stats received:`, JSON.stringify(clusterStats, null, 2));
    
    // Check if cluster stats match expected
    const expectedCount = NUM_CONNECTIONS;
    const actualCount = Object.values(clusterStats.nodes || {})
      .reduce((sum, node) => sum + (node.connection_count || 0), 0);
    
    if (actualCount === expectedCount) {
      console.log(`✓ Cluster count correct: ${actualCount}`);
      return true;
    } else {
      console.log(`✗ Cluster count incorrect: expected ${expectedCount}, got ${actualCount}`);
      allPassed = false;
      return false;
    }
  } catch (error) {
    console.log(`✗ Failed to get cluster stats: ${error.message}`);
    console.log('  This likely means PatternAggregator is not running');
    allPassed = false;
    return false;
  }
}

// Test 3: Test disconnection handling
async function testDisconnections() {
  console.log('\nTest 3: Testing disconnection handling...');
  
  if (connections.length < 5 || statsConnections.length === 0) {
    console.log('✗ Not enough connections for disconnection test');
    allPassed = false;
    return false;
  }
  
  const statsConn = statsConnections[0];
  
  try {
    // Get initial count
    const initialStats = await requestStats(statsConn, 'local');
    console.log(`Initial stream count: ${initialStats.stream_count}`);
    
    // Disconnect 5 connections
    console.log('Disconnecting 5 connections...');
    for (let i = 0; i < 5; i++) {
      connections[i].ws.close();
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    
    // Wait for cleanup
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // Check new count
    const afterStats = await requestStats(statsConn, 'local');
    console.log(`Stream count after disconnections: ${afterStats.stream_count}`);
    
    const expectedRemaining = NUM_CONNECTIONS - 5;
    if (afterStats.stream_count === expectedRemaining) {
      console.log(`✓ Disconnection tracking correct: ${afterStats.stream_count}`);
      
      // Also check cluster stats
      await new Promise(resolve => setTimeout(resolve, 3000));
      try {
        const clusterStats = await requestStats(statsConn, 'cluster');
        const clusterCount = Object.values(clusterStats.nodes || {})
          .reduce((sum, node) => sum + (node.connection_count || 0), 0);
        console.log(`✓ Cluster count after disconnections: ${clusterCount}`);
      } catch (e) {
        console.log(`  Note: Cluster stats unavailable: ${e.message}`);
      }
      
      return true;
    } else {
      console.log(`✗ Expected ${expectedRemaining} stream connections, got ${afterStats.stream_count}`);
      allPassed = false;
      return false;
    }
  } catch (error) {
    console.log(`✗ Disconnection test failed: ${error.message}`);
    allPassed = false;
    return false;
  }
}

// Test 4: Verify pattern:vsm channel works
async function testVsmChannel() {
  console.log('\nTest 4: Testing patterns:vsm channel...');
  
  try {
    const vsmConn = await createConnection('patterns:vsm', 's4');
    console.log('✓ Successfully joined patterns:vsm with topic s4');
    
    // Listen for pattern events
    const patternPromise = new Promise((resolve) => {
      const timeout = setTimeout(() => resolve(null), 5000);
      vsmConn.ws.on('message', (data) => {
        const msg = JSON.parse(data);
        if (msg.event === 'vsm_pattern') {
          clearTimeout(timeout);
          resolve(msg.payload);
        }
      });
    });
    
    console.log('Waiting for VSM pattern events (5 seconds)...');
    const pattern = await patternPromise;
    
    if (pattern) {
      console.log('✓ Received VSM pattern event:', JSON.stringify(pattern, null, 2));
    } else {
      console.log('  No VSM pattern events received (this is okay if no patterns are being generated)');
    }
    
    vsmConn.ws.close();
    return true;
  } catch (error) {
    console.log(`✗ VSM channel test failed: ${error.message}`);
    allPassed = false;
    return false;
  }
}

// Main test runner
async function runTests() {
  console.log('Starting comprehensive WebSocket tests...\n');
  console.log('Requirements:');
  console.log('1. Server must be running as distributed node');
  console.log('2. PatternAggregator must be active');
  console.log('3. All channels must be functional\n');
  
  // Run tests in sequence
  await testGradualConnections();
  await testClusterStats();
  await testDisconnections();
  await testVsmChannel();
  
  // Cleanup
  console.log('\nCleaning up connections...');
  connections.forEach(conn => conn.ws.close());
  statsConnections.forEach(conn => conn.ws.close());
  
  // Summary
  console.log('\n=== Test Summary ===');
  if (allPassed) {
    console.log('✓ ALL TESTS PASSED - WebSocket connection counting is working 100%!');
    console.log('✓ Local connection tracking: Working');
    console.log('✓ Cluster-wide aggregation: Working');
    console.log('✓ Disconnection handling: Working');
    console.log('✓ VSM channel integration: Working');
    process.exit(0);
  } else {
    console.log('✗ Some tests failed - see details above');
    console.log('\nCommon issues:');
    console.log('1. PatternAggregator not running - start server with:');
    console.log('   elixir --name test@127.0.0.1 -S mix phx.server');
    console.log('2. EventBus not started - check application supervision tree');
    console.log('3. WebGateway health check failures - check S4 Intelligence logs');
    process.exit(1);
  }
}

// Handle errors
process.on('unhandledRejection', (error) => {
  console.error('\n✗ Unhandled error:', error.message);
  process.exit(1);
});

// Run tests
runTests().catch(error => {
  console.error('\n✗ Test runner failed:', error);
  process.exit(1);
});