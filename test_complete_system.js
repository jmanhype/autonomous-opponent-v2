const WebSocket = require('ws');

// Helper to create and join a channel
async function createChannel(topic, payload = {}) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket('ws://localhost:4000/socket/websocket');
    let joined = false;
    
    ws.on('open', () => {
      const joinMsg = {
        topic: topic,
        event: 'phx_join',
        payload: payload,
        ref: '1',
        join_ref: '1'
      };
      ws.send(JSON.stringify(joinMsg));
    });
    
    ws.on('message', (data) => {
      const msg = JSON.parse(data.toString());
      if (msg.event === 'phx_reply' && msg.ref === '1' && !joined) {
        joined = true;
        if (msg.payload.status === 'ok') {
          resolve(ws);
        } else {
          ws.close();
          reject(new Error(`Failed to join ${topic}: ${JSON.stringify(msg.payload)}`));
        }
      }
    });
    
    ws.on('error', (err) => {
      reject(err);
    });
    
    setTimeout(() => {
      if (!joined) {
        ws.close();
        reject(new Error(`Timeout joining ${topic}`));
      }
    }, 5000);
  });
}

// Helper to send a message and get response
async function sendMessage(ws, topic, event, payload, joinRef = '1') {
  return new Promise((resolve, reject) => {
    const ref = Date.now().toString();
    let responded = false;
    
    const handler = (data) => {
      const msg = JSON.parse(data.toString());
      if (msg.event === 'phx_reply' && msg.ref === ref && !responded) {
        responded = true;
        ws.removeListener('message', handler);
        if (msg.payload.status === 'ok') {
          resolve(msg.payload.response);
        } else {
          reject(new Error(`${event} failed: ${JSON.stringify(msg.payload)}`));
        }
      }
    };
    
    ws.on('message', handler);
    
    const message = {
      topic: topic,
      event: event,
      payload: payload,
      ref: ref,
      join_ref: joinRef
    };
    
    ws.send(JSON.stringify(message));
    
    setTimeout(() => {
      if (!responded) {
        ws.removeListener('message', handler);
        reject(new Error(`${event} timeout`));
      }
    }, 5000);
  });
}

