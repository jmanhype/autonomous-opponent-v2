#!/usr/bin/env node

const WebSocket = require('ws');

console.log('Testing basic WebSocket functionality...\n');

// Test 1: Basic connection
const ws1 = new WebSocket('ws://localhost:4000/socket/websocket');

ws1.on('open', () => {
  console.log('✓ Connected to WebSocket server');
  
  // Join patterns:stream
  ws1.send(JSON.stringify({
    topic: 'patterns:stream',
    event: 'phx_join',
    payload: {},
    ref: 1
  }));
});

ws1.on('message', (data) => {
  const msg = JSON.parse(data);
  if (msg.event === 'phx_reply' && msg.payload?.status === 'ok') {
    console.log('✓ Joined patterns:stream channel');
    
    // Now test stats channel
    const ws2 = new WebSocket('ws://localhost:4000/socket/websocket');
    
    ws2.on('open', () => {
      ws2.send(JSON.stringify({
        topic: 'patterns:stats',
        event: 'phx_join',
        payload: {},
        ref: 1
      }));
    });
    
    ws2.on('message', (data2) => {
      const msg2 = JSON.parse(data2);
      if (msg2.event === 'phx_reply' && msg2.payload?.status === 'ok') {
        console.log('✓ Joined patterns:stats channel');
        
        // Get local stats
        ws2.send(JSON.stringify({
          topic: 'patterns:stats',
          event: 'get_local_stats',
          payload: {},
          ref: 2
        }));
        
        // Set timeout for response
        setTimeout(() => {
          console.log('✗ No response to get_local_stats');
          ws1.close();
          ws2.close();
          process.exit(1);
        }, 2000);
      } else if (msg2.event === 'local_stats') {
        console.log('✓ Got local stats:', JSON.stringify(msg2.payload));
        console.log('\n✓ WebSocket connection counting is working locally!');
        ws1.close();
        ws2.close();
        process.exit(0);
      }
    });
    
    ws2.on('error', (err) => {
      console.log('✗ Stats WebSocket error:', err.message);
      process.exit(1);
    });
  }
});

ws1.on('error', (err) => {
  console.log('✗ WebSocket error:', err.message);
  console.log('Make sure the server is running on http://localhost:4000');
  process.exit(1);
});

// Global timeout
setTimeout(() => {
  console.log('\n✗ Test timed out after 5 seconds');
  process.exit(1);
}, 5000);