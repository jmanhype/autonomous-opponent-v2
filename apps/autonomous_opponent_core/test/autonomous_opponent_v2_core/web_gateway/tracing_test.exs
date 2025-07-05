defmodule AutonomousOpponentV2Core.WebGateway.TracingTest do
  use ExUnit.Case, async: true
  
  alias AutonomousOpponentV2Core.WebGateway.Tracing
  
  describe "trace_routing/4" do
    test "traces successful routing" do
      result = Tracing.trace_routing("client123", %{type: "message"}, :websocket, fn ->
        {:ok, :routed}
      end)
      
      assert result == {:ok, :routed}
    end
    
    test "traces routing errors" do
      result = Tracing.trace_routing("client123", %{type: "message"}, :websocket, fn ->
        {:error, :no_transport}
      end)
      
      assert result == {:error, :no_transport}
    end
  end
  
  describe "trace_websocket_message/3" do
    test "traces WebSocket message handling" do
      result = Tracing.trace_websocket_message("client123", %{type: "ping"}, fn ->
        {:ok, :pong}
      end)
      
      assert result == {:ok, :pong}
    end
  end
  
  describe "trace_sse_event/4" do
    test "traces SSE event sending" do
      result = Tracing.trace_sse_event("client123", "message", %{data: "test"}, fn ->
        :ok
      end)
      
      assert result == :ok
    end
  end
  
  describe "trace_pool_operation/3" do
    test "traces pool checkout" do
      result = Tracing.trace_pool_operation(:checkout, "conn123", fn ->
        {:ok, :connection}
      end)
      
      assert result == {:ok, :connection}
    end
    
    test "measures operation duration" do
      result = Tracing.trace_pool_operation(:checkin, "conn123", fn ->
        Process.sleep(10)
        :ok
      end)
      
      assert result == :ok
    end
  end
  
  describe "trace_vsm_interaction/4" do
    test "traces VSM subsystem interaction" do
      result = Tracing.trace_vsm_interaction(:s1_operations, :process, %{type: "variety"}, fn data ->
        assert Map.has_key?(data, :trace_context)
        {:ok, %{processed: true}}
      end)
      
      assert result == {:ok, %{processed: true}}
    end
    
    test "handles VSM errors" do
      result = Tracing.trace_vsm_interaction(:s2_coordination, :check, %{}, fn _data ->
        {:error, :conflict}
      end)
      
      assert result == {:error, :conflict}
    end
  end
  
  describe "trace_circuit_breaker/3" do
    test "traces circuit breaker calls" do
      result = Tracing.trace_circuit_breaker(:websocket_transport, :call, fn ->
        {:ok, :allowed}
      end)
      
      assert result == {:ok, :allowed}
    end
    
    test "traces circuit breaker rejections" do
      result = Tracing.trace_circuit_breaker(:websocket_transport, :call, fn ->
        {:error, :circuit_open}
      end)
      
      assert result == {:error, :circuit_open}
    end
  end
  
  describe "extract_trace_context/1" do
    test "extracts W3C trace context from headers" do
      headers = %{
        "traceparent" => "00-0af7651916cd43dd8448eb211c80319c-b9c7c989f97918e1-01",
        "tracestate" => "congo=ucfJifl5GOE,rojo=00f067aa0ba902b7"
      }
      
      context = Tracing.extract_trace_context(headers)
      
      # Context extraction depends on OpenTelemetry implementation
      assert context != nil
    end
    
    test "returns undefined for missing trace context" do
      headers = %{}
      
      context = Tracing.extract_trace_context(headers)
      
      assert context == :undefined
    end
  end
  
  describe "inject_trace_context/1" do
    test "injects trace context into headers" do
      headers = %{"content-type" => "application/json"}
      
      enriched = Tracing.inject_trace_context(headers)
      
      # Should still have original headers
      assert enriched["content-type"] == "application/json"
      # May or may not have trace headers depending on current context
      assert is_map(enriched)
    end
  end
  
  describe "add_attributes/1" do
    test "adds attributes to current span" do
      attributes = %{
        client_id: "client123",
        transport: "websocket",
        message_size: 1024
      }
      
      # This doesn't return anything, just verify it doesn't crash
      assert Tracing.add_attributes(attributes) == :ok
    end
  end
  
  describe "add_event/2" do
    test "records event in current span" do
      assert Tracing.add_event("connection.established", %{
        transport: "websocket",
        client_id: "client123"
      }) == :ok
    end
  end
  
  describe "setup_telemetry_handlers/0" do
    test "sets up telemetry event handlers" do
      # Should not crash
      assert Tracing.setup_telemetry_handlers() == :ok
    end
  end
end