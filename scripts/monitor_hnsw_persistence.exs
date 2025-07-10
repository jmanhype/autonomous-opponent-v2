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

# Keep the script running
IO.puts("\n⏳ Monitoring active... Press Ctrl+C to stop.\n")

# Optional: Trigger a manual persistence to test
IO.puts("🧪 Triggering a test persistence event...")
GenServer.cast(
  {:via, Registry, {AutonomousOpponentV2Core.VSM.S4.VectorStore.Registry, :hnsw_index}},
  :persist_now
)

# Keep the process alive
Process.sleep(:infinity)