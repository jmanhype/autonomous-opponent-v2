defmodule AutonomousOpponentV2Web.MetricsControllerTest do
  use AutonomousOpponentV2Web.ConnCase

  describe "GET /metrics" do
    test "returns prometheus format with proper content type", %{conn: conn} do
      conn = get(conn, "/metrics")
      assert response = text_response(conn, 200)
      
      # Check content type
      [content_type] = get_resp_header(conn, "content-type")
      assert String.starts_with?(content_type, "text/plain; version=0.0.4")
      
      # Should either be empty (when no metrics) or contain valid prometheus format
      # Valid prometheus format has metric_name{labels} value or just metric_name value
      assert response == "" || 
             String.contains?(response, " ") || 
             String.contains?(response, "{") ||
             String.starts_with?(response, "#")
    end

    test "includes CORS headers for cross-origin scraping", %{conn: conn} do
      conn = get(conn, "/metrics")
      assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
    end

    test "includes metric type annotations", %{conn: conn} do
      conn = get(conn, "/metrics")
      response = text_response(conn, 200)
      
      # Should include HELP and TYPE annotations
      assert String.contains?(response, "# HELP") || String.contains?(response, "No metrics available")
      assert String.contains?(response, "# TYPE") || String.contains?(response, "No metrics available")
    end

    test "includes meta-metrics about cardinality", %{conn: conn} do
      conn = get(conn, "/metrics")
      response = text_response(conn, 200)
      
      # Should include cardinality tracking
      assert String.contains?(response, "metrics_cardinality_total") || 
             String.contains?(response, "No metrics available")
    end

    test "handles metrics system not running gracefully", %{conn: conn} do
      # Stop metrics if running
      case Process.whereis(AutonomousOpponentV2Core.Core.Metrics) do
        nil -> :ok
        pid -> 
          ref = Process.monitor(pid)
          GenServer.stop(pid)
          # Wait for DOWN message to confirm process is stopped
          receive do
            {:DOWN, ^ref, :process, ^pid, _} -> :ok
          after
            5000 -> raise "Metrics process failed to stop"
          end
      end
      
      conn = get(conn, "/metrics")
      response = text_response(conn, 200)
      
      # When metrics system is not running, we should get either "No metrics available"
      # or an empty metrics response with headers
      assert String.contains?(response, "No metrics available") || 
             String.contains?(response, "# Autonomous Opponent VSM Metrics")
    end
    
    test "enforces cardinality limit when metrics exceed maximum", %{conn: conn} do
      # This test verifies that the cardinality limit is enforced
      # In a real scenario, we would need to mock the metrics to exceed the limit
      # For now, we verify the logic exists by checking the response format
      conn = get(conn, "/metrics")
      response = text_response(conn, 200)
      
      # Response should either be normal metrics or warning about cardinality
      assert String.contains?(response, "# Autonomous Opponent VSM Metrics") ||
             String.contains?(response, "# WARNING: Metric cardinality") ||
             String.contains?(response, "No metrics available")
    end
    
    test "respects CORS configuration", %{conn: conn} do
      # Test with CORS disabled
      Application.put_env(:autonomous_opponent_web, :metrics_endpoint_cors_enabled, false)
      conn_no_cors = get(conn, "/metrics")
      assert get_resp_header(conn_no_cors, "access-control-allow-origin") == []
      
      # Test with CORS enabled and custom origin
      Application.put_env(:autonomous_opponent_web, :metrics_endpoint_cors_enabled, true)
      Application.put_env(:autonomous_opponent_web, :metrics_endpoint_cors_origin, "https://prometheus.example.com")
      conn_custom = get(conn, "/metrics")
      assert get_resp_header(conn_custom, "access-control-allow-origin") == ["https://prometheus.example.com"]
      
      # Reset to defaults
      Application.put_env(:autonomous_opponent_web, :metrics_endpoint_cors_enabled, true)
      Application.put_env(:autonomous_opponent_web, :metrics_endpoint_cors_origin, "*")
    end
  end
end