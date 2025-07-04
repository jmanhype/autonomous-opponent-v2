defmodule AutonomousOpponentV2Core.AMCP.RealAMQPTest do
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.AMCP.Message
  
  @moduletag :integration
  @moduletag :amqp
  
  setup do
    # Only run these tests if AMQP is available
    if System.get_env("AMQP_ENABLED", "true") == "true" and 
       Code.ensure_loaded?(AMQP) do
      :ok
    else
      :skip
    end
  end
  
  describe "real AMQP connection" do
    test "can connect to RabbitMQ" do
      # Use connection options from config
      conn_opts = Application.get_env(:autonomous_opponent_core, :amqp_connection, [])
      
      case AMQP.Connection.open(conn_opts) do
        {:ok, connection} ->
          assert {:ok, channel} = AMQP.Channel.open(connection)
          
          # Cleanup
          AMQP.Channel.close(channel)
          AMQP.Connection.close(connection)
          
        {:error, {:auth_failure, _}} ->
          IO.puts("Auth failure - check RabbitMQ credentials")
          IO.puts("Expected: #{inspect(conn_opts)}")
          flunk("Cannot connect to RabbitMQ - check credentials")
          
        {:error, :econnrefused} ->
          IO.puts("Connection refused - is RabbitMQ running?")
          flunk("Cannot connect to RabbitMQ - service not available")
          
        {:error, reason} ->
          IO.puts("Connection error: #{inspect(reason)}")
          flunk("Cannot connect to RabbitMQ")
      end
    end
    
    test "can publish and consume messages with content-based IDs" do
      conn_opts = Application.get_env(:autonomous_opponent_core, :amqp_connection, [])
      
      case AMQP.Connection.open(conn_opts) do
        {:ok, connection} ->
          {:ok, channel} = AMQP.Channel.open(connection)
      
      # Setup test exchange and queue
      exchange = "test.exchange"
      queue = "test.queue.#{System.unique_integer([:positive])}"
      
      :ok = AMQP.Exchange.declare(channel, exchange, :topic)
      {:ok, _} = AMQP.Queue.declare(channel, queue, auto_delete: true)
      :ok = AMQP.Queue.bind(channel, queue, exchange, routing_key: "#")
      
      # Create test message with content-based ID
      message = Message.new(%{
        type: "test",
        sender: "test_sender",
        recipient: "test_recipient",
        payload: %{data: "Hello AMQP!", test: true},
        context: %{test_id: System.unique_integer([:positive])}
      })
      
      # Publish message
      payload = Jason.encode!(message)
      :ok = AMQP.Basic.publish(channel, exchange, "test.routing", payload)
      
      # Consume message
      {:ok, payload_received, _meta} = AMQP.Basic.get(channel, queue)
      message_received = Jason.decode!(payload_received)
      
      # Verify message integrity
      assert message_received["id"] == message.id
      assert message_received["type"] == "test"
      assert message_received["payload"]["data"] == "Hello AMQP!"
      
      # Verify content-based ID is deterministic
      message2 = Message.new(%{
        type: "test",
        sender: "test_sender",
        recipient: "test_recipient",
        payload: %{data: "Hello AMQP!", test: true},
        context: %{test_id: message.context.test_id},
        timestamp: message.timestamp
      })
      
      assert message2.id == message.id
      
      # Cleanup
      AMQP.Queue.delete(channel, queue)
      AMQP.Channel.close(channel)
      AMQP.Connection.close(connection)
      
        {:error, reason} ->
          IO.puts("Cannot test AMQP messages - connection failed: #{inspect(reason)}")
          flunk("AMQP connection required for this test")
      end
    end
  end
end