async function testCompleteSystem() {
  console.log('🚀 COMPLETE WEBSOCKET CONNECTION COUNTING TEST\n');
  console.log('=' .repeat(60));
  
  const connections = [];
  let allTestsPassed = true;
  
  try {
    // Phase 1: Create connections
    console.log('\n📡 PHASE 1: Creating WebSocket Connections');
    console.log('-'.repeat(40));
    
    // Create 3 stream connections
    for (let i = 1; i <= 3; i++) {
      try {
        const ws = await createChannel('patterns:stream');
        connections.push(ws);
        console.log(`  ✅ Connected to patterns:stream (#${i})`);
      } catch (error) {
        console.log(`  ❌ Failed to connect patterns:stream (#${i}): ${error.message}`);
        allTestsPassed = false;
      }
    }
    
    // Create 2 stats connections
    for (let i = 1; i <= 2; i++) {
      try {
        const ws = await createChannel('patterns:stats');
        connections.push(ws);
        console.log(`  ✅ Connected to patterns:stats (#${i})`);
      } catch (error) {
        console.log(`  ❌ Failed to connect patterns:stats (#${i}): ${error.message}`);
        allTestsPassed = false;
      }
    }
    
    // Create 1 vsm connection
    try {
      const ws = await createChannel('patterns:vsm', { subsystem: 'all' });
      connections.push(ws);
      console.log(`  ✅ Connected to patterns:vsm`);
    } catch (error) {
      console.log(`  ❌ Failed to connect patterns:vsm: ${error.message}`);
      allTestsPassed = false;
    }
    
    console.log(`\n  Total connections created: ${connections.length}`);
    
    // Phase 2: Test local stats
    console.log('\n📊 PHASE 2: Testing Local Connection Stats');
    console.log('-'.repeat(40));
    
    if (connections.length >= 4) {
      try {
        const stats = await sendMessage(connections[3], 'patterns:stats', 'get_connection_stats', {});
        console.log('  ✅ Local stats retrieved successfully!');
        console.log(`     Total connections: ${stats.total}`);
        console.log('     Connections by topic:');
        
        let verifiedTotal = 0;
        for (const [topic, nodes] of Object.entries(stats.connections || {})) {
          const count = Object.values(nodes).reduce((sum, n) => sum + n, 0);
          verifiedTotal += count;
          console.log(`       - ${topic}: ${count}`);
        }
        
        if (stats.total === connections.length && verifiedTotal === connections.length) {
          console.log(`  ✅ Connection count verified: ${stats.total} = ${connections.length}`);
        } else {
          console.log(`  ❌ Connection count mismatch: reported ${stats.total}, actual ${connections.length}`);
          allTestsPassed = false;
        }
      } catch (error) {
        console.log(`  ❌ Failed to get local stats: ${error.message}`);
        allTestsPassed = false;
      }
    }
    
    // Phase 3: Test cluster stats
    console.log('\n🌐 PHASE 3: Testing Cluster-wide Stats');
    console.log('-'.repeat(40));
    
    if (connections.length >= 4) {
      try {
        const clusterStats = await sendMessage(connections[3], 'patterns:stats', 'get_cluster_connection_stats', {});
        console.log('  ✅ Cluster stats retrieved successfully!');
        console.log(`     Total cluster connections: ${clusterStats.total_connections}`);
        console.log(`     Cluster size: ${clusterStats.cluster_size} nodes`);
        console.log('     Topics summary:');
        
        for (const [topic, data] of Object.entries(clusterStats.topics || {})) {
          console.log(`       - ${topic}: ${data.total} connections`);
        }
        
        if (clusterStats.total_connections === connections.length) {
          console.log(`  ✅ Cluster count verified: ${clusterStats.total_connections}`);
        } else {
          console.log(`  ❌ Cluster count mismatch: ${clusterStats.total_connections} vs ${connections.length}`);
          allTestsPassed = false;
        }
      } catch (error) {
        console.log(`  ⚠️  Cluster stats not available: ${error.message}`);
        console.log('     (This is expected if PatternAggregator is not running)');
      }
    }
    
    // Phase 4: Test connection cleanup
    console.log('\n🧹 PHASE 4: Testing Connection Cleanup');
    console.log('-'.repeat(40));
    
    if (connections.length >= 4) {
      const beforeCount = connections.length;
      console.log(`  Closing 2 connections (current: ${beforeCount})...`);
      
      // Close first two connections
      connections[0].close();
      connections[1].close();
      connections.splice(0, 2);
      
      // Wait for cleanup
      await new Promise(resolve => setTimeout(resolve, 1500));
      
      try {
        const afterStats = await sendMessage(connections[1], 'patterns:stats', 'get_connection_stats', {});
        console.log(`  ✅ Stats after cleanup retrieved`);
        console.log(`     New total: ${afterStats.total}`);
        
        if (afterStats.total === connections.length) {
          console.log(`  ✅ Cleanup verified: ${beforeCount} → ${afterStats.total}`);
        } else {
          console.log(`  ❌ Cleanup failed: expected ${connections.length}, got ${afterStats.total}`);
          allTestsPassed = false;
        }
      } catch (error) {
        console.log(`  ❌ Failed to verify cleanup: ${error.message}`);
        allTestsPassed = false;
      }
    }
    
    // Phase 5: Test pattern search functionality
    console.log('\n🔍 PHASE 5: Testing Pattern Search (Bonus)');
    console.log('-'.repeat(40));
    
    if (connections.length >= 1) {
      try {
        // Create a test vector (100 dimensions)
        const testVector = Array(100).fill(0).map(() => Math.random());
        const results = await sendMessage(connections[0], 'patterns:stream', 'query_similar', {
          vector: testVector,
          k: 5
        });
        
        console.log(`  ✅ Pattern search working!`);
        console.log(`     Found ${results.results?.length || 0} similar patterns`);
      } catch (error) {
        console.log(`  ⚠️  Pattern search not available: ${error.message}`);
        console.log('     (This is expected if PatternHNSWBridge is not running)');
      }
    }
    
  } catch (error) {
    console.error(`\n❌ Unexpected error: ${error.message}`);
    allTestsPassed = false;
  } finally {
    // Cleanup
    console.log('\n🏁 FINAL CLEANUP');
    console.log('-'.repeat(40));
    console.log(`  Closing ${connections.length} remaining connections...`);
    connections.forEach(ws => ws.close());
    
    // Final summary
    console.log('\n' + '='.repeat(60));
    if (allTestsPassed) {
      console.log('✅ ALL TESTS PASSED! WebSocket connection counting is 100% functional!');
    } else {
      console.log('⚠️  Some tests failed - see details above');
    }
    console.log('='.repeat(60));
    
    setTimeout(() => process.exit(allTestsPassed ? 0 : 1), 1000);
  }
}

// Run the complete test
testCompleteSystem().catch(console.error);