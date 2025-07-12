#!/usr/bin/env node

/**
 * WebSocket Pattern Monitoring Test Client
 * 
 * Tests Issue #92 real-time pattern streaming from S4 Intelligence
 * to WebSocket clients through PatternsChannel.
 */

const WebSocket = require('ws');

// Configuration
const WS_URL = 'ws://localhost:4000/socket/websocket';
const PHOENIX_VSN = '2.0.0';

class PatternMonitoringClient {
  constructor() {
    this.socket = null;
    this.ref = 0;
    this.channels = new Map();
  }

  connect() {
    console.log('🔌 Connecting to Phoenix WebSocket...');
    
    this.socket = new WebSocket(WS_URL);
    
    this.socket.on('open', () => {
      console.log('✅ Connected to Phoenix WebSocket');
      this.joinPatternStreams();
    });
    
    this.socket.on('message', (data) => {
      this.handleMessage(JSON.parse(data.toString()));
    });
    
    this.socket.on('error', (error) => {
      console.error('❌ WebSocket error:', error.message);
    });
    
    this.socket.on('close', () => {
      console.log('🔌 WebSocket connection closed');
    });
  }

  getRef() {
    return ++this.ref;
  }

  send(message) {
    if (this.socket && this.socket.readyState === WebSocket.OPEN) {
      this.socket.send(JSON.stringify(message));
    }
  }

  joinPatternStreams() {
    // Join main pattern stream for Issue #92 events
    this.joinChannel('patterns:stream', {});
    
    // Join VSM pattern flow
    this.joinChannel('patterns:vsm', { subsystem: 'all' });
    
    // Join stats channel
    this.joinChannel('patterns:stats', {});
  }

  joinChannel(topic, payload) {
    const ref = this.getRef();
    
    console.log(`📡 Joining channel: ${topic}`);
    
    this.send([
      null,      // join_ref 
      ref,       // ref
      topic,     // topic
      'phx_join', // event
      payload    // payload
    ]);
    
    this.channels.set(topic, ref);
  }

  handleMessage([join_ref, ref, topic, event, payload]) {
    switch (event) {
      case 'phx_reply':
        this.handleReply(topic, payload);
        break;
      
      case 'pattern_detected':
        this.handlePatternDetected(payload);
        break;
      
      case 'temporal_pattern_detected':
        this.handleTemporalPattern(payload);
        break;
      
      case 'vsm_pattern_flow':
        this.handleVSMPatternFlow(payload);
        break;
      
      case 'algedonic_pattern':
        this.handleAlgedonicPattern(payload);
        break;
      
      case 'pattern_indexed':
        this.handlePatternIndexed(payload);
        break;
      
      case 'stats_update':
        this.handleStatsUpdate(payload);
        break;
      
      case 'initial_stats':
        this.handleInitialStats(payload);
        break;
      
      default:
        console.log(`📨 ${event}:`, payload);
    }
  }

  handleReply(topic, payload) {
    if (payload.status === 'ok') {
      console.log(`✅ Successfully joined ${topic}`);
    } else {
      console.error(`❌ Failed to join ${topic}:`, payload);
    }
  }

  handlePatternDetected(payload) {
    console.log(`🧠 PATTERN DETECTED [${payload.source}]:`, {
      type: payload.pattern_type,
      confidence: payload.confidence,
      severity: payload.severity,
      vsm_impact: payload.vsm_impact,
      timestamp: new Date(payload.timestamp).toLocaleTimeString()
    });
  }

  handleTemporalPattern(payload) {
    console.log(`⏰ TEMPORAL PATTERN:`, {
      type: payload.pattern_type,
      confidence: payload.confidence,
      frequency: payload.frequency,
      time_window: payload.time_window,
      timestamp: new Date(payload.timestamp).toLocaleTimeString()
    });
  }

  handleVSMPatternFlow(payload) {
    console.log(`🔄 VSM FLOW [${payload.subsystem}]:`, {
      type: payload.pattern_type,
      variety: payload.variety_type,
      direction: payload.flow_direction,
      confidence: payload.confidence,
      timestamp: new Date(payload.timestamp).toLocaleTimeString()
    });
  }

  handleAlgedonicPattern(payload) {
    console.log(`🚨 ALGEDONIC ALERT [${payload.source}]:`, {
      type: payload.type,
      intensity: payload.intensity,
      severity: payload.severity,
      timestamp: new Date(payload.timestamp).toLocaleTimeString()
    });
  }

  handlePatternIndexed(payload) {
    console.log(`📊 PATTERNS INDEXED:`, {
      count: payload.count,
      deduplicated: payload.deduplicated,
      source: payload.source,
      timestamp: new Date(payload.timestamp).toLocaleTimeString()
    });
  }

  handleStatsUpdate(payload) {
    console.log(`📈 STATS UPDATE:`, {
      connections: payload.connections?.total || 0,
      stream_count: payload.connections?.stream_count || 0,
      timestamp: new Date(payload.timestamp).toLocaleTimeString()
    });
  }

  handleInitialStats(payload) {
    console.log(`📊 INITIAL STATS:`, {
      monitoring: payload.monitoring,
      connections: payload.stats,
      timestamp: new Date(payload.timestamp).toLocaleTimeString()
    });
  }

  // Send test queries
  testQueries() {
    setTimeout(() => {
      console.log('\n🧪 Testing WebSocket queries...');
      
      // Test connection stats
      this.send([
        null,
        this.getRef(),
        'patterns:stats',
        'get_local_stats',
        {}
      ]);
      
      // Test monitoring info
      this.send([
        null,
        this.getRef(),
        'patterns:stream',
        'get_monitoring',
        {}
      ]);
      
    }, 2000);
  }

  disconnect() {
    console.log('🔌 Disconnecting...');
    if (this.socket) {
      this.socket.close();
    }
  }
}

// Run the test
console.log('🚀 Starting Pattern Monitoring Test Client');
console.log('   Testing Issue #92: Real-time pattern streaming from S4 Intelligence');
console.log('   Monitoring VSM pattern flow and algedonic signals\n');

const client = new PatternMonitoringClient();
client.connect();

// Test queries after connection
client.testQueries();

// Run for 30 seconds then cleanup
setTimeout(() => {
  console.log('\n✅ Test completed. Disconnecting...');
  client.disconnect();
  process.exit(0);
}, 30000);

// Handle Ctrl+C gracefully
process.on('SIGINT', () => {
  console.log('\n👋 Received SIGINT. Disconnecting...');
  client.disconnect();
  process.exit(0);
});