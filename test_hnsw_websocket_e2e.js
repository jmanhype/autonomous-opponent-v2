#!/usr/bin/env node

/**
 * End-to-End HNSW WebSocket Streaming Test
 * 
 * This test verifies the complete data flow:
 * EventBus -> PatternHNSWBridge -> HNSW Index -> WebSocket -> Client
 */

const WebSocket = require('ws');
const http = require('http');

const WS_URL = 'ws://127.0.0.1:4000/socket/websocket';
const HTTP_URL = 'http://127.0.0.1:4000';

// ANSI color codes
const colors = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m'
};

function log(message, color = 'reset') {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

class HNSWWebSocketTest {
  constructor() {
    this.ws = null;
    this.messageRef = 0;
    this.receivedMessages = [];
    this.testResults = {
      connection: false,
      channelJoin: false,
      patternIndexed: false,
      patternMatched: false,
      searchResults: false,
      monitoring: false,
      algedonicSignal: false
    };
  }

  async run() {
    log('\n╔══════════════════════════════════════════════════════════════╗', 'bright');
    log('║         HNSW WebSocket Streaming End-to-End Test            ║', 'bright');
    log('╚══════════════════════════════════════════════════════════════╝\n', 'bright');

    try {
      // 1. Test server health
      await this.testServerHealth();
      
      // 2. Connect to WebSocket
      await this.connectWebSocket();
      
      // 3. Join pattern stream channel
      await this.joinPatternChannel();
      
      // 4. Test pattern search
      await this.testPatternSearch();
      
      // 5. Test monitoring
      await this.testMonitoring();
      
      // 6. Publish test patterns
      await this.publishTestPatterns();
      
      // 7. Wait for pattern streaming
      await this.waitForPatterns();
      
      // 8. Print results
      this.printResults();
      
    } catch (error) {
      log(`\n❌ Test failed: ${error.message}`, 'red');
    } finally {
      if (this.ws) {
        this.ws.close();
      }
    }
  }

  async testServerHealth() {
    log('🏥 Testing server health...', 'cyan');
    
    return new Promise((resolve, reject) => {
      http.get(`${HTTP_URL}/health`, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          try {
            const health = JSON.parse(data);
            log(`   Server status: ${health.status}`, health.status === 'healthy' ? 'green' : 'yellow');
            log(`   Process count: ${health.system.process_count}`, 'green');
            resolve();
          } catch (e) {
            reject(new Error('Failed to parse health response'));
          }
        });
      }).on('error', reject);
    });
  }

  async connectWebSocket() {
    log('\n🔌 Connecting to WebSocket...', 'cyan');
    
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(WS_URL);
      
      this.ws.on('open', () => {
        log('   ✅ WebSocket connected!', 'green');
        this.testResults.connection = true;
        resolve();
      });
      
      this.ws.on('error', (error) => {
        reject(new Error(`WebSocket connection failed: ${error.message}`));
      });
      
      this.ws.on('message', (data) => {
        this.handleMessage(data.toString());
      });
    });
  }

  async joinPatternChannel() {
    log('\n📡 Joining patterns:stream channel...', 'cyan');
    
    const joinMsg = {
      topic: 'patterns:stream',
      event: 'phx_join',
      payload: {},
      ref: String(++this.messageRef)
    };
    
    return this.sendAndWaitForReply(joinMsg, 'channelJoin');
  }

  async testPatternSearch() {
    log('\n🔍 Testing pattern search...', 'cyan');
    
    const searchMsg = {
      topic: 'patterns:stream',
      event: 'query_similar',
      payload: {
        vector: Array(100).fill(0.5),
        k: 5
      },
      ref: String(++this.messageRef)
    };
    
    return this.sendAndWaitForReply(searchMsg, 'searchResults');
  }

  async testMonitoring() {
    log('\n📊 Testing monitoring endpoint...', 'cyan');
    
    const monitorMsg = {
      topic: 'patterns:stream',
      event: 'get_monitoring',
      payload: {},
      ref: String(++this.messageRef)
    };
    
    return this.sendAndWaitForReply(monitorMsg, 'monitoring');
  }

  async publishTestPatterns() {
    log('\n🎯 Publishing test patterns via HTTP API...', 'cyan');
    
    // Since we can't directly call EventBus from outside, we need to trigger
    // patterns through an API endpoint or wait for natural patterns
    
    // For now, we'll simulate by sending a message that might trigger patterns
    const testPatterns = [
      {
        pattern_id: `e2e_test_${Date.now()}_1`,
        confidence: 0.95,
        type: 'error_pattern'
      },
      {
        pattern_id: `e2e_test_${Date.now()}_2`,
        confidence: 0.88,
        type: 'performance_pattern'
      }
    ];
    
    log(`   📤 Would publish ${testPatterns.length} test patterns`, 'yellow');
    log('   ⚠️  Note: Direct EventBus access requires running inside the app', 'yellow');
  }

  async waitForPatterns() {
    log('\n⏳ Waiting for pattern events (5 seconds)...', 'cyan');
    
    return new Promise(resolve => {
      setTimeout(() => {
        if (this.receivedMessages.some(msg => msg.event === 'pattern_indexed')) {
          this.testResults.patternIndexed = true;
        }
        if (this.receivedMessages.some(msg => msg.event === 'pattern_matched')) {
          this.testResults.patternMatched = true;
        }
        if (this.receivedMessages.some(msg => msg.event === 'algedonic_pattern')) {
          this.testResults.algedonicSignal = true;
        }
        resolve();
      }, 5000);
    });
  }

  sendAndWaitForReply(message, resultKey) {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error(`Timeout waiting for reply to ref ${message.ref}`));
      }, 3000);
      
      const handler = (data) => {
        const msg = JSON.parse(data);
        if (msg.ref === message.ref && msg.event === 'phx_reply') {
          clearTimeout(timeout);
          
          if (msg.payload.status === 'ok') {
            log(`   ✅ ${message.event} successful`, 'green');
            if (msg.payload.response) {
              this.logResponse(msg.payload.response);
            }
            this.testResults[resultKey] = true;
            resolve();
          } else {
            reject(new Error(`${message.event} failed: ${JSON.stringify(msg.payload)}`));
          }
        }
      };
      
      this.ws.once('message', handler);
      this.ws.send(JSON.stringify(message));
      log(`   📤 Sent ${message.event} request`, 'blue');
    });
  }

  handleMessage(data) {
    try {
      const msg = JSON.parse(data);
      this.receivedMessages.push(msg);
      
      // Log specific events
      switch (msg.event) {
        case 'pattern_indexed':
          log(`   📈 Pattern indexed: ${msg.payload.count} patterns`, 'green');
          break;
        case 'pattern_matched':
          log(`   🎯 Pattern matched: ${msg.payload.pattern_id} (${msg.payload.confidence})`, 'green');
          break;
        case 'algedonic_pattern':
          log(`   🚨 Algedonic signal: ${msg.payload.type} - ${msg.payload.intensity}`, 'red');
          break;
        case 'stats_update':
          log(`   📊 Stats update received`, 'blue');
          break;
      }
    } catch (e) {
      // Ignore parse errors
    }
  }

  logResponse(response) {
    if (response.results && Array.isArray(response.results)) {
      log(`      Found ${response.results.length} similar patterns`, 'blue');
    } else if (response.pattern_metrics) {
      log(`      Total patterns: ${response.pattern_metrics.total_indexed || 0}`, 'blue');
      log(`      Success rate: ${(response.pattern_metrics.success_rate * 100).toFixed(1)}%`, 'blue');
    }
  }

  printResults() {
    log('\n' + '═'.repeat(60), 'bright');
    log('📊 TEST RESULTS SUMMARY', 'bright');
    log('═'.repeat(60) + '\n', 'bright');
    
    let passed = 0;
    let total = 0;
    
    for (const [test, result] of Object.entries(this.testResults)) {
      total++;
      if (result) passed++;
      
      const status = result ? '✅' : '❌';
      const color = result ? 'green' : 'red';
      log(`${status} ${this.formatTestName(test)}: ${result ? 'PASSED' : 'FAILED'}`, color);
    }
    
    log('\n' + '═'.repeat(60), 'bright');
    
    if (passed === total) {
      log('🎉 ALL TESTS PASSED! HNSW WebSocket streaming is fully operational!', 'green');
    } else {
      log(`⚠️  ${passed}/${total} tests passed. Some features may not be working.`, 'yellow');
    }
    
    log('═'.repeat(60) + '\n', 'bright');
  }

  formatTestName(name) {
    return name
      .replace(/([A-Z])/g, ' $1')
      .trim()
      .split(' ')
      .map(word => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ');
  }
}

// Check if ws module is installed
try {
  require.resolve('ws');
} catch (e) {
  log('❌ WebSocket module not found. Please run: npm install ws', 'red');
  process.exit(1);
}

// Run the test
const test = new HNSWWebSocketTest();
test.run().catch(error => {
  log(`\n❌ Unhandled error: ${error.message}`, 'red');
  process.exit(1);
});