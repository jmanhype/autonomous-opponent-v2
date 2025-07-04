defmodule AutonomousOpponentV2Core.AMCP.MessageTest do
  use ExUnit.Case, async: true
  alias AutonomousOpponentV2Core.AMCP.Message

  describe "new/1" do
    test "creates message with content-based hash ID" do
      attrs = %{
        type: "test",
        sender: "test_sender",
        recipient: "test_recipient",
        payload: %{data: "test"},
        context: %{request_id: "123"}
      }
      
      message = Message.new(attrs)
      
      assert message.id != nil
      assert String.match?(message.id, ~r/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/)
      assert message.type == "test"
      assert message.sender == "test_sender"
      assert message.timestamp != nil
    end
    
    test "generates same ID for same content" do
      attrs = %{
        type: "test",
        sender: "sender",
        recipient: "recipient",
        payload: %{value: 42},
        context: %{},
        timestamp: ~U[2025-01-01 00:00:00Z]
      }
      
      message1 = Message.new(attrs)
      message2 = Message.new(attrs)
      
      assert message1.id == message2.id
    end
    
    test "generates different IDs for different content" do
      attrs1 = %{
        type: "test",
        sender: "sender1",
        recipient: "recipient",
        payload: %{value: 42},
        context: %{}
      }
      
      attrs2 = %{
        type: "test", 
        sender: "sender2", # Different sender
        recipient: "recipient",
        payload: %{value: 42},
        context: %{}
      }
      
      message1 = Message.new(attrs1)
      message2 = Message.new(attrs2)
      
      assert message1.id != message2.id
    end
    
    test "ignores ID and signature when generating hash" do
      base_attrs = %{
        type: "test",
        sender: "sender",
        recipient: "recipient",
        payload: %{data: "test"},
        context: %{},
        timestamp: ~U[2025-01-01 00:00:00Z]
      }
      
      attrs_with_id = Map.put(base_attrs, :id, "should-be-ignored")
      attrs_with_sig = Map.put(base_attrs, :signature, "should-be-ignored")
      
      message1 = Message.new(base_attrs)
      message2 = Message.new(attrs_with_id)
      message3 = Message.new(attrs_with_sig)
      
      assert message1.id == message2.id
      assert message1.id == message3.id
    end
  end
  
  describe "generate_content_hash/1" do
    test "generates deterministic hash" do
      attrs = %{
        type: "test",
        sender: "sender",
        payload: %{key: "value"},
        context: %{},
        timestamp: ~U[2025-01-01 00:00:00Z]
      }
      
      hash1 = Message.generate_content_hash(attrs)
      hash2 = Message.generate_content_hash(attrs)
      
      assert hash1 == hash2
    end
    
    test "handles complex nested structures" do
      attrs = %{
        type: "complex",
        sender: "sender",
        payload: %{
          nested: %{
            list: [1, 2, 3],
            map: %{a: 1, b: 2}
          }
        },
        context: %{
          metadata: %{
            tags: ["tag1", "tag2"]
          }
        },
        timestamp: ~U[2025-01-01 00:00:00Z]
      }
      
      hash = Message.generate_content_hash(attrs)
      assert String.match?(hash, ~r/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/)
    end
  end
end