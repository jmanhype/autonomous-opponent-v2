defmodule AutonomousOpponentV2Web.WebGatewayDashboardLiveTest do
  use AutonomousOpponentV2Web.ConnCase

  import Phoenix.LiveViewTest

  describe "Web Gateway Dashboard" do
    test "renders dashboard", %{conn: conn} do
      {:ok, view, html} = live(conn, "/web-gateway/dashboard")
      
      assert html =~ "Web Gateway Dashboard"
      assert html =~ "Active Connections"
      assert html =~ "Message Throughput"
      assert html =~ "Circuit Breakers"
      assert html =~ "Connection Pool"
      assert html =~ "VSM Integration"
      assert html =~ "Error Rates"
    end
    
    test "updates metrics in real-time", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/web-gateway/dashboard")
      
      # Simulate metrics update via PubSub
      metrics = %{
        connections: %{websocket: 10, http_sse: 5, total: 15},
        throughput: 100,
        circuit_breakers: %{websocket: :open, http_sse: :closed},
        vsm_metrics: %{
          s1_variety_absorption: 50,
          s2_coordination_active: true,
          s3_resource_usage: 75,
          s4_intelligence_events: 10,
          s5_policy_violations: 2,
          algedonic_signals: []
        },
        error_rates: %{websocket: 0.5, http_sse: 1.2},
        pool_status: %{available: 80, in_use: 20, overflow: 0}
      }
      
      send(view.pid, {:mcp_metrics_update, metrics})
      
      # Check that values are updated
      assert render(view) =~ "10"  # WebSocket connections
      assert render(view) =~ "5"   # SSE connections
      assert render(view) =~ "100" # Throughput
      assert render(view) =~ "OPEN"
      assert render(view) =~ "CLOSED"
    end
    
    test "displays algedonic signals when present", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/web-gateway/dashboard")
      
      metrics = %{
        connections: %{websocket: 0, http_sse: 0, total: 0},
        throughput: 0,
        circuit_breakers: %{websocket: :closed, http_sse: :closed},
        vsm_metrics: %{
          s1_variety_absorption: 0,
          s2_coordination_active: false,
          s3_resource_usage: 0,
          s4_intelligence_events: 0,
          s5_policy_violations: 0,
          algedonic_signals: [
            %{
              severity: :critical,
              message: "All transports down",
              timestamp: DateTime.utc_now()
            }
          ]
        },
        error_rates: %{websocket: 0, http_sse: 0},
        pool_status: %{available: 100, in_use: 0, overflow: 0}
      }
      
      send(view.pid, {:mcp_metrics_update, metrics})
      
      assert render(view) =~ "Algedonic Signals"
      assert render(view) =~ "All transports down"
      assert render(view) =~ "critical"
    end
  end
end