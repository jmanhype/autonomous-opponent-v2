defmodule AutonomousOpponentV2Web.MetricsController do
  @moduledoc """
  Controller for exposing metrics in Prometheus format.
  This endpoint can be scraped by Prometheus/Grafana for monitoring.
  
  Enhanced with VSM Multi-Mind recommendations:
  - Metric type annotations for Prometheus compliance
  - CORS headers for cross-origin scraping
  - Cardinality tracking to prevent explosion
  - Meta-metrics about the metrics system itself
  """
  use AutonomousOpponentV2Web, :controller

  # Maximum allowed metric cardinality to prevent memory explosion
  @max_metric_cardinality 10_000

  def index(conn, params) do
    # Check if cluster aggregation is requested
    prometheus_text = if params["cluster"] == "true" do
      get_cluster_metrics()
    else
      get_local_metrics()
    end

    # Apply CORS headers based on configuration
    conn = if Application.get_env(:autonomous_opponent_web, :metrics_endpoint_cors_enabled, true) do
      cors_origin = Application.get_env(:autonomous_opponent_web, :metrics_endpoint_cors_origin, "*")
      put_resp_header(conn, "access-control-allow-origin", cors_origin)
    else
      conn
    end

    conn
    |> put_resp_content_type("text/plain; version=0.0.4")
    |> send_resp(200, prometheus_text)
  end
  
  @doc """
  Returns cluster-wide aggregated metrics in JSON format.
  Supports query parameters:
    - metric: specific metric name to query
    - aggregation: sum, avg, min, max, p50, p95, p99
    - from/to: time range
    - nodes: specific nodes to query
  """
  def cluster(conn, params) do
    require Logger
    
    result = case params do
      %{"metric" => metric_name} ->
        # Query specific metric
        aggregation = String.to_atom(params["aggregation"] || "raw")
        opts = build_query_opts(params)
        
        AutonomousOpponentV2Core.Core.Metrics.query_cluster(metric_name, Keyword.put(opts, :aggregation, aggregation))
        
      _ ->
        # Get all cluster metrics
        case Process.whereis(AutonomousOpponentV2Core.Metrics.Cluster.Aggregator) do
          nil ->
            {:error, :cluster_not_available}
          _pid ->
            AutonomousOpponentV2Core.Metrics.Cluster.Aggregator.aggregate_cluster_metrics()
        end
    end
    
    case result do
      {:ok, metrics} ->
        json(conn, %{
          status: "success",
          data: format_cluster_metrics(metrics),
          timestamp: System.os_time(:millisecond),
          node_count: length(Node.list()) + 1
        })
        
      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          status: "error",
          error: to_string(reason),
          message: "Cluster metrics aggregation failed"
        })
    end
  end
  
  @doc """
  Returns VSM health status across the cluster
  """
  def vsm_health(conn, _params) do
    case Process.whereis(AutonomousOpponentV2Core.Metrics.Cluster.Aggregator) do
      nil ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "error", message: "Cluster metrics not available"})
        
      _pid ->
        case AutonomousOpponentV2Core.Metrics.Cluster.Aggregator.vsm_health() do
          {:ok, health} ->
            json(conn, %{
              status: "success",
              health: health,
              timestamp: System.os_time(:millisecond)
            })
            
          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{
              status: "error",
              error: to_string(reason)
            })
        end
    end
  end
  
  # Private functions
  
  defp get_local_metrics do
    case Process.whereis(AutonomousOpponentV2Core.Core.Metrics) do
      nil ->
        # Return empty metrics if metrics system not running
        "# No metrics available - metrics system not running\n"
      _pid ->
        try do
          # Get raw metrics
          metrics_text = AutonomousOpponentV2Core.Core.Metrics.prometheus_format(AutonomousOpponentV2Core.Core.Metrics)
          
          # Add metric type annotations and meta-metrics
          enhance_prometheus_output(metrics_text)
        rescue
          error ->
            # Log the actual error for debugging
            require Logger
            Logger.error("Failed to retrieve metrics: #{inspect(error)}")
            "# Error retrieving metrics\n"
        end
    end
  end
  
  defp get_cluster_metrics do
    case Process.whereis(AutonomousOpponentV2Core.Metrics.Cluster.Aggregator) do
      nil ->
        "# No cluster metrics available - aggregator not running\n"
      _pid ->
        try do
          # Get aggregated cluster metrics
          {:ok, metrics} = AutonomousOpponentV2Core.Metrics.Cluster.Aggregator.aggregate_cluster_metrics()
          
          # Convert to Prometheus format
          convert_cluster_to_prometheus(metrics)
        rescue
          error ->
            require Logger
            Logger.error("Failed to retrieve cluster metrics: #{inspect(error)}")
            "# Error retrieving cluster metrics\n"
        end
    end
  end
  
  defp convert_cluster_to_prometheus(metrics) do
    header = """
    # Autonomous Opponent VSM Cluster Metrics
    # Generated at: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    # Nodes: #{length(Node.list()) + 1}
    
    """
    
    metric_lines = Enum.map_join(metrics, "\n", fn metric ->
      # Format each aggregated metric
      base_name = metric.name
      
      # Output aggregated values
      lines = []
      
      if metric.aggregated[:sum] do
        lines = ["#{base_name}_cluster_sum #{metric.aggregated.sum}" | lines]
      end
      
      if metric.aggregated[:avg] do
        lines = ["#{base_name}_cluster_avg #{metric.aggregated.avg}" | lines]
      end
      
      if metric.aggregated[:min] do
        lines = ["#{base_name}_cluster_min #{metric.aggregated.min}" | lines]
      end
      
      if metric.aggregated[:max] do
        lines = ["#{base_name}_cluster_max #{metric.aggregated.max}" | lines]
      end
      
      # Add per-node breakdown
      node_lines = Enum.map(metric.node_values, fn {node, value} ->
        "#{base_name}_by_node{node=\"#{node}\"} #{value}"
      end)
      
      Enum.join(lines ++ node_lines, "\n")
    end)
    
    header <> metric_lines
  end
  
  defp build_query_opts(params) do
    opts = []
    
    opts = if from = params["from"] do
      [{:from, parse_time(from)} | opts]
    else
      opts
    end
    
    opts = if to = params["to"] do
      [{:to, parse_time(to)} | opts]
    else
      opts
    end
    
    opts = if nodes = params["nodes"] do
      nodes_list = String.split(nodes, ",") |> Enum.map(&String.to_atom/1)
      [{:nodes, nodes_list} | opts]
    else
      opts
    end
    
    opts
  end
  
  defp parse_time(time_str) do
    case DateTime.from_iso8601(time_str) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now()
    end
  end
  
  defp format_cluster_metrics(metrics) when is_list(metrics) do
    Enum.map(metrics, &format_metric/1)
  end
  
  defp format_cluster_metrics(metric), do: format_metric(metric)
  
  defp format_metric(metric) when is_map(metric) do
    metric
  end
  
  defp format_metric(value), do: value

  # Enhance Prometheus output with type annotations and meta-metrics
  defp enhance_prometheus_output(metrics_text) do
    cardinality = count_metric_cardinality(metrics_text)
    
    # Check cardinality limit
    if cardinality > @max_metric_cardinality do
      require Logger
      Logger.error("Metric cardinality (#{cardinality}) exceeds limit (#{@max_metric_cardinality})")
      
      # Return warning with truncated metrics
      warning = """
      # WARNING: Metric cardinality (#{cardinality}) exceeds limit (#{@max_metric_cardinality})
      # Metrics have been truncated to prevent memory exhaustion
      # Generated at: #{DateTime.utc_now() |> DateTime.to_iso8601()}
      
      """
      
      # Truncate metrics to stay under limit
      truncated_metrics = truncate_metrics_safely(metrics_text, @max_metric_cardinality)
      warning <> truncated_metrics
    else
      # Add header with metadata
      header = """
      # Autonomous Opponent VSM Metrics
      # Generated at: #{DateTime.utc_now() |> DateTime.to_iso8601()}
      # Cardinality: #{cardinality} metrics
      
      """
      
      # Add type annotations for known metrics
      type_annotations = """
      # HELP vsm_variety_absorbed The amount of variety absorbed by each subsystem
      # TYPE vsm_variety_absorbed counter
      # HELP vsm_variety_generated The amount of variety generated by each subsystem  
      # TYPE vsm_variety_generated counter
      # HELP vsm_algedonic_pain Pain signals intensity (0-1)
      # TYPE vsm_algedonic_pain gauge
      # HELP vsm_algedonic_pleasure Pleasure signals intensity (0-1)
      # TYPE vsm_algedonic_pleasure gauge
      # HELP vsm_subsystem_health Health percentage of each VSM subsystem
      # TYPE vsm_subsystem_health gauge
      # HELP vsm_cybernetic_loop_latency Latency of cybernetic feedback loops in milliseconds
      # TYPE vsm_cybernetic_loop_latency histogram
      # HELP metrics_cardinality_total Current number of unique metric series
      # TYPE metrics_cardinality_total gauge
      
      """
      
      # Add meta-metrics about the metrics system
      meta_metrics = generate_meta_metrics(metrics_text, cardinality)
      
      # Combine all parts
      header <> type_annotations <> metrics_text <> "\n" <> meta_metrics
    end
  end

  # Count unique metric series for cardinality tracking
  defp count_metric_cardinality(metrics_text) do
    metrics_text
    |> String.split("\n")
    |> Enum.reject(&(String.starts_with?(&1, "#") || String.trim(&1) == ""))
    |> Enum.map(&extract_metric_name/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.count()
  end
  
  # Extract metric name from a metric line
  defp extract_metric_name(line) do
    # Match metric name with optional labels
    # Format: metric_name{labels} value or metric_name value
    case Regex.run(~r/^([a-zA-Z_][a-zA-Z0-9_:]*)(?:[\s{]|$)/, line) do
      [_, name] -> name
      _ -> nil
    end
  end

  # Generate meta-metrics about the metrics system itself
  defp generate_meta_metrics(metrics_text, cardinality) do
    size_bytes = byte_size(metrics_text)
    
    """
    # Meta-metrics for observability of the metrics system
    metrics_cardinality_total #{cardinality}
    metrics_response_size_bytes #{size_bytes}
    metrics_endpoint_up 1
    """
  end
  
  # Safely truncate metrics to stay under cardinality limit
  defp truncate_metrics_safely(metrics_text, limit) do
    metrics_text
    |> String.split("\n")
    |> Enum.take(limit)
    |> Enum.join("\n")
  end
end