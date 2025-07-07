# Simple web server to test VSM via HTTP without full Phoenix

defmodule SimpleVSMWeb do
  use Plug.Router
  
  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  
  plug :match
  plug :dispatch
  
  get "/health" do
    send_resp(conn, 200, Jason.encode!(%{status: "ok", vsm: "operational"}))
  end
  
  get "/api/vsm/status" do
    # Check all VSM subsystems
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
    
    send_resp(conn, 200, Jason.encode!(%{vsm_subsystems: status}))
  end
  
  get "/api/vsm/variety" do
    variety = AutonomousOpponentV2Core.VSM.S1.Operations.get_variety_metrics()
    send_resp(conn, 200, Jason.encode!(variety))
  end
  
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
        response_times_count: length(metrics.response_times)
      }
    }
    
    send_resp(conn, 200, Jason.encode!(response))
  end
  
  post "/api/vsm/event" do
    event_type = String.to_atom(conn.body_params["type"] || "test_event")
    event_data = conn.body_params["data"] || %{}
    
    AutonomousOpponentV2Core.EventBus.publish(event_type, event_data)
    
    send_resp(conn, 200, Jason.encode!(%{status: "event_published", type: event_type}))
  end
  
  match _ do
    send_resp(conn, 404, "Not found")
  end
end

# Start the application
{:ok, _} = Application.ensure_all_started(:autonomous_opponent_core)

# Start simple web server
IO.puts "Starting simple VSM web server on port 4001..."
{:ok, _} = Plug.Cowboy.http(SimpleVSMWeb, [], port: 4001)

IO.puts """
\n=== Simple VSM Web Server Running ===

Test with:
  curl http://localhost:4001/health
  curl http://localhost:4001/api/vsm/status
  curl http://localhost:4001/api/vsm/variety
  curl http://localhost:4001/api/vsm/algedonic
  
  curl -X POST http://localhost:4001/api/vsm/event \\
    -H "Content-Type: application/json" \\
    -d '{"type": "test_event", "data": {"message": "Hello VSM"}}'

Press Ctrl+C to stop...
"""

# Keep the script running
Process.sleep(:infinity)