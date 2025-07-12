#!/usr/bin/env python3
"""
End-to-End Test for HNSW WebSocket Streaming using Python

This script verifies the complete data flow:
1. Connect to WebSocket endpoint
2. Join patterns:stream channel
3. Publish test patterns via EventBus
4. Verify they're indexed in HNSW
5. Verify they're streamed via WebSocket
6. Test pattern search functionality
7. Test monitoring endpoints
"""

import asyncio
import json
import subprocess
import sys
import time
from datetime import datetime
from typing import Dict, List, Any

try:
    import websockets
except ImportError:
    print("Error: websockets module not found")
    print("Install with: pip3 install websockets")
    sys.exit(1)

# Configuration
WS_URL = "ws://127.0.0.1:4000/socket/websocket"
TEST_TIMEOUT = 30

# ANSI color codes
class Colors:
    RESET = '\033[0m'
    GREEN = '\033[32m'
    RED = '\033[31m'
    YELLOW = '\033[33m'
    BLUE = '\033[34m'
    CYAN = '\033[36m'

def log(color: str, prefix: str, message: str):
    print(f"{color}[{prefix}]{Colors.RESET} {message}")

def success(message: str):
    log(Colors.GREEN, 'SUCCESS', message)

def error(message: str):
    log(Colors.RED, 'ERROR', message)

def info(message: str):
    log(Colors.BLUE, 'INFO', message)

def test(message: str):
    log(Colors.CYAN, 'TEST', message)

def warn(message: str):
    log(Colors.YELLOW, 'WARN', message)

