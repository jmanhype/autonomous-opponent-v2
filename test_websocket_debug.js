const WebSocket = require('ws');

async function testWebSocketDebug() {
  console.log('🧪 Testing WebSocket Connection (Debug Mode)\n');
  
  const ws = new WebSocket('ws://localhost:4000/socket/websocket');
  
  ws.on('open', () => {
    console.log('✅ WebSocket connected to server');
    
    // Try to join patterns:stats channel
    const joinMsg = {
      topic: 'patterns:stats',
      event: 'phx_join',
      payload: {},
      ref: '1',
      join_ref: '1'
    };
    
    console.log('📤 Sending join request:', JSON.stringify(joinMsg));
    ws.send(JSON.stringify(joinMsg));
  });
  
  ws.on('message', (data) => {
    const msg = JSON.parse(data.toString());
    console.log('📨 Received:', JSON.stringify(msg, null, 2));
    
    if (msg.event === 'phx_reply' && msg.ref === '1') {
      if (msg.payload.status === 'ok') {
        console.log('✅ Successfully joined channel!');
        
        // Try to get connection stats
        const statsMsg = {
          topic: 'patterns:stats',
          event: 'get_connection_stats',
          payload: {},
          ref: '2',
          join_ref: '1'
        };
        
        console.log('\n📤 Requesting connection stats...');
        ws.send(JSON.stringify(statsMsg));
        
      } else {
        console.log('❌ Failed to join channel:', msg.payload);
        ws.close();
      }
    } else if (msg.event === 'phx_reply' && msg.ref === '2') {
      console.log('\n📊 Connection stats response:');
      if (msg.payload.status === 'ok') {
        console.log(JSON.stringify(msg.payload.response, null, 2));
      } else {
        console.log('Failed:', msg.payload);
      }
      
      // Clean up
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
testWebSocketDebug();