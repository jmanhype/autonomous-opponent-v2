# HNSW WebSocket End-to-End Testing

This directory contains comprehensive end-to-end tests that verify the HNSW WebSocket streaming functionality is actually working. The tests verify the complete data flow from EventBus publishing through HNSW indexing to WebSocket streaming.

## Test Scripts

### 1. Node.js Test (`test_hnsw_websocket_e2e.js`)

The most comprehensive test using Node.js and the `ws` WebSocket library.

**Prerequisites:**
```bash
npm install ws
```

**Run:**
```bash
node test_hnsw_websocket_e2e.js
```

**Features:**
- Full WebSocket protocol support
- Comprehensive message handling
- Detailed test output with color coding
- Tests all major functionality

### 2. Bash/curl Test (`test_hnsw_websocket_curl.sh`)

A simpler test using command-line tools like `curl` and optionally `websocat` or `wscat`.

**Prerequisites (optional but recommended):**
```bash
# Install websocat (macOS)
brew install websocat

# Or install wscat
npm install -g wscat
```

**Run:**
```bash
./test_hnsw_websocket_curl.sh
```

**Features:**
- Uses standard Unix tools
- Tests HTTP endpoints
- Can use websocat for WebSocket testing
- Direct Elixir integration for publishing

### 3. Python Test (`test_hnsw_websocket_python.py`)

A Python-based test using the `websockets` library.

**Prerequisites:**
```bash
pip3 install websockets
```

**Run:**
```bash
python3 test_hnsw_websocket_python.py
# or
./test_hnsw_websocket_python.py
```

**Features:**
- Async/await support
- Clean Python implementation
- Good for Python developers
- Comprehensive test coverage

## What the Tests Verify

All test scripts verify the following end-to-end flow:

1. **WebSocket Connection**: Connects to `ws://localhost:4000/socket/websocket`

2. **Channel Join**: Joins the `patterns:stream` Phoenix channel

3. **Pattern Publishing**: Publishes test patterns via EventBus:
   - Individual pattern events (`pattern_matched`)
   - Bulk pattern events (`patterns_extracted`)

4. **HNSW Indexing**: Verifies patterns are indexed in the HNSW vector store

5. **WebSocket Streaming**: Confirms patterns are streamed via WebSocket:
   - `pattern_indexed` events
   - `pattern_matched` events
   - Statistics updates

6. **Pattern Search**: Tests vector similarity search functionality

7. **Monitoring**: Verifies monitoring endpoints return proper data:
   - Pattern metrics
   - Backpressure status
   - Health information

8. **Cluster Support**: Tests distributed pattern aggregation (if available)

## Expected Output

A successful test run will show:
- ✓ WebSocket connection established
- ✓ Channel joined successfully
- ✓ Test patterns published
- ✓ Patterns indexed in HNSW
- ✓ Pattern events received via WebSocket
- ✓ Search functionality working
- ✓ Monitoring data available

## Prerequisites

Before running any test:

1. **Start the Phoenix server:**
   ```bash
   iex -S mix phx.server
   ```

2. **Ensure RabbitMQ is running (if AMQP is enabled):**
   ```bash
   rabbitmq-server
   ```

3. **Verify the HNSW bridge is running:**
   ```elixir
   # In iex console
   Process.whereis(AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge)
   ```

## Troubleshooting

### WebSocket Connection Failed
- Ensure Phoenix server is running on port 4000
- Check `config/dev.exs` for WebSocket configuration
- Verify no firewall blocking WebSocket connections

### No Patterns Indexed
- Check if PatternHNSWBridge is running
- Look for errors in Phoenix console
- Verify EventBus is working: `AutonomousOpponentV2Core.EventBus.list_subscribers()`

### Search Returns No Results
- Ensure patterns were indexed first
- Check HNSW index stats
- Verify vector dimensions match (should be 100)

### Monitoring Returns Errors
- Check if all VSM components are started
- Verify supervisor tree is complete
- Look for crashed processes in logs

## Manual WebSocket Testing

For interactive testing, you can use:

```bash
# Using wscat
wscat -c ws://localhost:4000/socket/websocket

# Then send Phoenix messages:
{"topic":"patterns:stream","event":"phx_join","payload":{},"ref":"1"}
{"topic":"patterns:stream","event":"get_monitoring","payload":{},"ref":"2"}

# Using websocat
websocat ws://localhost:4000/socket/websocket
```

## Integration with CI/CD

These tests can be integrated into your CI/CD pipeline:

```yaml
# Example GitHub Actions
- name: Start Phoenix Server
  run: |
    mix deps.get
    mix compile
    mix phx.server &
    sleep 10  # Wait for server to start

- name: Run E2E Tests
  run: |
    npm install ws
    node test_hnsw_websocket_e2e.js
```

## Performance Testing

To test performance and load:

1. Modify the test scripts to publish more patterns
2. Adjust batch sizes and timeouts
3. Monitor memory and CPU usage
4. Check backpressure activation thresholds

## Contributing

When adding new tests:
1. Follow the existing pattern of colored output
2. Test both success and failure cases
3. Include timeout handling
4. Verify actual data flow, not just API responses
5. Update this README with new test coverage