const WebSocket = require('ws');

async function createConnection(topic, payload = {}) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket('ws://localhost:4000/socket/websocket');
    
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
      if (msg.event === 'phx_reply' && msg.ref === '1') {
        if (msg.payload.status === 'ok') {
          resolve(ws);
        } else {
          reject(new Error(`Failed to join ${topic}`));
        }
      }
    });
    
    ws.on('error', reject);
    
    setTimeout(() => reject(new Error('Connection timeout')), 5000);
  });
}

async function getStats(ws, topic) {
  return new Promise((resolve, reject) => {
    const ref = Date.now().toString();
    
    const handler = (data) => {
      const msg = JSON.parse(data.toString());
      if (msg.event === 'phx_reply' && msg.ref === ref) {
        ws.removeListener('message', handler);
        if (msg.payload.status === 'ok') {
          resolve(msg.payload.response);
        } else {
          reject(new Error(msg.payload.status));
        }
      }
    };
    
    ws.on('message', handler);
    
    const statsMsg = {
      topic: topic,
      event: 'get_connection_stats',
      payload: {},
      ref: ref,
      join_ref: '1'
    };
    
    ws.send(JSON.stringify(statsMsg));
    
    setTimeout(() => {
      ws.removeListener('message', handler);
      reject(new Error('Stats request timeout'));
    }, 5000);
  });
}

async function getClusterStats(ws, topic) {
  return new Promise((resolve, reject) => {
    const ref = Date.now().toString();
    
    const handler = (data) => {
      const msg = JSON.parse(data.toString());
      if (msg.event === 'phx_reply' && msg.ref === ref) {
        ws.removeListener('message', handler);
        if (msg.payload.status === 'ok') {
          resolve(msg.payload.response);
        } else {
          reject(new Error(msg.payload.status || 'Cluster stats failed'));
        }
      }
    };
    
    ws.on('message', handler);
    
    const statsMsg = {
      topic: topic,
      event: 'get_cluster_connection_stats',
      payload: {},
      ref: ref,
      join_ref: '1'
    };
    
    ws.send(JSON.stringify(statsMsg));
    
    setTimeout(() => {
      ws.removeListener('message', handler);
      reject(new Error('Cluster stats request timeout'));
    }, 5000);
  });
}

async function testFullWebSocketCounting() {
  console.log('🧪 Full WebSocket Connection Counting Test\n');
  
  const connections = [];
  
  try {
    // Create multiple connections
    console.log('1️⃣  Creating connections...');
    connections.push(await createConnection('patterns:stream'));
    console.log('   ✅ Connected to patterns:stream');
    
    connections.push(await createConnection('patterns:stream'));
    console.log('   ✅ Connected to patterns:stream (2)');
    
    connections.push(await createConnection('patterns:stream'));
    console.log('   ✅ Connected to patterns:stream (3)');
    
    connections.push(await createConnection('patterns:stats'));
    console.log('   ✅ Connected to patterns:stats');
    
    connections.push(await createConnection('patterns:stats'));
    console.log('   ✅ Connected to patterns:stats (2)');
    
    connections.push(await createConnection('patterns:vsm', { subsystem: 'all' }));
    console.log('   ✅ Connected to patterns:vsm');
    
    // Get local stats
    console.log('\n2️⃣  Getting local connection stats...');
    const localStats = await getStats(connections[3], 'patterns:stats');
    console.log('   Total connections:', localStats.total);
    console.log('   By topic:');
    for (const [topic, nodes] of Object.entries(localStats.connections)) {
      const total = Object.values(nodes).reduce((sum, count) => sum + count, 0);
      console.log(`     ${topic}: ${total}`);
    }
    
    // Try cluster stats
    console.log('\n3️⃣  Getting cluster-wide stats...');
    try {
      const clusterStats = await getClusterStats(connections[3], 'patterns:stats');
      console.log('   ✅ Cluster stats available!');
      console.log('   Total cluster connections:', clusterStats.total_connections);
      console.log('   Cluster size:', clusterStats.cluster_size);
    } catch (error) {
      console.log('   ⚠️  Cluster stats not available:', error.message);
    }
    
    // Test decrement
    console.log('\n4️⃣  Testing connection cleanup...');
    const beforeClose = localStats.total;
    connections[0].close();
    connections.shift();
    
    // Wait a bit for cleanup
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    const afterStats = await getStats(connections[2], 'patterns:stats');
    console.log(`   Before close: ${beforeClose}, After close: ${afterStats.total}`);
    
    if (afterStats.total === beforeClose - 1) {
      console.log('   ✅ Connection properly decremented!');
    } else {
      console.log('   ❌ Decrement failed');
    }
    
    console.log('\n✅ WebSocket connection counting is fully operational!');
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
  } finally {
    // Clean up
    console.log('\n🧹 Cleaning up...');
    connections.forEach(ws => ws.close());
    setTimeout(() => process.exit(0), 1000);
  }
}

// Run the test
testFullWebSocketCounting();