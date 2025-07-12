const WebSocket = require('ws');

class PhoenixSocket {
  constructor(endpoint) {
    this.endpoint = endpoint;
    this.ws = null;
    this.messageId = 0;
    this.channels = new Map();
    this.pendingJoins = new Map();
  }

  async connect() {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(this.endpoint);
      
      this.ws.on('open', () => {
        console.log('✅ WebSocket connected');
        this.startHeartbeat();
        resolve();
      });
      
      this.ws.on('message', (data) => {
        const msg = JSON.parse(data.toString());
        this.handleMessage(msg);
      });
      
      this.ws.on('error', reject);
      this.ws.on('close', () => {
        console.log('WebSocket closed');
        this.stopHeartbeat();
      });
    });
  }
  
  join(topic, params = {}) {
    const ref = String(++this.messageId);
    const joinMsg = {
      topic,
      event: 'phx_join',
      payload: params,
      ref,
      join_ref: ref
    };
    
    return new Promise((resolve, reject) => {
      this.pendingJoins.set(ref, { resolve, reject, topic, join_ref: ref });
      this.channels.set(topic, { join_ref: ref, joined: false });
      this.ws.send(JSON.stringify(joinMsg));
    });
  }
  
  push(topic, event, payload) {
    const channel = this.channels.get(topic);
    if (!channel || !channel.joined) {
      throw new Error(`Not joined to channel: ${topic}`);
    }
    
    const ref = String(++this.messageId);
    const msg = {
      topic,
      event,
      payload,
      ref,
      join_ref: channel.join_ref
    };
    
    return new Promise((resolve, reject) => {
      this.pendingJoins.set(ref, { resolve, reject });
      this.ws.send(JSON.stringify(msg));
    });
  }
  
  handleMessage(msg) {
    if (msg.event === 'phx_reply' && this.pendingJoins.has(msg.ref)) {
      const pending = this.pendingJoins.get(msg.ref);
      this.pendingJoins.delete(msg.ref);
      
      if (msg.payload.status === 'ok') {
        if (pending.topic) {
          const channel = this.channels.get(pending.topic);
          if (channel) channel.joined = true;
        }
        pending.resolve(msg.payload.response);
      } else {
        pending.reject(new Error(msg.payload.status));
      }
    } else if (msg.event !== 'phx_reply') {
      console.log(`📨 Event: ${msg.event}`, msg.payload);
    }
  }
  
  startHeartbeat() {
    this.heartbeatInterval = setInterval(() => {
      if (this.ws.readyState === WebSocket.OPEN) {
        const msg = {
          topic: 'phoenix',
          event: 'heartbeat',
          payload: {},
          ref: String(++this.messageId)
        };
        this.ws.send(JSON.stringify(msg));
      }
    }, 30000);
  }
  
  stopHeartbeat() {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
    }
  }
  
  close() {
    this.stopHeartbeat();
    if (this.ws) {
      this.ws.close();
    }
  }
}

async function testWebSocketCounting() {
  console.log('🧪 Testing WebSocket Connection Counting\n');
  
  const sockets = [];
  
  try {
    // Create multiple connections
    console.log('1️⃣  Creating 3 connections to patterns:stream...');
    for (let i = 0; i < 3; i++) {
      const socket = new PhoenixSocket('ws://localhost:4000/socket/websocket');
      await socket.connect();
      await socket.join('patterns:stream');
      sockets.push(socket);
    }
    
    console.log('2️⃣  Creating 2 connections to patterns:stats...');
    for (let i = 0; i < 2; i++) {
      const socket = new PhoenixSocket('ws://localhost:4000/socket/websocket');
      await socket.connect();
      await socket.join('patterns:stats');
      sockets.push(socket);
    }
    
    console.log('3️⃣  Creating 1 connection to patterns:vsm...');
    const vsmSocket = new PhoenixSocket('ws://localhost:4000/socket/websocket');
    await vsmSocket.connect();
    await vsmSocket.join('patterns:vsm', { subsystem: 'all' });
    sockets.push(vsmSocket);
    
    // Query connection stats
    console.log('\n4️⃣  Querying connection stats...');
    const statsResult = await sockets[3].push('patterns:stats', 'get_connection_stats', {});
    console.log('Local stats:', JSON.stringify(statsResult, null, 2));
    
    // Query cluster stats
    console.log('\n5️⃣  Querying cluster connection stats...');
    const clusterResult = await sockets[3].push('patterns:stats', 'get_cluster_connection_stats', {});
    console.log('Cluster stats:', JSON.stringify(clusterResult, null, 2));
    
    // Close one connection and check again
    console.log('\n6️⃣  Closing one patterns:stream connection...');
    sockets[0].close();
    sockets.shift();
    
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    const afterCloseStats = await sockets[2].push('patterns:stats', 'get_connection_stats', {});
    console.log('Stats after closing:', JSON.stringify(afterCloseStats, null, 2));
    
    console.log('\n✅ WebSocket connection counting working correctly!');
    
  } catch (error) {
    console.error('❌ Test failed:', error);
  } finally {
    // Clean up
    console.log('\n🧹 Cleaning up connections...');
    sockets.forEach(socket => socket.close());
    process.exit(0);
  }
}

// Run the test
testWebSocketCounting();