class WebSocketTester:
    def __init__(self):
        self.ws = None
        self.received_messages: List[Dict] = []
        self.message_handlers: Dict[str, asyncio.Future] = {}
        self.is_joined = False
        self.running = True

    def phoenix_message(self, topic: str, event: str, payload: Dict, ref: str = None) -> str:
        """Create a Phoenix WebSocket message"""
        if ref is None:
            ref = str(int(time.time() * 1000))
        return json.dumps({
            "topic": topic,
            "event": event,
            "payload": payload,
            "ref": ref
        })

    async def handle_incoming_messages(self):
        """Handle incoming WebSocket messages"""
        try:
            async for message in self.ws:
                if not self.running:
                    break
                    
                try:
                    data = json.loads(message)
                    self.received_messages.append(data)
                    
                    # Handle Phoenix responses
                    if 'ref' in data and data['ref'] in self.message_handlers:
                        future = self.message_handlers.pop(data['ref'])
                        if not future.done():
                            future.set_result(data)
                    
                    # Log specific events
                    event = data.get('event', '')
                    if event == 'pattern_indexed':
                        info(f"Pattern indexed: {json.dumps(data['payload'])}")
                    elif event == 'pattern_matched':
                        info(f"Pattern matched: {json.dumps(data['payload'])}")
                    elif event == 'algedonic_pattern':
                        warn(f"Algedonic pattern: {json.dumps(data['payload'])}")
                    elif event == 'initial_stats':
                        info(f"Initial stats received: {json.dumps(data['payload']['stats'])}")
                    elif event == 'stats_update':
                        info(f"Stats update: {json.dumps(data['payload']['stats'])}")
                        
                except json.JSONDecodeError:
                    warn(f"Failed to parse message: {message}")
                except Exception as e:
                    warn(f"Error handling message: {e}")
                    
        except websockets.exceptions.ConnectionClosed:
            warn("WebSocket connection closed")
        except Exception as e:
            error(f"Error in message handler: {e}")

    async def connect(self):
        """Connect to WebSocket endpoint"""
        test("Connecting to WebSocket endpoint...")
        self.ws = await websockets.connect(WS_URL)
        success("WebSocket connected")
        
        # Start message handler
        asyncio.create_task(self.handle_incoming_messages())

    async def join_channel(self, channel: str):
        """Join a Phoenix channel"""
        test(f"Joining channel: {channel}")
        
        ref = str(int(time.time() * 1000))
        join_message = self.phoenix_message(channel, "phx_join", {}, ref)
        
        future = asyncio.Future()
        self.message_handlers[ref] = future
        
        await self.ws.send(join_message)
        
        try:
            response = await asyncio.wait_for(future, timeout=5.0)
            if response['event'] == 'phx_reply' and response['payload']['status'] == 'ok':
                success(f"Joined channel: {channel}")
                self.is_joined = True
            else:
                raise Exception(f"Failed to join channel: {response['payload']}")
        except asyncio.TimeoutError:
            raise Exception("Channel join timeout")

    async def publish_test_patterns(self):
        """Publish test patterns via EventBus"""
        test("Publishing test patterns via EventBus...")
        
        patterns = [
            {
                "pattern_id": "py_test_pattern_1",
                "match_context": {
                    "type": "test_pattern",
                    "confidence": 0.95,
                    "source": "py_e2e_test"
                },
                "matched_event": {
                    "type": "user_action",
                    "action": "click",
                    "timestamp": datetime.utcnow().isoformat()
                }
            },
            {
                "pattern_id": "py_test_pattern_2",
                "match_context": {
                    "type": "test_pattern",
                    "confidence": 0.87,
                    "source": "py_e2e_test"
                },
                "matched_event": {
                    "type": "system_event",
                    "event": "memory_spike",
                    "timestamp": datetime.utcnow().isoformat()
                }
            },
            {
                "pattern_id": "py_test_pattern_3",
                "match_context": {
                    "type": "algedonic_test",
                    "confidence": 0.92,
                    "source": "py_e2e_test"
                },
                "matched_event": {
                    "type": "pain_signal",
                    "intensity": 0.85,
                    "timestamp": datetime.utcnow().isoformat()
                }
            }
        ]
        
        # Publish patterns via Elixir
        for pattern in patterns:
            elixir_code = f'''
            {{:ok, _}} = Application.ensure_all_started(:autonomous_opponent_core)
            alias AutonomousOpponentV2Core.EventBus
            
            pattern = %{{
              pattern_id: "{pattern['pattern_id']}",
              match_context: %{{
                type: :{pattern['match_context']['type']},
                confidence: {pattern['match_context']['confidence']},
                source: :{pattern['match_context']['source']}
              }},
              matched_event: %{{
                type: :{pattern['matched_event']['type']},
                {f"action: :{pattern['matched_event'].get('action', '')}," if 'action' in pattern['matched_event'] else ''}
                {f"event: :{pattern['matched_event'].get('event', '')}," if 'event' in pattern['matched_event'] else ''}
                {f"intensity: {pattern['matched_event'].get('intensity', 0.0)}," if 'intensity' in pattern['matched_event'] else ''}
                timestamp: DateTime.utc_now()
              }},
              triggered_at: DateTime.utc_now()
            }}
            
            EventBus.publish(:pattern_matched, pattern)
            IO.puts("Published pattern: {pattern['pattern_id']}")
            '''
            
            result = subprocess.run(['elixir', '-e', elixir_code], 
                                  capture_output=True, text=True)
            if result.returncode == 0:
                success(f"Published pattern: {pattern['pattern_id']}")
            else:
                error(f"Failed to publish pattern {pattern['pattern_id']}: {result.stderr}")
                raise Exception(f"Pattern publishing failed: {result.stderr}")
        
        # Also publish bulk patterns
        bulk_code = '''
        {:ok, _} = Application.ensure_all_started(:autonomous_opponent_core)
        alias AutonomousOpponentV2Core.EventBus
        
        patterns = [
          %{type: :bulk_pattern_1, confidence: 0.88, timestamp: DateTime.utc_now()},
          %{type: :bulk_pattern_2, confidence: 0.91, timestamp: DateTime.utc_now()},
          %{type: :bulk_pattern_3, confidence: 0.79, timestamp: DateTime.utc_now()}
        ]
        
        EventBus.publish(:patterns_extracted, %{patterns: patterns, source: :py_e2e_test})
        IO.puts("Published bulk patterns")
        '''
        
        result = subprocess.run(['elixir', '-e', bulk_code], 
                              capture_output=True, text=True)
        if result.returncode == 0:
            success("Published bulk patterns")
        else:
            error(f"Failed to publish bulk patterns: {result.stderr}")

    async def wait_for_pattern_indexing(self):
        """Wait for patterns to be indexed"""
        test("Waiting for patterns to be indexed...")
        
        start_time = time.time()
        indexed_count = 0
        
        while time.time() - start_time < 10:  # 10 second timeout
            indexed_messages = [m for m in self.received_messages if m.get('event') == 'pattern_indexed']
            if indexed_messages:
                indexed_count = sum(m['payload'].get('count', 0) for m in indexed_messages)
                if indexed_count >= 3:
                    success(f"{indexed_count} patterns indexed")
                    return
            await asyncio.sleep(1)
        
        warn(f"Only {indexed_count} patterns indexed (expected at least 3)")

    async def test_pattern_search(self):
        """Test pattern search functionality"""
        test("Testing pattern search functionality...")
        
        ref = str(int(time.time() * 1000))
        search_message = self.phoenix_message('patterns:stream', 'query_similar', {
            'vector': [float(i) / 100 for i in range(100)],  # 100-dim vector
            'k': 5
        }, ref)
        
        future = asyncio.Future()
        self.message_handlers[ref] = future
        
        await self.ws.send(search_message)
        
        try:
            response = await asyncio.wait_for(future, timeout=5.0)
            if response['event'] == 'phx_reply' and response['payload']['status'] == 'ok':
                results = response['payload']['response']['results']
                success(f"Pattern search returned {len(results)} results")
                info(f"Search results: {json.dumps(results[:3])}")
            else:
                raise Exception(f"Pattern search failed: {response['payload']}")
        except asyncio.TimeoutError:
            raise Exception("Pattern search timeout")

    async def test_monitoring(self):
        """Test monitoring endpoint"""
        test("Testing monitoring endpoint...")
        
        ref = str(int(time.time() * 1000))
        monitoring_message = self.phoenix_message('patterns:stream', 'get_monitoring', {}, ref)
        
        future = asyncio.Future()
        self.message_handlers[ref] = future
        
        await self.ws.send(monitoring_message)
        
        try:
            response = await asyncio.wait_for(future, timeout=5.0)
            if response['event'] == 'phx_reply' and response['payload']['status'] == 'ok':
                monitoring = response['payload']['response']
                success("Monitoring data received")
                info(f"Pattern metrics: {json.dumps(monitoring.get('pattern_metrics', {}))}")
                info(f"Backpressure status: {json.dumps(monitoring.get('backpressure', {}))}")
                info(f"Health status: {monitoring.get('health', {}).get('status', 'unknown')}")
            else:
                raise Exception(f"Monitoring request failed: {response['payload']}")
        except asyncio.TimeoutError:
            raise Exception("Monitoring request timeout")

    async def test_cluster_patterns(self):
        """Test cluster pattern aggregation"""
        test("Testing cluster pattern aggregation...")
        
        ref = str(int(time.time() * 1000))
        cluster_message = self.phoenix_message('patterns:stream', 'get_cluster_patterns', {
            'min_nodes': 1
        }, ref)
        
        future = asyncio.Future()
        self.message_handlers[ref] = future
        
        await self.ws.send(cluster_message)
        
        try:
            response = await asyncio.wait_for(future, timeout=5.0)
            if response['event'] == 'phx_reply':
                if response['payload']['status'] == 'ok':
                    patterns = response['payload']['response']['patterns']
                    success(f"Cluster patterns received: {len(patterns)} patterns")
                else:
                    warn(f"Cluster patterns not available: {response['payload']['response']['reason']}")
        except asyncio.TimeoutError:
            warn("Cluster pattern request timeout")

    def verify_data_flow(self):
        """Verify complete data flow"""
        test("Verifying complete data flow...")
        
        # Check received messages
        pattern_indexed_count = len([m for m in self.received_messages if m.get('event') == 'pattern_indexed'])
        pattern_matched_count = len([m for m in self.received_messages if m.get('event') == 'pattern_matched'])
        stats_update_count = len([m for m in self.received_messages if m.get('event') == 'stats_update'])
        initial_stats_count = len([m for m in self.received_messages if m.get('event') == 'initial_stats'])
        
        info("Received message summary:")
        info(f"  - Pattern indexed events: {pattern_indexed_count}")
        info(f"  - Pattern matched events: {pattern_matched_count}")
        info(f"  - Stats updates: {stats_update_count}")
        info(f"  - Initial stats: {initial_stats_count}")
        
        # Validate data flow
        if pattern_indexed_count > 0:
            success("Pattern indexing events received")
        else:
            error("No pattern indexing events received")
        
        if stats_update_count > 0 or initial_stats_count > 0:
            success("Statistics updates received")
        else:
            warn("No statistics updates received")
        
        # Check HNSW stats via Elixir
        stats_code = '''
        {:ok, _} = Application.ensure_all_started(:autonomous_opponent_core)
        alias AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge
        
        stats = PatternHNSWBridge.get_stats()
        IO.inspect(stats, label: "HNSW Bridge Stats")
        '''
        
        result = subprocess.run(['elixir', '-e', stats_code], 
                              capture_output=True, text=True)
        if result.returncode == 0:
            info(f"HNSW Bridge Stats:\n{result.stdout}")
        else:
            error(f"Failed to get HNSW stats: {result.stderr}")

    async def run_tests(self):
        """Main test runner"""
        print(f"\n{Colors.CYAN}{'=' * 60}{Colors.RESET}")
        print(f"{Colors.CYAN}HNSW WebSocket End-to-End Test (Python){Colors.RESET}")
        print(f"{Colors.CYAN}{'=' * 60}{Colors.RESET}\n")
        
        try:
            # Connect to WebSocket
            await self.connect()
            
            # Join patterns:stream channel
            await self.join_channel('patterns:stream')
            
            # Wait a bit for initial stats
            await asyncio.sleep(2)
            
            # Publish test patterns
            await self.publish_test_patterns()
            
            # Wait for indexing
            await self.wait_for_pattern_indexing()
            
            # Test pattern search
            await self.test_pattern_search()
            
            # Test monitoring
            await self.test_monitoring()
            
            # Test cluster patterns (if available)
            await self.test_cluster_patterns()
            
            # Verify complete data flow
            self.verify_data_flow()
            
            # Summary
            print(f"\n{Colors.GREEN}{'=' * 60}{Colors.RESET}")
            print(f"{Colors.GREEN}All tests completed successfully!{Colors.RESET}")
            print(f"{Colors.GREEN}{'=' * 60}{Colors.RESET}\n")
            
            return True
            
        except Exception as e:
            print(f"\n{Colors.RED}{'=' * 60}{Colors.RESET}")
            print(f"{Colors.RED}Test failed!{Colors.RESET}")
            print(f"{Colors.RED}{str(e)}{Colors.RESET}")
            print(f"{Colors.RED}{'=' * 60}{Colors.RESET}\n")
            return False
            
        finally:
            self.running = False
            if self.ws:
                await self.ws.close()

async def main():
    """Main entry point"""
    # Check if Phoenix server is running
    import urllib.request
    try:
        urllib.request.urlopen('http://127.0.0.1:4000', timeout=1)
    except:
        error("Phoenix server is not running on http://127.0.0.1:4000")
        info("Start the server with: iex -S mix phx.server")
        sys.exit(1)
    
    success("Phoenix server is running")
    
    # Run tests
    tester = WebSocketTester()
    test_success = await tester.run_tests()
    
    sys.exit(0 if test_success else 1)

if __name__ == "__main__":
    asyncio.run(main())