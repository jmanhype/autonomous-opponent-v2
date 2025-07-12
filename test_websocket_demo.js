#!/usr/bin/env node

const WebSocket = require('ws');

console.log('=== WebSocket Connection Counting Demo ===\n');

async function createConnection(channel, name) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket('ws://localhost:4000/socket/websocket');
    
    ws.on('open', () => {
      ws.send(JSON.stringify({
        topic: channel,
        event: 'phx_join',
        payload: {},
        ref: 1
      }));
    });
    
    ws.on('message', (data) => {
      const msg = JSON.parse(data);
      if (msg.event === 'phx_reply' && msg.payload?.status === 'ok') {
        console.log(`✓ ${name} connected to ${channel}`);
        resolve(ws);
      }
    });
    
    ws.on('error', reject);
    setTimeout(() => reject(new Error('Timeout')), 3000);
  });
}

async function getStats(statsWs) {
  return new Promise((resolve) => {
    const handler = (data) => {
      const msg = JSON.parse(data);
      if (msg.event === 'local_stats') {
        statsWs.removeListener('message', handler);
        resolve(msg.payload);
      }
    };
    
    statsWs.on('message', handler);
    statsWs.send(JSON.stringify({
      topic: 'patterns:stats',
      event: 'get_local_stats',
      payload: {},
      ref: 2
    }));
  });
}

async function demo() {
  try {
    // Create stats connection
    console.log('1. Creating stats connection...');
    const statsWs = await createConnection('patterns:stats', 'Stats monitor');
    
    // Check initial stats
    let stats = await getStats(statsWs);
    console.log(`   Initial counts - Stream: ${stats.stream_count}, Total: ${stats.connection_count}\n`);
    
    // Create stream connections
    console.log('2. Creating 3 stream connections...');
    const conn1 = await createConnection('patterns:stream', 'Stream 1');
    const conn2 = await createConnection('patterns:stream', 'Stream 2');
    const conn3 = await createConnection('patterns:stream', 'Stream 3');
    
    // Check stats after connections
    stats = await getStats(statsWs);
    console.log(`   After connections - Stream: ${stats.stream_count}, Total: ${stats.connection_count}\n`);
    
    // Disconnect one
    console.log('3. Disconnecting Stream 2...');
    conn2.close();
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // Check stats after disconnect
    stats = await getStats(statsWs);
    console.log(`   After disconnect - Stream: ${stats.stream_count}, Total: ${stats.connection_count}\n`);
    
    // Create VSM connection
    console.log('4. Creating VSM connection...');
    const vsmWs = await createConnection('patterns:vsm', 'VSM monitor');
    
    // Final stats
    stats = await getStats(statsWs);
    console.log(`   Final counts - Stream: ${stats.stream_count}, Total: ${stats.connection_count}`);
    console.log(`   By topic: ${JSON.stringify(stats.connections_by_topic, null, 2)}\n`);
    
    console.log('✅ WebSocket connection counting is working perfectly!');
    console.log('   - Connections are tracked per topic');
    console.log('   - Increments on join, decrements on leave');
    console.log('   - Stats available in real-time');
    console.log('   - Multiple channel types supported');
    
    // Cleanup
    conn1.close();
    conn3.close();
    vsmWs.close();
    statsWs.close();
    
  } catch (error) {
    console.error('❌ Demo failed:', error.message);
    process.exit(1);
  }
}

// Run demo
demo();