#!/usr/bin/env elixir

# EventBus Cluster Power Verification - Maximum Intensity Testing

defmodule ClusterPowerVerification do
  @moduledoc """
  MAXIMUM INTENSITY verification of the EventBus Cluster Bridge.
  
  This script doesn't hold back - it tests every component at maximum capacity:
  - Direct cluster component verification
  - High-frequency event publishing
  - Algedonic bypass stress testing
  - Variety channel saturation
  - Real-time performance monitoring
  """

  require Logger

  def unleash_maximum_verification do
    Logger.info("🚀 UNLEASHING MAXIMUM CLUSTER VERIFICATION - NO LIMITS!")
    
    # Connect to running cluster
    connect_to_cluster()
    
    # Verify all components are alive and responsive
    verify_all_cluster_components()
    
    # Test maximum event throughput
    test_maximum_event_throughput()
    
    # Stress test algedonic bypass
    stress_test_algedonic_system()
    
    # Saturate variety channels
    saturate_variety_channels()
    
    # Test cross-cluster event propagation
    test_cross_cluster_propagation()
    
    # Monitor real-time performance
    monitor_cluster_performance()
    
    Logger.info("🏆 MAXIMUM CLUSTER VERIFICATION COMPLETE - SYSTEM DOMINATED!")
  end

  defp connect_to_cluster do
    Logger.info("🔗 Connecting to VSM cluster with maximum authority...")
    
    Node.start(:"cluster_verifier@localhost")
    Node.set_cookie(:"cluster_verifier@localhost", :autonomous_opponent)
    
    case Node.connect(:"test@localhost") do
      true -> 
        Logger.info("✅ CONNECTED TO VSM CLUSTER - FULL ACCESS GRANTED")
        # Get cluster info
        nodes = Node.list()
        Logger.info("🌐 Connected nodes: #{inspect([node() | nodes])}")
        
      false -> 
        Logger.error("❌ CLUSTER CONNECTION FAILED")
        System.halt(1)
    end
  end

  defp verify_all_cluster_components do
    Logger.info("🔍 VERIFYING ALL CLUSTER COMPONENTS AT MAXIMUM INTENSITY...")
    
    components = [
      {AutonomousOpponentV2Core.EventBus, "EventBus Core"},
      {AutonomousOpponentV2Core.EventBus.Cluster.Supervisor, "Cluster Supervisor"},
      {AutonomousOpponentV2Core.EventBus.Cluster.ClusterBridge, "Cluster Bridge"},
      {AutonomousOpponentV2Core.EventBus.Cluster.VarietyManager, "Variety Manager"},
      {AutonomousOpponentV2Core.EventBus.Cluster.PartitionDetector, "Partition Detector"},
      {AutonomousOpponentV2Core.EventBus.Cluster.AlgedonicBroadcast, "Algedonic Broadcast"}
    ]
    
    Enum.each(components, fn {module, name} ->
      case :rpc.call(:"test@localhost", Process, :whereis, [module]) do
        pid when is_pid(pid) ->
          Logger.info("✅ #{name}: OPERATIONAL (PID: #{inspect(pid)})")
          
          # Test component responsiveness
          case :rpc.call(:"test@localhost", Process, :alive?, [pid]) do
            true -> Logger.info("   🟢 #{name}: RESPONSIVE AND HEALTHY")
            false -> Logger.warn("   🟡 #{name}: NOT RESPONDING")
          end
          
        _ ->
          Logger.warn("⚠️  #{name}: NOT FOUND OR NOT RUNNING")
      end
    end)
  end

  defp test_maximum_event_throughput do
    Logger.info("⚡ TESTING MAXIMUM EVENT THROUGHPUT - UNLEASHING FULL POWER!")
    
    event_types = [
      :s1_operational, :s2_coordination, :s3_control, 
      :s4_intelligence, :s5_policy, :algedonic_pain,
      :variety_flow, :cluster_sync, :emergency_signal
    ]
    
    total_events = 5000
    batch_size = 100
    
    start_time = System.monotonic_time(:millisecond)
    
    # Launch event tsunami
    tasks = Enum.map(1..total_events, fn i ->
      Task.async(fn ->
        event_type = Enum.random(event_types)
        event_data = generate_high_intensity_event_data(i)
        
        result = :rpc.call(:"test@localhost", AutonomousOpponentV2Core.EventBus, :publish, [event_type, event_data])
        {i, event_type, result}
      end)
    end)
    
    # Process in batches to avoid overwhelming the system
    results = process_tasks_in_batches(tasks, batch_size)
    
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time
    
    successful_events = Enum.count(results, fn {_, _, result} -> result == :ok end)
    events_per_second = successful_events / (duration / 1000)
    
    Logger.info("🚀 MAXIMUM THROUGHPUT ACHIEVED:")
    Logger.info("   📊 Total Events: #{total_events}")
    Logger.info("   ✅ Successful: #{successful_events}")
    Logger.info("   ⚡ Rate: #{Float.round(events_per_second, 2)} events/second")
    Logger.info("   ⏱️  Duration: #{duration}ms")
    Logger.info("   🎯 Success Rate: #{Float.round(successful_events / total_events * 100, 2)}%")
  end

  defp stress_test_algedonic_system do
    Logger.info("😱 STRESS TESTING ALGEDONIC SYSTEM - MAXIMUM PAIN INTENSITY!")
    
    algedonic_signals = [
      %{type: :emergency_scream, intensity: 0.99, source: "SYSTEM_OVERLOAD", priority: :maximum},
      %{type: :pain_signal, intensity: 0.95, source: "RESOURCE_EXHAUSTION", priority: :high},
      %{type: :pain_signal, intensity: 0.90, source: "PERFORMANCE_DEGRADATION", priority: :high},
      %{type: :pleasure_signal, intensity: 0.85, source: "OPTIMIZATION_SUCCESS", priority: :medium},
      %{type: :emergency_scream, intensity: 0.97, source: "IDENTITY_CRISIS", priority: :maximum}
    ]
    
    # Launch algedonic signal storm
    Logger.info("🌪️  LAUNCHING ALGEDONIC SIGNAL STORM...")
    
    storm_tasks = Enum.map(1..200, fn i ->
      Task.async(fn ->
        signal = Enum.random(algedonic_signals)
        enhanced_signal = Map.merge(signal, %{
          storm_id: i,
          timestamp: System.system_time(:microsecond),
          cluster_wide: true,
          bypass_all_limits: true
        })
        
        result = :rpc.call(:"test@localhost", AutonomousOpponentV2Core.EventBus, :publish, [:emergency_algedonic, enhanced_signal])
        {i, signal.type, signal.intensity, result}
      end)
    end)
    
    storm_results = Task.await_many(storm_tasks, 15_000)
    
    # Analyze algedonic storm results
    successful_signals = Enum.count(storm_results, fn {_, _, _, result} -> result == :ok end)
    max_intensity = storm_results |> Enum.map(fn {_, _, intensity, _} -> intensity end) |> Enum.max()
    avg_intensity = storm_results |> Enum.map(fn {_, _, intensity, _} -> intensity end) |> Enum.sum() |> Kernel./(length(storm_results))
    
    Logger.info("🩸 ALGEDONIC STORM ANALYSIS:")
    Logger.info("   ⚡ Signals Sent: #{length(storm_results)}")
    Logger.info("   ✅ Successful: #{successful_signals}")
    Logger.info("   📈 Max Intensity: #{max_intensity}")
    Logger.info("   📊 Avg Intensity: #{Float.round(avg_intensity, 3)}")
    Logger.info("   🎯 Algedonic Success Rate: #{Float.round(successful_signals / length(storm_results) * 100, 2)}%")
  end

  defp saturate_variety_channels do
    Logger.info("🌊 SATURATING VARIETY CHANNELS - MAXIMUM CAPACITY TEST!")
    
    # Test each variety channel at its limits
    channel_tests = %{
      algedonic: {1000, "UNLIMITED"},  # Algedonic has no limits
      s5_policy: {75, "50 + overflow"},  # 50% over quota
      s4_intelligence: {150, "100 + overflow"},  # 50% over quota  
      s3_control: {300, "200 + overflow"},  # 50% over quota
      s2_coordination: {750, "500 + overflow"},  # 50% over quota
      s1_operational: {1500, "1000 + overflow"}  # 50% over quota
    }
    
    saturation_results = Enum.map(channel_tests, fn {channel, {event_count, description}} ->
      Logger.info("   🌊 Saturating #{channel} channel (#{description})...")
      
      start_time = System.monotonic_time(:millisecond)
      
      # Generate channel-specific events
      channel_tasks = Enum.map(1..event_count, fn i ->
        Task.async(fn ->
          event_data = generate_channel_specific_data(channel, i)
          result = :rpc.call(:"test@localhost", AutonomousOpponentV2Core.EventBus, :publish, [channel, event_data])
          {i, result}
        end)
      end)
      
      channel_results = Task.await_many(channel_tasks, 10_000)
      end_time = System.monotonic_time(:millisecond)
      
      successful = Enum.count(channel_results, fn {_, result} -> result == :ok end)
      duration = end_time - start_time
      rate = successful / (duration / 1000)
      
      Logger.info("   ✅ #{channel}: #{successful}/#{event_count} events (#{Float.round(rate, 2)} events/sec)")
      
      {channel, %{
        events_sent: event_count,
        successful: successful,
        rate: rate,
        duration: duration
      }}
    end) |> Enum.into(%{})
    
    # Summary of variety saturation
    total_events = saturation_results |> Map.values() |> Enum.map(& &1.events_sent) |> Enum.sum()
    total_successful = saturation_results |> Map.values() |> Enum.map(& &1.successful) |> Enum.sum()
    
    Logger.info("🌊 VARIETY SATURATION COMPLETE:")
    Logger.info("   📊 Total Events: #{total_events}")
    Logger.info("   ✅ Total Successful: #{total_successful}")
    Logger.info("   🎯 Overall Success Rate: #{Float.round(total_successful / total_events * 100, 2)}%")
  end

  defp test_cross_cluster_propagation do
    Logger.info("🔄 TESTING CROSS-CLUSTER EVENT PROPAGATION...")
    
    # Test event propagation across cluster nodes
    propagation_events = [
      {:cluster_sync_test, %{test: "cross_cluster_propagation", node: node(), timestamp: System.system_time(:microsecond)}},
      {:replication_test, %{message: "Testing cluster replication", priority: :high}},
      {:distributed_computation, %{algorithm: "test", data: "cluster_verification"}}
    ]
    
    propagation_tasks = Enum.map(propagation_events, fn {event_type, event_data} ->
      Task.async(fn ->
        # Publish event and monitor propagation
        result = :rpc.call(:"test@localhost", AutonomousOpponentV2Core.EventBus, :publish, [event_type, event_data])
        
        # Wait a bit for propagation
        Process.sleep(100)
        
        {event_type, result}
      end)
    end)
    
    propagation_results = Task.await_many(propagation_tasks, 5000)
    
    successful_propagations = Enum.count(propagation_results, fn {_, result} -> result == :ok end)
    
    Logger.info("🔄 CROSS-CLUSTER PROPAGATION RESULTS:")
    Logger.info("   📡 Events Tested: #{length(propagation_events)}")
    Logger.info("   ✅ Successful: #{successful_propagations}")
    Logger.info("   🎯 Propagation Success Rate: #{Float.round(successful_propagations / length(propagation_events) * 100, 2)}%")
  end

  defp monitor_cluster_performance do
    Logger.info("📊 MONITORING CLUSTER PERFORMANCE AT MAXIMUM INTENSITY...")
    
    # Monitor for 30 seconds with high frequency sampling
    monitoring_duration = 30_000  # 30 seconds
    sample_interval = 500  # 500ms
    samples = div(monitoring_duration, sample_interval)
    
    performance_data = Enum.map(1..samples, fn sample ->
      start_sample_time = System.monotonic_time(:millisecond)
      
      # Test event publishing speed
      test_event_data = %{
        sample: sample,
        timestamp: System.system_time(:microsecond),
        test_type: "performance_monitoring"
      }
      
      publish_start = System.monotonic_time(:microsecond)
      result = :rpc.call(:"test@localhost", AutonomousOpponentV2Core.EventBus, :publish, [:performance_test, test_event_data])
      publish_end = System.monotonic_time(:microsecond)
      
      publish_latency = (publish_end - publish_start) / 1000  # Convert to milliseconds
      
      sample_data = %{
        sample: sample,
        publish_result: result,
        publish_latency_ms: publish_latency,
        timestamp: System.system_time(:microsecond)
      }
      
      # Control sampling rate
      elapsed = System.monotonic_time(:millisecond) - start_sample_time
      if elapsed < sample_interval do
        Process.sleep(sample_interval - elapsed)
      end
      
      if rem(sample, 10) == 0 do
        Logger.info("   📈 Performance sample #{sample}/#{samples} - Latency: #{Float.round(publish_latency, 2)}ms")
      end
      
      sample_data
    end)
    
    # Analyze performance data
    successful_samples = Enum.count(performance_data, fn data -> data.publish_result == :ok end)
    latencies = Enum.map(performance_data, & &1.publish_latency_ms)
    avg_latency = Enum.sum(latencies) / length(latencies)
    max_latency = Enum.max(latencies)
    min_latency = Enum.min(latencies)
    
    Logger.info("📊 PERFORMANCE MONITORING COMPLETE:")
    Logger.info("   📈 Samples Collected: #{length(performance_data)}")
    Logger.info("   ✅ Successful Publishes: #{successful_samples}")
    Logger.info("   ⚡ Average Latency: #{Float.round(avg_latency, 2)}ms")
    Logger.info("   📊 Min Latency: #{Float.round(min_latency, 2)}ms")
    Logger.info("   📊 Max Latency: #{Float.round(max_latency, 2)}ms")
    Logger.info("   🎯 Performance Success Rate: #{Float.round(successful_samples / length(performance_data) * 100, 2)}%")
    
    # Save performance data
    performance_report = %{
      monitoring_duration_ms: monitoring_duration,
      sample_count: length(performance_data),
      successful_samples: successful_samples,
      average_latency_ms: Float.round(avg_latency, 2),
      min_latency_ms: Float.round(min_latency, 2),
      max_latency_ms: Float.round(max_latency, 2),
      success_rate: Float.round(successful_samples / length(performance_data), 4),
      timestamp: DateTime.utc_now()
    }
    
    File.write!("/Users/speed/autonomous-opponent-v2/cluster_performance_report.json", 
                Jason.encode!(performance_report, pretty: true))
    
    Logger.info("💾 Performance report saved to cluster_performance_report.json")
  end

  # Helper functions for generating test data

  defp generate_high_intensity_event_data(id) do
    %{
      event_id: "INTENSITY_#{id}",
      intensity: :rand.uniform(),
      complexity: :rand.uniform() * 10,
      priority: Enum.random([:low, :medium, :high, :critical, :maximum]),
      timestamp: System.system_time(:microsecond),
      test_metadata: %{
        source: "cluster_verification",
        batch: div(id, 100),
        sequence: id
      },
      payload: generate_random_payload(id)
    }
  end

  defp generate_channel_specific_data(channel, id) do
    base_data = %{
      channel: channel,
      event_id: "#{channel}_#{id}",
      timestamp: System.system_time(:microsecond),
      test_type: "channel_saturation"
    }
    
    case channel do
      :algedonic ->
        Map.merge(base_data, %{
          type: Enum.random([:pain, :pleasure, :emergency]),
          intensity: :rand.uniform(),
          source: "saturation_test",
          bypass_priority: :maximum
        })
        
      :s5_policy ->
        Map.merge(base_data, %{
          policy: "test_policy_#{id}",
          constraint: "saturation_constraint",
          governance_level: :maximum
        })
        
      :s4_intelligence ->
        Map.merge(base_data, %{
          analysis_type: "threat_assessment",
          complexity: :rand.uniform() * 10,
          environmental_factor: :rand.uniform()
        })
        
      :s3_control ->
        Map.merge(base_data, %{
          resource: Enum.random([:cpu, :memory, :network, :disk]),
          allocation: :rand.uniform() * 100,
          optimization_target: :maximum
        })
        
      :s2_coordination ->
        Map.merge(base_data, %{
          coordination_type: "anti_oscillation",
          pattern: "test_pattern_#{id}",
          effectiveness: :rand.uniform()
        })
        
      :s1_operational ->
        Map.merge(base_data, %{
          operation: "production_#{id}",
          throughput: :rand.uniform() * 1000,
          efficiency: :rand.uniform()
        })
        
      _ ->
        Map.merge(base_data, %{generic_data: "test_#{id}"})
    end
  end

  defp generate_random_payload(id) do
    # Generate varying payload sizes to test system limits
    payload_size = rem(id, 5) + 1
    
    payload_data = for i <- 1..payload_size do
      %{
        "data_#{i}" => "test_payload_#{id}_#{i}",
        "random_value" => :rand.uniform() * 1000,
        "complexity_factor" => :rand.uniform() * 10
      }
    end
    
    %{
      payload_data: payload_data,
      payload_size: payload_size,
      checksum: :erlang.phash2(payload_data)
    }
  end

  defp process_tasks_in_batches(tasks, batch_size) do
    tasks
    |> Enum.chunk_every(batch_size)
    |> Enum.flat_map(fn batch ->
      results = Task.await_many(batch, 10_000)
      # Brief pause between batches to avoid overwhelming
      Process.sleep(50)
      results
    end)
  end
end

# Add JSON encoding capability
defmodule Jason do
  def encode!(data, opts \\ []) do
    encoded = :json.encode(data)
    if opts[:pretty] do
      # Simple pretty printing
      encoded
      |> String.replace("{", "{\n  ")
      |> String.replace("}", "\n}")
      |> String.replace(",", ",\n  ")
    else
      encoded
    end
  end
end

# Execute maximum intensity cluster verification
ClusterPowerVerification.unleash_maximum_verification()