#!/bin/bash

# End-to-End Test for HNSW WebSocket Streaming using curl and wscat
# This is a simpler alternative that uses command-line tools

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
WS_URL="ws://localhost:4000/socket/websocket"
HTTP_URL="http://localhost:4000"

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}HNSW WebSocket End-to-End Test (curl version)${NC}"
echo -e "${BLUE}======================================================${NC}\n"

# Function to publish patterns via HTTP API or direct Elixir call
publish_patterns() {
    echo -e "${BLUE}[TEST]${NC} Publishing test patterns via Elixir..."
    
    elixir -e '
    {:ok, _} = Application.ensure_all_started(:autonomous_opponent_core)
    alias AutonomousOpponentV2Core.EventBus
    
    # Publish individual patterns
    patterns = [
      %{
        pattern_id: "curl_test_pattern_1",
        match_context: %{
          type: :test_pattern,
          confidence: 0.95,
          source: :curl_e2e_test
        },
        matched_event: %{
          type: :user_action,
          action: :click,
          timestamp: DateTime.utc_now()
        },
        triggered_at: DateTime.utc_now()
      },
      %{
        pattern_id: "curl_test_pattern_2",
        match_context: %{
          type: :test_pattern,
          confidence: 0.87,
          source: :curl_e2e_test
        },
        matched_event: %{
          type: :system_event,
          event: :memory_spike,
          timestamp: DateTime.utc_now()
        },
        triggered_at: DateTime.utc_now()
      }
    ]
    
    Enum.each(patterns, fn pattern ->
      EventBus.publish(:pattern_matched, pattern)
      IO.puts("Published pattern: #{pattern.pattern_id}")
    end)
    
    # Publish bulk patterns
    bulk_patterns = [
      %{type: :bulk_pattern_1, confidence: 0.88, timestamp: DateTime.utc_now()},
      %{type: :bulk_pattern_2, confidence: 0.91, timestamp: DateTime.utc_now()},
      %{type: :bulk_pattern_3, confidence: 0.79, timestamp: DateTime.utc_now()}
    ]
    
    EventBus.publish(:patterns_extracted, %{patterns: bulk_patterns, source: :curl_e2e_test})
    IO.puts("Published #{length(bulk_patterns)} bulk patterns")
    
    # Wait a bit for processing
    Process.sleep(2000)
    
    # Get stats
    alias AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge
    stats = PatternHNSWBridge.get_stats()
    IO.puts("\nHNSW Bridge Stats:")
    IO.inspect(stats, pretty: true)
    '
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[SUCCESS]${NC} Patterns published successfully"
    else
        echo -e "${RED}[ERROR]${NC} Failed to publish patterns"
        exit 1
    fi
}

# Function to test WebSocket with websocat (if available)
test_with_websocat() {
    if command -v websocat &> /dev/null; then
        echo -e "\n${BLUE}[TEST]${NC} Testing WebSocket connection with websocat..."
        
        # Create a test script for websocat
        cat > /tmp/ws_test_commands.txt << 'EOF'
{"topic":"patterns:stream","event":"phx_join","payload":{},"ref":"1"}
{"topic":"patterns:stream","event":"get_monitoring","payload":{},"ref":"2"}
{"topic":"patterns:stream","event":"query_similar","payload":{"vector":[0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0],"k":5},"ref":"3"}
EOF
        
        echo -e "${BLUE}[INFO]${NC} Connecting to WebSocket and sending commands..."
        timeout 10 websocat -t "$WS_URL" < /tmp/ws_test_commands.txt | while IFS= read -r line; do
            echo -e "${BLUE}[WS]${NC} $line"
            
            # Check for specific responses
            if [[ "$line" == *"phx_reply"* ]] && [[ "$line" == *"\"status\":\"ok\""* ]]; then
                echo -e "${GREEN}[SUCCESS]${NC} Received successful response"
            fi
            
            if [[ "$line" == *"pattern_indexed"* ]]; then
                echo -e "${GREEN}[SUCCESS]${NC} Received pattern_indexed event"
            fi
            
            if [[ "$line" == *"stats_update"* ]] || [[ "$line" == *"initial_stats"* ]]; then
                echo -e "${GREEN}[SUCCESS]${NC} Received stats update"
            fi
        done
        
        rm -f /tmp/ws_test_commands.txt
    else
        echo -e "${YELLOW}[WARN]${NC} websocat not found. Install with: brew install websocat"
    fi
}

