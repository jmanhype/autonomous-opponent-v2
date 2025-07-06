defmodule AutonomousOpponentV2Web.ConsciousnessPage do
  @moduledoc """
  Custom Phoenix LiveDashboard page for Consciousness metrics and monitoring.
  """
  
  use Phoenix.LiveDashboard.PageBuilder
  alias AutonomousOpponentV2Core.Consciousness
  
  @impl true
  def menu_link(_, _) do
    {:ok, "Consciousness"}
  end
  
  @impl true
  def render_page(assigns) do
    # For now, return a simple HTML structure
    ~H"""
    <div class="p-6">
      <h1 class="text-2xl font-bold mb-4">Consciousness System Metrics</h1>
      <div class="grid gap-4">
        <div class="bg-white rounded-lg shadow p-4">
          <h2 class="text-lg font-semibold mb-2">Current State</h2>
          <p class="text-gray-600">System is operational</p>
        </div>
      </div>
    </div>
    """
  end
  
  defp fetch_consciousness_data(_params, _node) do
    # Get current consciousness state
    consciousness_data = case Consciousness.get_consciousness_state() do
      {:ok, state} -> state
      _ -> %{}
    end
    
    # Get inner dialog
    inner_dialog = case Consciousness.get_inner_dialog() do
      {:ok, dialog} -> dialog
      _ -> []
    end
    
    # Build metrics rows
    rows = [
      %{
        metric: "Current State",
        value: Map.get(consciousness_data, :state, "unknown") |> to_string(),
        description: "The current consciousness state",
        category: "State"
      },
      %{
        metric: "Awareness Level",
        value: Map.get(consciousness_data, :awareness_level, 0.0) |> Float.round(2) |> to_string(),
        description: "Current awareness level (0.0 - 1.0)",
        category: "Awareness"
      },
      %{
        metric: "Identity Coherence",
        value: Map.get(consciousness_data, :identity_coherence, 0.0) |> Float.round(2) |> to_string(),
        description: "Identity coherence factor",
        category: "Identity"
      },
      %{
        metric: "Inner Dialog Entries",
        value: length(inner_dialog) |> to_string(),
        description: "Number of recent inner dialog entries",
        category: "Dialog"
      },
      %{
        metric: "Latest Thought",
        value: List.first(inner_dialog) || "No thoughts yet",
        description: "Most recent inner dialog entry",
        category: "Dialog"
      },
      %{
        metric: "Last Update",
        value: Map.get(consciousness_data, :timestamp, DateTime.utc_now()) |> DateTime.to_string(),
        description: "When consciousness was last updated",
        category: "Time"
      }
    ]
    
    # Add telemetry-based metrics if available
    telemetry_rows = fetch_telemetry_metrics()
    
    {rows ++ telemetry_rows, length(rows) + length(telemetry_rows)}
  end
  
  defp fetch_telemetry_metrics do
    # In a real implementation, we would fetch these from telemetry storage
    # For now, return some placeholder metrics
    [
      %{
        metric: "Total Reflections",
        value: "0",
        description: "Total reflections completed",
        category: "Activity"
      },
      %{
        metric: "Dialog Exchanges",
        value: "0",
        description: "Total dialog exchanges",
        category: "Activity"
      },
      %{
        metric: "Existential Inquiries",
        value: "0",
        description: "Total existential questions answered",
        category: "Activity"
      },
      %{
        metric: "State Changes Today",
        value: "0",
        description: "Consciousness state changes in last 24h",
        category: "Activity"
      }
    ]
  end
  
  defp columns do
    [
      %{
        field: :metric,
        header: "Metric",
        header_attrs: [class: "text-left"],
        cell_attrs: [class: "text-left font-medium"],
        sortable: :asc
      },
      %{
        field: :value,
        header: "Value",
        header_attrs: [class: "text-left"],
        cell_attrs: [class: "text-left"],
        format: &format_value/1
      },
      %{
        field: :description,
        header: "Description",
        header_attrs: [class: "text-left"],
        cell_attrs: [class: "text-left text-gray-600"]
      },
      %{
        field: :category,
        header: "Category",
        header_attrs: [class: "text-left"],
        cell_attrs: [class: "text-left"],
        format: &format_category/1
      }
    ]
  end
  
  defp row_attrs(row) do
    [
      {"phx-click", "show_detail"},
      {"phx-value-metric", row[:metric]},
      {"phx-page-loading", true}
    ]
  end
  
  defp format_value(value) when is_binary(value) do
    if String.length(value) > 50 do
      String.slice(value, 0, 47) <> "..."
    else
      value
    end
  end
  defp format_value(value), do: to_string(value)
  
  defp format_category(category) do
    color = case category do
      "State" -> "blue"
      "Awareness" -> "green"
      "Identity" -> "purple"
      "Dialog" -> "yellow"
      "Activity" -> "orange"
      "Time" -> "gray"
      _ -> "gray"
    end
    
    {:safe, ~s(<span class="px-2 py-1 text-xs rounded-full bg-#{color}-100 text-#{color}-800">#{category}</span>)}
  end
end