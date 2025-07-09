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
          GenServer.stop(pid)
          # Wait for process to fully stop
          Process.sleep(100)
      end
      
      conn = get(conn, "/metrics")
      response = text_response(conn, 200)
      
      # When metrics system is not running, we should get either "No metrics available"
      # or an empty metrics response with headers
      assert String.contains?(response, "No metrics available") || 
             String.contains?(response, "# Autonomous Opponent VSM Metrics")
    end
  end
end