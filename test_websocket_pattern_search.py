#!/usr/bin/env python

import asyncio
import json
import websockets
from datetime import datetime

class PatternWebSocketClient:
    def __init__(self):
        self.uri = "ws://localhost:4000/socket/websocket"
        self.ref = 0
        
    def next_ref(self):
        self.ref += 1
        return str(self.ref)
        
    async def test_pattern_channel(self):
        async with websockets.connect(self.uri) as websocket:
            print("✅ Connected to WebSocket")
            
            # Join patterns:stream channel
            join_msg = {
                "topic": "patterns:stream",
                "event": "phx_join",
                "payload": {},
                "ref": self.next_ref()
            }
            
            await websocket.send(json.dumps(join_msg))
            print("📤 Sent join request")
            
            # Listen for messages
            async def receive_messages():
                while True:
                    try:
                        message = await asyncio.wait_for(websocket.recv(), timeout=5.0)
                        data = json.loads(message)
                        print(f"📥 Received: {json.dumps(data, indent=2)}")
                        
                        # If we joined successfully, try pattern search
                        if data.get("event") == "phx_reply" and data.get("payload", {}).get("status") == "ok":
                            if data.get("ref") == "1":  # Join successful
                                print("\n🔍 Testing pattern search...")
                                
                                # Generate test vector (100 dimensions)
                                import random
                                vector = [random.random() for _ in range(100)]
                                
                                search_msg = {
                                    "topic": "patterns:stream",
                                    "event": "query_similar",
                                    "payload": {
                                        "vector": vector,
                                        "k": 5
                                    },
                                    "ref": self.next_ref()
                                }
                                
                                await websocket.send(json.dumps(search_msg))
                                print("📤 Sent pattern search request")
                                
                    except asyncio.TimeoutError:
                        print("⏱️  Timeout waiting for message")
                        break
                    except Exception as e:
                        print(f"❌ Error: {e}")
                        break
            
            await receive_messages()
            
            print("\n👋 Closing connection")

async def main():
    print("🚀 Testing Pattern WebSocket Functionality\n")
    
    client = PatternWebSocketClient()
    await client.test_pattern_channel()
    
    print("\n✨ Test complete!")

if __name__ == "__main__":
    asyncio.run(main())