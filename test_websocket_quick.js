#!/usr/bin/env node

const WebSocket = require('ws');

console.log('=== Quick WebSocket Connection Test ===\n');

const ws = new WebSocket('ws://localhost:4000/socket/websocket');

ws.on('open', () => {
  console.log('✓ Connected to WebSocket');
  
  // Join patterns:stats channel
  ws.send(JSON.stringify({
    topic: 'patterns:stats',
    event: 'phx_join',
    payload: {},
    ref: 1
  }));
});

ws.on('message', (data) => {
  const msg = JSON.parse(data);
  
  if (msg.event === 'phx_reply' && msg.payload?.status === 'ok') {
    console.log('✓ Joined patterns:stats channel');
    
    // Request local stats
    ws.send(JSON.stringify({
      topic: 'patterns:stats',
      event: 'get_local_stats',
      payload: {},
      ref: 2
    }));
  } else if (msg.event === 'local_stats') {
    console.log('✓ Received local stats:', msg.payload);
    
    // Request cluster stats
    ws.send(JSON.stringify({
      topic: 'patterns:stats',
      event: 'get_cluster_stats',
      payload: {},
      ref: 3
    }));
  } else if (msg.event === 'cluster_stats') {
    console.log('✓ Received cluster stats:', msg.payload);
    console.log('\n✓ WebSocket connection counting is working!');
    ws.close();
    process.exit(0);
  }
});

ws.on('error', (err) => {
  console.log('✗ WebSocket error:', err.message);
  process.exit(1);
});

// Timeout after 5 seconds
setTimeout(() => {
  console.log('✗ Test timed out');
  ws.close();
  process.exit(1);
}, 5000);