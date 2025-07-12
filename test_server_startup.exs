#!/usr/bin/env elixir

# Test server startup issue
IO.puts("Testing server startup...")

# Start applications manually to find the issue
apps = [
  :logger,
  :runtime_tools,
  :telemetry,
  :jason,
  :poolboy,
  :postgrex,
  :ecto,
  :phoenix,
  :phoenix_ecto,
  :phoenix_html,
  :phoenix_live_view,
  :phoenix_live_dashboard,
  :autonomous_opponent_core,
  :autonomous_opponent_web
]

Enum.each(apps, fn app ->
  case Application.ensure_all_started(app) do
    {:ok, _} -> 
      IO.puts("✅ Started #{app}")
    {:error, {app_name, reason}} ->
      IO.puts("❌ Failed to start #{app_name}: #{inspect(reason)}")
      if app == :autonomous_opponent_core do
        IO.puts("\nDetailed error:")
        IO.inspect(reason, pretty: true, limit: :infinity)
      end
  end
end)