# Function to test HTTP endpoints
test_http_endpoints() {
    echo -e "\n${BLUE}[TEST]${NC} Testing HTTP monitoring endpoints..."
    
    # Test health endpoint
    echo -e "${BLUE}[INFO]${NC} Checking health endpoint..."
    health_response=$(curl -s -w "\nHTTP_CODE:%{http_code}" "$HTTP_URL/health")
    http_code=$(echo "$health_response" | grep "HTTP_CODE:" | cut -d: -f2)
    
    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}[SUCCESS]${NC} Health endpoint returned 200"
        echo "$health_response" | grep -v "HTTP_CODE:" | jq . 2>/dev/null || echo "$health_response"
    else
        echo -e "${RED}[ERROR]${NC} Health endpoint returned $http_code"
    fi
    
    # Test metrics endpoint if available
    echo -e "\n${BLUE}[INFO]${NC} Checking metrics endpoint..."
    metrics_response=$(curl -s -w "\nHTTP_CODE:%{http_code}" "$HTTP_URL/metrics" 2>/dev/null || echo "HTTP_CODE:404")
    metrics_code=$(echo "$metrics_response" | grep "HTTP_CODE:" | cut -d: -f2)
    
    if [ "$metrics_code" = "200" ]; then
        echo -e "${GREEN}[SUCCESS]${NC} Metrics endpoint available"
    else
        echo -e "${YELLOW}[INFO]${NC} Metrics endpoint not available (expected if not configured)"
    fi
}

# Function to verify HNSW state
verify_hnsw_state() {
    echo -e "\n${BLUE}[TEST]${NC} Verifying HNSW index state..."
    
    elixir -e '
    {:ok, _} = Application.ensure_all_started(:autonomous_opponent_core)
    
    alias AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge
    alias AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex
    
    # Get comprehensive monitoring info
    monitoring = PatternHNSWBridge.get_monitoring_info()
    
    IO.puts("\n=== Pattern Processing Metrics ===")
    IO.inspect(monitoring.pattern_metrics, pretty: true)
    
    IO.puts("\n=== Backpressure Status ===")
    IO.inspect(monitoring.backpressure, pretty: true)
    
    IO.puts("\n=== HNSW Index Health ===")
    IO.inspect(monitoring.hnsw, pretty: true)
    
    IO.puts("\n=== System Health ===")
    IO.inspect(monitoring.health, pretty: true)
    
    # Check if patterns were actually indexed
    if monitoring.pattern_metrics.total_indexed > 0 do
      IO.puts("\n✓ Patterns successfully indexed: #{monitoring.pattern_metrics.total_indexed}")
      
      # Try a search
      test_vector = Enum.map(1..100, fn _ -> :rand.uniform() end)
      case HNSWIndex.search(:hnsw_index, test_vector, 5) do
        {:ok, results} ->
          IO.puts("✓ Search successful, found #{length(results)} similar patterns")
        {:error, reason} ->
          IO.puts("✗ Search failed: #{inspect(reason)}")
      end
    else
      IO.puts("\n✗ No patterns indexed yet")
    end
    '
}

# Function to test with wscat (Node.js WebSocket client)
test_with_wscat() {
    if command -v wscat &> /dev/null; then
        echo -e "\n${BLUE}[TEST]${NC} Testing WebSocket connection with wscat..."
        echo -e "${YELLOW}[INFO]${NC} This will open an interactive session. Type Ctrl+C to exit."
        echo -e "${YELLOW}[INFO]${NC} Try these commands:"
        echo '{"topic":"patterns:stream","event":"phx_join","payload":{},"ref":"1"}'
        echo '{"topic":"patterns:stream","event":"get_monitoring","payload":{},"ref":"2"}'
        
        wscat -c "$WS_URL"
    else
        echo -e "${YELLOW}[WARN]${NC} wscat not found. Install with: npm install -g wscat"
    fi
}

# Main test flow
main() {
    # Check if Phoenix server is running
    if ! curl -s "$HTTP_URL" > /dev/null 2>&1; then
        echo -e "${RED}[ERROR]${NC} Phoenix server is not running on $HTTP_URL"
        echo -e "${YELLOW}[INFO]${NC} Start the server with: iex -S mix phx.server"
        exit 1
    fi
    
    echo -e "${GREEN}[SUCCESS]${NC} Phoenix server is running"
    
    # Run tests
    publish_patterns
    test_http_endpoints
    test_with_websocat
    verify_hnsw_state
    
    echo -e "\n${GREEN}======================================================${NC}"
    echo -e "${GREEN}Test completed! Check the output above for results.${NC}"
    echo -e "${GREEN}======================================================${NC}"
    
    echo -e "\n${YELLOW}[INFO]${NC} For interactive WebSocket testing, you can also use:"
    echo -e "  - wscat -c $WS_URL"
    echo -e "  - websocat $WS_URL"
    echo -e "  - Or run the Node.js test: node test_hnsw_websocket_e2e.js"
}

# Run main
main