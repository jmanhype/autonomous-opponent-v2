#!/usr/bin/env node

const WebSocket = require('ws');

console.log('🚀 Testing Phoenix WebSocket channels...\n');

const ws = new WebSocket('ws://127.0.0.1:4000/socket/websocket?vsn=2.0.0');

ws.on('open', () => {
  console.log('✅ Connected to WebSocket');
  
  // Phoenix expects specific message format with vsn
  const joinMsg = JSON.stringify([
    "1",          // ref
    "1",          // join_ref
    "patterns:stream", // topic
    "phx_join",   // event
    {}            // payload
  ]);
  
  console.log('📤 Sending join request:', joinMsg);
  ws.send(joinMsg);
});

ws.on('message', (data) => {
  console.log('📥 Received:', data.toString());
  const parsed = JSON.parse(data.toString());
  
  if (parsed[3] === 'phx_reply' && parsed[4].status === 'ok') {
    console.log('✅ Successfully joined channel!');
    
    // Test a query
    const queryMsg = JSON.stringify([
      "2",          // ref
      "1",          // join_ref
      "patterns:stream", // topic
      "get_monitoring",  // event
      {}            // payload
    ]);
    
    console.log('\n📤 Sending monitoring request...');
    ws.send(queryMsg);
  }
});

ws.on('error', (error) => {
  console.error('❌ WebSocket error:', error);
});

// Close after 5 seconds
setTimeout(() => {
  console.log('\n👋 Closing connection...');
  ws.close();
}, 5000);