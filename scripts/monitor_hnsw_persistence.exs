# HNSW Persistence Telemetry Monitor
# This script sets up telemetry monitoring for HNSW persistence metrics

IO.puts("\n🔭 VSM S4 Intelligence - HNSW Persistence Monitor\n")

# Attach telemetry handlers for all HNSW persistence events
handlers = [
  {
    [:hnsw, :persistence, :started],
    "HNSW persistence started",
    fn _event, measurements, metadata, _config ->
      IO.puts("\n🚀 HNSW Persistence Started")
      IO.puts("   Pattern count: #{measurements.pattern_count}")
      IO.puts("   Variety pressure: #{Float.round(measurements.variety_pressure || 0.0, 2)}")
      IO.puts("   Path: #{metadata.path}")
      IO.puts("   Timestamp: #{DateTime.utc_now() |> DateTime.to_string()}")
    end
  },
  {
    [:hnsw, :persistence, :completed],
    "HNSW persistence completed",
    fn _event, measurements, metadata, _config ->
      IO.puts("\n✅ HNSW Persistence Completed")
      IO.puts("   Duration: #{measurements.duration_ms}ms")
      IO.puts("   Pattern count: #{measurements.pattern_count}")
      IO.puts("   File size: #{measurements.file_size_bytes} bytes")
      IO.puts("   Compression ratio: #{Float.round(measurements.compression_ratio || 1.0, 2)}")
      IO.puts("   Path: #{metadata.path}")
      
      # Calculate throughput
      if measurements.duration_ms > 0 do
        throughput = measurements.pattern_count / (measurements.duration_ms / 1000)
        IO.puts("   Throughput: #{Float.round(throughput, 1)} patterns/sec")
      end
    end
  },
  {
    [:hnsw, :persistence, :failed],
    "HNSW persistence failed",
    fn _event, measurements, metadata, _config ->
      IO.puts("\n❌ HNSW Persistence Failed")
      IO.puts("   Duration: #{measurements.duration_ms}ms")
      IO.puts("   Error: #{inspect(metadata.error)}")
      IO.puts("   Path: #{metadata.path}")
      
      # Emit algedonic pain signal
      EventBus.publish(:vsm_algedonic_signal, %{
        source: :s4_intelligence,
        type: :pain,
        intensity: 0.8,
        reason: "HNSW persistence failure",
        metadata: %{error: metadata.error}
      })
    end
  },
  {
    [:hnsw, :restoration, :started],
    "HNSW restoration started",
    fn _event, _measurements, metadata, _config ->
      IO.puts("\n📂 HNSW Restoration Started")
      IO.puts("   Path: #{metadata.path}")
      IO.puts("   Timestamp: #{DateTime.utc_now() |> DateTime.to_string()}")
    end
  },
  {
    [:hnsw, :restoration, :completed],
    "HNSW restoration completed",
    fn _event, measurements, metadata, _config ->
      IO.puts("\n✅ HNSW Restoration Completed")
      IO.puts("   Duration: #{measurements.duration_ms}ms")
      IO.puts("   Pattern count: #{measurements.pattern_count}")
      IO.puts("   Index parameters: #{inspect(measurements.parameters)}")
      IO.puts("   Path: #{metadata.path}")
    end
  },
  {
    [:hnsw, :emergency_pruning, :triggered],
    "Emergency pruning triggered",
    fn _event, measurements, metadata, _config ->
      IO.puts("\n⚠️  HNSW Emergency Pruning Triggered!")
      IO.puts("   Variety pressure: #{Float.round(measurements.variety_pressure, 2)}")
      IO.puts("   Current patterns: #{measurements.current_patterns}")
      IO.puts("   Target patterns: #{measurements.target_patterns}")
      IO.puts("   Pruning strategy: #{metadata.strategy}")
      
      # Emit algedonic pain signal for high variety
      EventBus.publish(:vsm_algedonic_signal, %{
        source: :s4_intelligence,
        type: :pain,
        intensity: measurements.variety_pressure,
        reason: "High variety pressure triggering emergency pruning"
      })
    end
  },
  {
    [:hnsw, :adaptive_interval, :adjusted],
    "Adaptive interval adjusted",
    fn _event, measurements, metadata, _config ->
      IO.puts("\n⏱️  HNSW Adaptive Interval Adjusted")
      IO.puts("   Insertion rate: #{Float.round(measurements.insertion_rate, 2)} patterns/sec")
      IO.puts("   New interval: #{measurements.new_interval_ms}ms")
      IO.puts("   Previous interval: #{measurements.previous_interval_ms}ms")
      IO.puts("   Adjustment factor: #{Float.round(measurements.adjustment_factor, 2)}")
    end
  }
]

