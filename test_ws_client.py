#!/usr/bin/env python3
"""
Simple WebSocket test client for HNSW pattern streaming
"""
import asyncio
import json
import websockets
import uuid

async def test_pattern_streaming():
    uri = "ws://localhost:4000/socket/websocket"
    
    try:
        async with websockets.connect(uri) as websocket:
            print("✅ Connected to WebSocket!")
            
            # Join patterns:stream channel
            join_msg = {
                "topic": "patterns:stream",
                "event": "phx_join",
                "payload": {},
                "ref": "1"
            }
            await websocket.send(json.dumps(join_msg))
            print("📤 Sent join request for patterns:stream")
            
            # Listen for messages
            async def receive_messages():
                while True:
                    try:
                        message = await asyncio.wait_for(websocket.recv(), timeout=1.0)
                        data = json.loads(message)
                        print(f"📥 Received: {data['event']} - {data.get('payload', {})}")
                    except asyncio.TimeoutError:
                        pass
                    except Exception as e:
                        print(f"Error receiving: {e}")
                        break
            
            # Start receiving in background
            receive_task = asyncio.create_task(receive_messages())
            
            # Wait for join confirmation
            await asyncio.sleep(1)
            
            # Query similar patterns
            search_msg = {
                "topic": "patterns:stream",
                "event": "query_similar",
                "payload": {
                    "vector": [0.5] * 100,  # 100-dimensional vector
                    "k": 5
                },
                "ref": "2"
            }
            await websocket.send(json.dumps(search_msg))
            print("🔍 Sent pattern search request")
            
            # Get monitoring info
            monitor_msg = {
                "topic": "patterns:stream",
                "event": "get_monitoring",
                "payload": {},
                "ref": "3"
            }
            await websocket.send(json.dumps(monitor_msg))
            print("📊 Sent monitoring request")
            
            # Wait for responses
            await asyncio.sleep(3)
            
            # Cancel receive task
            receive_task.cancel()
            
            print("\n✅ Test completed!")
            
    except Exception as e:
        print(f"❌ Connection failed: {e}")

if __name__ == "__main__":
    asyncio.run(test_pattern_streaming())