#!/usr/bin/env elixir

# Test WebSocket pattern streaming end-to-end
Mix.install([
  {:websocket_client, "~> 1.5"},
  {:jason, "~> 1.4"}
])

defmodule PatternWebSocketTest do
  @moduledoc """
  End-to-end test for HNSW pattern streaming via WebSocket
  """
  
  require Logger
  
  @url "ws://localhost:4000/socket/websocket"
  @timeout 5000
  
  def run do
    IO.puts("\n🚀 Testing HNSW Pattern WebSocket Streaming...\n")
    
    # Start WebSocket client
    case :websocket_client.start_link(@url, __MODULE__, []) do
      {:ok, ws_pid} ->
        IO.puts("✅ Connected to WebSocket!")
        
        # Join pattern stream channel
        join_msg = %{
          "topic" => "patterns:stream",
          "event" => "phx_join",
          "payload" => %{},
          "ref" => "1"
        }
        
        :websocket_client.send(ws_pid, {:text, Jason.encode!(join_msg)})
        IO.puts("📤 Sent join request for patterns:stream")
        
        # Wait for join confirmation
        Process.sleep(1000)
        
        # Test pattern search
        search_msg = %{
          "topic" => "patterns:stream",
          "event" => "query_similar",
          "payload" => %{
            "vector" => List.duplicate(0.5, 100),
            "k" => 5
          },
          "ref" => "2"
        }
        
        :websocket_client.send(ws_pid, {:text, Jason.encode!(search_msg)})
        IO.puts("🔍 Sent pattern search request")
        
        # Test getting monitoring info
        monitor_msg = %{
          "topic" => "patterns:stream",
          "event" => "get_monitoring",
          "payload" => %{},
          "ref" => "3"
        }
        
        :websocket_client.send(ws_pid, {:text, Jason.encode!(monitor_msg)})
        IO.puts("📊 Sent monitoring request")
        
        # Generate test patterns via EventBus
        IO.puts("\n🎯 Generating test patterns...")
        generate_test_patterns()
        
        # Keep connection open to receive messages
        Process.sleep(5000)
        
        :websocket_client.stop(ws_pid)
        IO.puts("\n✅ Test completed!")
        
      {:error, reason} ->
        IO.puts("❌ Failed to connect: #{inspect(reason)}")
    end
  end
  
  def generate_test_patterns do
    alias AutonomousOpponentV2Core.EventBus
    
    # Generate various pattern types
    patterns = [
      %{
        pattern_id: "ws_test_#{:erlang.unique_integer()}",
        match_context: %{
          confidence: 0.95,
          type: "error_pattern",
          source: :websocket_test
        },
        matched_event: %{data: "Critical error detected"},
        triggered_at: DateTime.utc_now()
      },
      %{
        pattern_id: "ws_test_#{:erlang.unique_integer()}",
        match_context: %{
          confidence: 0.88,
          type: "performance_pattern",
          source: :websocket_test
        },
        matched_event: %{data: "Performance anomaly"},
        triggered_at: DateTime.utc_now()
      },
      %{
        pattern_id: "ws_test_#{:erlang.unique_integer()}",
        match_context: %{
          confidence: 0.76,
          type: "security_pattern",
          source: :websocket_test
        },
        matched_event: %{data: "Suspicious activity"},
        triggered_at: DateTime.utc_now()
      }
    ]
    
    Enum.each(patterns, fn pattern ->
      EventBus.publish(:pattern_matched, pattern)
      Process.sleep(500)
    end)
    
    # Publish pattern indexing summary
    EventBus.publish(:patterns_indexed, %{
      count: length(patterns),
      deduplicated: 0,
      source: :websocket_test
    })
    
    # Generate algedonic signal
    EventBus.publish(:algedonic_signal, %{
      type: :pain,
      intensity: 0.92,
      source: :system_overload,
      pattern_vector: List.duplicate(0.9, 100)
    })
    
    IO.puts("✅ Published #{length(patterns)} test patterns")
  end
  
  # WebSocket callbacks
  def init([]) do
    {:once, %{}}
  end
  
  def onconnect(_ws_req, state) do
    IO.puts("🔌 WebSocket connected!")
    :ok = :websocket_client.cast(self(), {:text, "ping"})
    {:ok, state}
  end
  
  def ondisconnect({:remote, :closed}, state) do
    IO.puts("🔌 WebSocket disconnected")
    {:ok, state}
  end
  
  def websocket_handle({:text, msg}, _conn_state, state) do
    case Jason.decode(msg) do
      {:ok, decoded} ->
        handle_message(decoded)
      {:error, _} ->
        IO.puts("Failed to decode: #{msg}")
    end
    {:ok, state}
  end
  
  def websocket_handle(_msg, _conn_state, state) do
    {:ok, state}
  end
  
  def websocket_info(_info, _conn_state, state) do
    {:ok, state}
  end
  
  def websocket_terminate(_reason, _conn_state, _state) do
    :ok
  end
  
  defp handle_message(%{"event" => event, "payload" => payload} = msg) do
    case event do
      "phx_reply" ->
        IO.puts("\n📥 Reply to ref #{msg["ref"]}: #{inspect(payload["status"])}")
        if payload["response"] do
          IO.inspect(payload["response"], label: "Response", pretty: true)
        end
        
      "pattern_indexed" ->
        IO.puts("\n📈 Pattern Indexed: #{payload["count"]} patterns (#{payload["deduplicated"]} deduped) from #{payload["source"]}")
        
      "pattern_matched" ->
        IO.puts("\n🎯 Pattern Match: #{payload["pattern_id"]} (#{payload["type"]}) - confidence: #{payload["confidence"]}")
        
      "algedonic_pattern" ->
        IO.puts("\n🚨 ALGEDONIC PATTERN: #{payload["type"]} - intensity: #{payload["intensity"]} - severity: #{payload["severity"]}")
        
      "initial_stats" ->
        IO.puts("\n📊 Initial Stats Received:")
        IO.inspect(payload["stats"], pretty: true)
        
      "stats_update" ->
        IO.puts("\n📊 Stats Update: #{inspect(payload["stats"])}")
        
      _ ->
        IO.puts("\n❓ Unknown event: #{event}")
        IO.inspect(payload, pretty: true)
    end
  end
  
  defp handle_message(msg) do
    IO.puts("\n📨 Received: #{inspect(msg)}")
  end
end

# Run the test
PatternWebSocketTest.run()