# Attach all handlers
for {event, name, handler} <- handlers do
  :telemetry.attach(
    "monitor-#{:erlang.phash2(event)}",
    event,
    handler,
    nil
  )
  IO.puts("📊 Attached handler for: #{name}")
end

IO.puts("\n\n🎯 Monitoring Setup Complete!")
IO.puts("The following HNSW persistence metrics are being monitored:")
IO.puts("  • Persistence start/complete/fail events")
IO.puts("  • Restoration events")
IO.puts("  • Emergency pruning triggers")
IO.puts("  • Adaptive interval adjustments")
IO.puts("\n💡 This monitor will display real-time telemetry as HNSW persistence events occur.")
IO.puts("   Leave this running to observe S4 Intelligence's pattern memory management.")

# State tracking for summary view
defmodule HNSWMonitor.State do
  defstruct [
    start_time: DateTime.utc_now(),
    persistence_count: 0,
    persistence_failures: 0,
    total_patterns_persisted: 0,
    total_persist_duration_ms: 0,
    restorations: 0,
    emergency_prunes: 0,
    adaptive_adjustments: 0,
    last_insertion_rate: 0.0,
    patterns_inserted: 0,
    patterns_pruned: 0,
    last_update: DateTime.utc_now()
  ]
end

# Start agent to track state
{:ok, state_agent} = Agent.start_link(fn -> %HNSWMonitor.State{} end)

# Function to update summary statistics
update_summary = fn ->
  state = Agent.get(state_agent, & &1)
  runtime_seconds = DateTime.diff(DateTime.utc_now(), state.start_time)
  runtime_minutes = runtime_seconds / 60
  
  IO.puts("\n" <> String.duplicate("=", 80))
  IO.puts("📊 HNSW PERSISTENCE SUMMARY (#{Float.round(runtime_minutes, 1)} minutes)")
  IO.puts(String.duplicate("=", 80))
  
  # Persistence statistics
  success_rate = if state.persistence_count > 0 do
    ((state.persistence_count - state.persistence_failures) / state.persistence_count * 100) |> Float.round(1)
  else
    100.0
  end
  
  avg_persist_time = if state.persistence_count > 0 do
    (state.total_persist_duration_ms / state.persistence_count) |> Float.round(1)
  else
    0.0
  end
  
  IO.puts("\n🗄️  Persistence Statistics:")
  IO.puts("   Total persists: #{state.persistence_count}")
  IO.puts("   Success rate: #{success_rate}%")
  IO.puts("   Average time: #{avg_persist_time}ms")
  IO.puts("   Total patterns saved: #{state.total_patterns_persisted}")
  
  # Pattern flow rates
  insertion_rate = if runtime_minutes > 0 do
    (state.patterns_inserted / runtime_minutes) |> Float.round(1)
  else
    0.0
  end
  
  prune_rate = if runtime_minutes > 0 do
    (state.patterns_pruned / runtime_minutes) |> Float.round(1)
  else
    0.0
  end
  
  net_growth_rate = insertion_rate - prune_rate
  
  IO.puts("\n📈 Pattern Flow Rates (per minute):")
  IO.puts("   Insertion rate: #{insertion_rate} patterns/min")
  IO.puts("   Pruning rate: #{prune_rate} patterns/min")
  IO.puts("   Net growth: #{net_growth_rate} patterns/min")
  IO.puts("   Current insertion rate: #{Float.round(state.last_insertion_rate * 60, 1)} patterns/min")
  
  # System health
  IO.puts("\n🏥 System Health:")
  IO.puts("   Restorations: #{state.restorations}")
  IO.puts("   Emergency prunes: #{state.emergency_prunes}")
  IO.puts("   Adaptive adjustments: #{state.adaptive_adjustments}")
  IO.puts("   Failures: #{state.persistence_failures}")
  
  # Projections
  if net_growth_rate > 0 do
    days_to_100k = (100_000 - state.total_patterns_persisted) / (net_growth_rate * 60 * 24)
    IO.puts("\n🔮 Projections:")
    IO.puts("   Days to 100k patterns: #{Float.round(days_to_100k, 1)}")
  end
  
  IO.puts("\n" <> String.duplicate("=", 80))
