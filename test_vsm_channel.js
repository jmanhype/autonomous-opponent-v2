const WebSocket = require('ws');

async function testVSMChannel() {
  console.log('🧪 Testing patterns:vsm channel join\n');
  
  const ws = new WebSocket('ws://localhost:4000/socket/websocket');
  
  ws.on('open', () => {
    console.log('✅ WebSocket connected');
    
    // Try to join patterns:vsm with subsystem
    const joinMsg = {
      topic: 'patterns:vsm',
      event: 'phx_join',
      payload: { subsystem: 'all' },
      ref: '1',
      join_ref: '1'
    };
    
    console.log('📤 Sending join request:', JSON.stringify(joinMsg, null, 2));
    ws.send(JSON.stringify(joinMsg));
  });
  
  ws.on('message', (data) => {
    const msg = JSON.parse(data.toString());
    console.log('📨 Received:', JSON.stringify(msg, null, 2));
    
    if (msg.event === 'phx_reply' && msg.ref === '1') {
      if (msg.payload.status === 'ok') {
        console.log('\n✅ Successfully joined patterns:vsm!');
      } else {
        console.log('\n❌ Failed to join:', msg.payload);
      }
      
      setTimeout(() => {
        ws.close();
        process.exit(0);
      }, 1000);
    }
  });
  
  ws.on('error', (error) => {
    console.error('❌ WebSocket error:', error);
  });
  
  ws.on('close', () => {
    console.log('🔌 WebSocket closed');
  });
}

// Run the test
testVSMChannel();