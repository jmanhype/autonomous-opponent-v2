#!/usr/bin/env node

const WebSocket = require('ws');

console.log('🚀 Testing WebSocket monitoring endpoint...\n');

const ws = new WebSocket('ws://127.0.0.1:4000/socket/websocket');
let messageRef = 0;

ws.on('open', () => {
  console.log('✅ Connected to WebSocket');
  
  // Join channel
  const joinMsg = {
    topic: 'patterns:stream',
    event: 'phx_join',
    payload: {},
    ref: String(++messageRef)
  };
  
  console.log('📤 Sending join request...');
  ws.send(JSON.stringify(joinMsg));
});

ws.on('message', (data) => {
  const msg = JSON.parse(data.toString());
  console.log('📥 Received:', JSON.stringify(msg, null, 2));
  
  if (msg.event === 'phx_reply' && msg.payload.status === 'ok' && msg.ref === '1') {
    console.log('\n✅ Successfully joined channel!\n');
    
    // Test monitoring
    const monitoringMsg = {
      topic: 'patterns:stream',
      event: 'get_monitoring',
      payload: {},
      ref: String(++messageRef)
    };
    
    console.log('📤 Sending monitoring request...');
    ws.send(JSON.stringify(monitoringMsg));
    
    // Also test initial stats
    setTimeout(() => {
      const statsMsg = {
        topic: 'patterns:stream',
        event: 'get_stats',
        payload: {},
        ref: String(++messageRef)
      };
      
      console.log('\n📤 Sending stats request...');
      ws.send(JSON.stringify(statsMsg));
    }, 1000);
  }
});

ws.on('error', (error) => {
  console.error('❌ WebSocket error:', error);
});

// Close after 5 seconds
setTimeout(() => {
  console.log('\n👋 Closing connection...');
  ws.close();
  process.exit(0);
}, 5000);