end

# Enhanced telemetry handlers with state tracking
handlers = [
  {
    [:hnsw, :persistence, :started],
    "HNSW persistence started",
    fn _event, measurements, metadata, _config ->
      IO.puts("\n🚀 HNSW Persistence Started")
      IO.puts("   Pattern count: #{measurements.pattern_count}")
      IO.puts("   Variety pressure: #{Float.round(measurements.variety_pressure || 0.0, 2)}")
      IO.puts("   Path: #{metadata.path}")
      IO.puts("   Timestamp: #{DateTime.utc_now() |> DateTime.to_string()}")
    end
  },
  {
    [:hnsw, :persistence, :completed],
    "HNSW persistence completed",
    fn _event, measurements, metadata, _config ->
      IO.puts("\n✅ HNSW Persistence Completed")
      IO.puts("   Duration: #{measurements.duration_ms}ms")
      IO.puts("   Pattern count: #{measurements.pattern_count}")
      IO.puts("   File size: #{measurements.file_size_bytes} bytes")
      IO.puts("   Compression ratio: #{Float.round(measurements.compression_ratio || 1.0, 2)}")
      IO.puts("   Path: #{metadata.path}")
      
      # Calculate throughput
      if measurements.duration_ms > 0 do
        throughput = measurements.pattern_count / (measurements.duration_ms / 1000)
        IO.puts("   Throughput: #{Float.round(throughput, 1)} patterns/sec")
      end
      
      # Update state
      Agent.update(state_agent, fn state ->
        %{state |
          persistence_count: state.persistence_count + 1,
          total_patterns_persisted: state.total_patterns_persisted + measurements.pattern_count,
          total_persist_duration_ms: state.total_persist_duration_ms + measurements.duration_ms,
          last_update: DateTime.utc_now()
        }
      end)
    end
  },
  {
    [:hnsw, :persistence, :failed],
    "HNSW persistence failed",
    fn _event, measurements, metadata, _config ->
      IO.puts("\n❌ HNSW Persistence Failed")
      IO.puts("   Duration: #{measurements.duration_ms}ms")
      IO.puts("   Error: #{inspect(metadata.error)}")
      IO.puts("   Path: #{metadata.path}")
      
      # Update state
      Agent.update(state_agent, fn state ->
        %{state |
          persistence_count: state.persistence_count + 1,
          persistence_failures: state.persistence_failures + 1,
          last_update: DateTime.utc_now()
        }
      end)
      
      # Emit algedonic pain signal
      EventBus.publish(:vsm_algedonic_signal, %{
        source: :s4_intelligence,
        type: :pain,
        intensity: 0.8,
        reason: "HNSW persistence failure",
        metadata: %{error: metadata.error}
      })
    end
  },
  {
    [:hnsw, :restoration, :started],
    "HNSW restoration started",
    fn _event, _measurements, metadata, _config ->
      IO.puts("\n📂 HNSW Restoration Started")
      IO.puts("   Path: #{metadata.path}")
      IO.puts("   Timestamp: #{DateTime.utc_now() |> DateTime.to_string()}")
    end
  },
  {
    [:hnsw, :restoration, :completed],
    "HNSW restoration completed",
    fn _event, measurements, metadata, _config ->
      IO.puts("\n✅ HNSW Restoration Completed")
      IO.puts("   Duration: #{measurements.duration_ms}ms")
      IO.puts("   Pattern count: #{measurements.pattern_count}")
      IO.puts("   Index parameters: #{inspect(measurements.parameters)}")
      IO.puts("   Path: #{metadata.path}")
      
      # Update state
      Agent.update(state_agent, fn state ->
        %{state |
          restorations: state.restorations + 1,
          last_update: DateTime.utc_now()
        }
      end)
    end
  },
  {
    [:hnsw, :emergency_pruning, :triggered],
    "Emergency pruning triggered",
    fn _event, measurements, metadata, _config ->
      IO.puts("\n⚠️  HNSW Emergency Pruning Triggered!")
      IO.puts("   Variety pressure: #{Float.round(measurements.variety_pressure, 2)}")
      IO.puts("   Current patterns: #{measurements.current_patterns}")
      IO.puts("   Target patterns: #{measurements.target_patterns}")
      IO.puts("   Pruning strategy: #{metadata.strategy}")
      
      # Update state
      Agent.update(state_agent, fn state ->
        %{state |
          emergency_prunes: state.emergency_prunes + 1,
          patterns_pruned: state.patterns_pruned + (measurements.current_patterns - measurements.target_patterns),
          last_update: DateTime.utc_now()
        }
      end)
      
      # Emit algedonic pain signal for high variety
      EventBus.publish(:vsm_algedonic_signal, %{
        source: :s4_intelligence,
        type: :pain,
        intensity: measurements.variety_pressure,
        reason: "High variety pressure triggering emergency pruning"
      })
    end
  },
  {
    [:hnsw, :adaptive_interval, :adjusted],
    "Adaptive interval adjusted",
    fn _event, measurements, metadata, _config ->
      IO.puts("\n⏱️  HNSW Adaptive Interval Adjusted")
      IO.puts("   Insertion rate: #{Float.round(measurements.insertion_rate, 2)} patterns/sec")
      IO.puts("   New interval: #{measurements.new_interval_ms}ms")
      IO.puts("   Previous interval: #{measurements.previous_interval_ms}ms")
      IO.puts("   Adjustment factor: #{Float.round(measurements.adjustment_factor, 2)}")
      
      # Update state
      Agent.update(state_agent, fn state ->
        %{state |
          adaptive_adjustments: state.adaptive_adjustments + 1,
          last_insertion_rate: measurements.insertion_rate,
          last_update: DateTime.utc_now()
        }
      end)
    end
  },
  {
    [:hnsw, :pattern, :inserted],
    "Pattern inserted",
    fn _event, _measurements, _metadata, _config ->
      # Silently track insertions
      Agent.update(state_agent, fn state ->
        %{state | patterns_inserted: state.patterns_inserted + 1}
      end)
    end
  }
]

# Keep the script running
IO.puts("\n⏳ Monitoring active... Press Ctrl+C to stop.\n")

# Print summary every 30 seconds
Task.start(fn ->
  Process.sleep(30_000)  # Wait 30 seconds before first summary
  
  Stream.iterate(1, &(&1 + 1))
  |> Enum.each(fn _ ->
    update_summary.()
    Process.sleep(30_000)  # Update every 30 seconds
  end)
end)

# Optional: Trigger a manual persistence to test
IO.puts("🧪 Triggering a test persistence event...")
GenServer.cast(
  {:via, Registry, {AutonomousOpponentV2Core.VSM.S4.VectorStore.Registry, :hnsw_index}},
  :persist_now
)

# Keep the process alive
Process.sleep(:infinity)