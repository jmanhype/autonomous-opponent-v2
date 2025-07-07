#!/usr/bin/env elixir

# Start the core application without Phoenix
{:ok, _} = Application.ensure_all_started(:autonomous_opponent_core)
Process.sleep(2000)

# Simple web server using Plug
defmodule VSMTestServer do
  use Plug.Router
  require Logger
  
  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  
  plug :match
  plug :dispatch
  
  # Health check
  get "/health" do
    response = %{
      status: "ok",
      vsm: "operational",
      timestamp: DateTime.utc_now()
    }
    send_json(conn, 200, response)
  end
  
  # VSM Status
  get "/api/vsm/status" do
    subsystems = [
      {AutonomousOpponentV2Core.VSM.S1.Operations, "S1"},
      {AutonomousOpponentV2Core.VSM.S2.Coordination, "S2"},
      {AutonomousOpponentV2Core.VSM.S3.Control, "S3"},
      {AutonomousOpponentV2Core.VSM.S4.Intelligence, "S4"},
      {AutonomousOpponentV2Core.VSM.S5.Policy, "S5"},
      {AutonomousOpponentV2Core.VSM.Algedonic.Channel, "Algedonic"}
    ]
    
    status = Enum.map(subsystems, fn {module, name} ->
      alive = case Process.whereis(module) do
        nil -> false
        pid -> Process.alive?(pid)
      end
      {name, alive}
    end)
    |> Map.new()
    
    send_json(conn, 200, %{vsm_subsystems: status})
  end
  
  # S1 Variety Metrics
  get "/api/vsm/variety" do
    variety = AutonomousOpponentV2Core.VSM.S1.Operations.get_variety_metrics()
    send_json(conn, 200, variety)
  end
  
  # Algedonic State
  get "/api/vsm/algedonic" do
    state = AutonomousOpponentV2Core.VSM.Algedonic.Channel.get_hedonic_state()
    metrics = AutonomousOpponentV2Core.VSM.Algedonic.Channel.get_metrics()
    
    response = %{
      mood: state.mood,
      pain_level: state.pain_level,
      pleasure_level: state.pleasure_level,
      in_pain: AutonomousOpponentV2Core.VSM.Algedonic.Channel.in_pain?(),
      metrics: %{
        error_count: metrics.error_count,
        memory_usage: metrics.memory_usage,
        response_times: length(metrics.response_times)
      }
    }
    
    send_json(conn, 200, response)
  end
  
  # S3 Control Performance
  get "/api/vsm/performance" do
    perf = AutonomousOpponentV2Core.VSM.S3.Control.get_performance_metrics(
      AutonomousOpponentV2Core.VSM.S3.Control
    )
    send_json(conn, 200, perf)
  end
  
  # Generate Event
  post "/api/vsm/event" do
    event_type = String.to_atom(conn.body_params["type"] || "test_event")
    event_data = conn.body_params["data"] || %{}
    
    AutonomousOpponentV2Core.EventBus.publish(event_type, event_data)
    
    send_json(conn, 200, %{status: "event_published", type: event_type})
  end
  
  # Metrics Data
  get "/api/metrics/:metric" do
    time_window = String.to_integer(conn.params["time_window"] || "60000")
    
    data = AutonomousOpponentV2Core.Core.Metrics.get_metrics(
      AutonomousOpponentV2Core.Core.Metrics,
      metric,
      time_window
    )
    
    send_json(conn, 200, %{metric: metric, data: data})
  end
  
  # Record Metric
  post "/api/metrics/:metric" do
    value = conn.body_params["value"] || 0
    
    AutonomousOpponentV2Core.Core.Metrics.record(
      AutonomousOpponentV2Core.Core.Metrics,
      metric,
      value
    )
    
    send_json(conn, 200, %{status: "recorded", metric: metric, value: value})
  end
  
  match _ do
    send_json(conn, 404, %{error: "Not found"})
  end
  
  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end

# Start the server
port = 4001
{:ok, _} = Plug.Cowboy.http(VSMTestServer, [], port: port)

IO.puts """
╔══════════════════════════════════════════════════════════════╗
║                VSM TEST SERVER RUNNING                       ║
╚══════════════════════════════════════════════════════════════╝

Server running on http://localhost:#{port}

Test endpoints:
  curl http://localhost:#{port}/health
  curl http://localhost:#{port}/api/vsm/status
  curl http://localhost:#{port}/api/vsm/variety
  curl http://localhost:#{port}/api/vsm/algedonic
  curl http://localhost:#{port}/api/vsm/performance
  
  # Record metrics
  curl -X POST http://localhost:#{port}/api/metrics/throughput \\
    -H "Content-Type: application/json" \\
    -d '{"value": 1500}'
    
  # Get metrics
  curl http://localhost:#{port}/api/metrics/throughput?time_window=60000
  
  # Generate events
  curl -X POST http://localhost:#{port}/api/vsm/event \\
    -H "Content-Type: application/json" \\
    -d '{"type": "system_performance", "data": {"cpu": 75, "memory": 80}}'

Press Ctrl+C to stop...
"""

# Generate some test data every 5 seconds
spawn(fn ->
  :timer.sleep(5000)
  
  Enum.each(1..100, fn i ->
    # Record various metrics
    AutonomousOpponentV2Core.Core.Metrics.record(
      AutonomousOpponentV2Core.Core.Metrics,
      "throughput",
      1000 + :rand.uniform(1000)
    )
    
    AutonomousOpponentV2Core.Core.Metrics.record(
      AutonomousOpponentV2Core.Core.Metrics,
      "latency",
      50 + :rand.uniform(150)
    )
    
    if rem(i, 10) == 0 do
      AutonomousOpponentV2Core.Core.Metrics.record(
        AutonomousOpponentV2Core.Core.Metrics,
        "errors",
        :rand.uniform(5)
      )
    end
    
    # Generate events
    AutonomousOpponentV2Core.EventBus.publish(:system_performance, %{
      cpu: 40 + :rand.uniform(50),
      memory: 50 + :rand.uniform(40),
      latency: 50 + :rand.uniform(150)
    })
    
    :timer.sleep(1000)
  end)
end)

Process.sleep(:infinity)