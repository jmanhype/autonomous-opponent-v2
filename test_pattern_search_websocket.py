#!/usr/bin/env python

import asyncio
import json
import websockets
import random
import time
from datetime import datetime

class PatternSearchWebSocketClient:
    def __init__(self):
        self.uri = "ws://localhost:4000/socket/websocket"
        self.ref = 0
        
    def next_ref(self):
        self.ref += 1
        return str(self.ref)
        
    async def test_full_pattern_flow(self):
        async with websockets.connect(self.uri) as websocket:
            print("✅ Connected to WebSocket")
            
            # 1. Join patterns:stream channel
            join_msg = {
                "topic": "patterns:stream",
                "event": "phx_join",
                "payload": {},
                "ref": self.next_ref()
            }
            
            await websocket.send(json.dumps(join_msg))
            print("📤 Sent join request")
            
            # Wait for join confirmation
            join_ref = join_msg["ref"]
            joined = False
            
            while not joined:
                message = await websocket.recv()
                data = json.loads(message)
                print(f"📥 Received: {data['event']}")
                
                if data.get("ref") == join_ref and data.get("payload", {}).get("status") == "ok":
                    joined = True
                    print("✅ Successfully joined channel!")
                    break
            
            # 2. Get monitoring info
            print("\n🔍 Getting monitoring info...")
            monitoring_msg = {
                "topic": "patterns:stream",
                "event": "get_monitoring",
                "payload": {},
                "ref": self.next_ref()
            }
            await websocket.send(json.dumps(monitoring_msg))
            
            # 3. Query similar patterns
            print("\n🔎 Querying similar patterns...")
            vector = [random.random() for _ in range(100)]
            
            query_msg = {
                "topic": "patterns:stream",
                "event": "query_similar",
                "payload": {
                    "vector": vector,
                    "k": 5
                },
                "ref": self.next_ref()
            }
            
            await websocket.send(json.dumps(query_msg))
            print("📤 Sent pattern search request")
            
            # 4. Listen for responses and pattern events
            print("\n👂 Listening for pattern events...")
            start_time = time.time()
            timeout = 15  # Listen for 15 seconds
            
            while time.time() - start_time < timeout:
                try:
                    message = await asyncio.wait_for(websocket.recv(), timeout=1.0)
                    data = json.loads(message)
                    
                    # Handle different event types
                    if data["event"] == "phx_reply":
                        if data["payload"]["status"] == "ok":
                            print(f"✅ Reply to ref {data['ref']}: Success")
                            if "response" in data["payload"] and "results" in data["payload"]["response"]:
                                results = data["payload"]["response"]["results"]
                                print(f"   Found {len(results)} similar patterns:")
                                for result in results[:3]:  # Show top 3
                                    print(f"   - Pattern {result['pattern_id']}: score {result['score']:.3f}")
                        else:
                            print(f"❌ Reply to ref {data['ref']}: {data['payload'].get('response', 'Error')}")
                    
                    elif data["event"] == "pattern_indexed":
                        print(f"📊 Pattern indexed: {data['payload']['count']} patterns, {data['payload']['deduplicated']} deduplicated")
                    
                    elif data["event"] == "pattern_matched":
                        print(f"🎯 Pattern matched: {data['payload']['pattern_id']} (confidence: {data['payload']['confidence']:.2f})")
                    
                    elif data["event"] == "initial_stats":
                        stats = data["payload"].get("stats", {})
                        if "error" not in stats:
                            print(f"📈 Initial stats: {json.dumps(stats, indent=2)}")
                    
                    elif data["event"] == "stats_update":
                        stats = data["payload"].get("stats", {})
                        print(f"📊 Stats update: Indexed={stats.get('indexed', 0)}, Deduped={stats.get('deduplicated', 0)}")
                    
                    elif data["event"] == "algedonic_pattern":
                        print(f"🚨 Algedonic pattern detected! Type: {data['payload']['type']}, Intensity: {data['payload']['intensity']}")
                        
                except asyncio.TimeoutError:
                    # No message within timeout, continue
                    pass
                except Exception as e:
                    print(f"❌ Error: {e}")
                    break
            
            print("\n👋 Closing connection")

async def main():
    print("🚀 Testing Pattern Search via WebSocket\n")
    
    client = PatternSearchWebSocketClient()
    await client.test_full_pattern_flow()
    
    print("\n✨ Test complete!")

if __name__ == "__main__":
    asyncio.run(main())