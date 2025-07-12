#!/usr/bin/env elixir

# Paste this into IEx to test the VSM pattern publishing
defmodule BrutalVSMTest do
  @moduledoc """
  BRUTAL TRUTH TESTING for VSM Pattern Publishing
  This will tell us exactly what works and what's fucked
  """

  def test_everything() do
    IO.puts("\n🔥 BRUTAL VSM PATTERN PUBLISHING TEST 🔥")
    IO.puts("================================================")
    
    # Step 1: Start the core application
    IO.puts("\n1️⃣ STARTING APPLICATION CORE...")
    case Application.ensure_all_started(:autonomous_opponent_core) do
      {:ok, _} -> IO.puts("✅ Core app started")
      {:error, reason} -> 
        IO.puts("❌ Core app failed: #{inspect reason}")
        return :failed
    end
    
    # Step 2: Check EventBus
    IO.puts("\n2️⃣ CHECKING EVENTBUS...")
    case Process.whereis(AutonomousOpponentV2Core.EventBus) do
      nil -> 
        IO.puts("❌ EventBus not running")
        return :failed
      pid -> 
        IO.puts("✅ EventBus running: #{inspect pid}")
    end
    
    # Step 3: Check VSM subsystems
    IO.puts("\n3️⃣ CHECKING VSM SUBSYSTEMS...")
    vsm_modules = [
      {"S1 Operations", AutonomousOpponentV2Core.VSM.S1.Operations},
      {"S2 Coordination", AutonomousOpponentV2Core.VSM.S2.Coordination},
      {"S3 Control", AutonomousOpponentV2Core.VSM.S3.Control},
      {"S4 Intelligence", AutonomousOpponentV2Core.VSM.S4.Intelligence},
      {"S5 Policy", AutonomousOpponentV2Core.VSM.S5.Policy}
    ]
    
    running_vsm = Enum.filter(vsm_modules, fn {name, module} ->
      case Process.whereis(module) do
        nil -> 
          IO.puts("❌ #{name} NOT RUNNING")
          false
        pid -> 
          IO.puts("✅ #{name} running: #{inspect pid}")
          true
      end
    end)
    
    if length(running_vsm) == 0 do
      IO.puts("💀 NO VSM SUBSYSTEMS RUNNING - STARTING THEM")
      start_vsm_subsystems()
      :timer.sleep(2000)  # Give them time to start
      
      # Recheck
      running_vsm = Enum.filter(vsm_modules, fn {name, module} ->
        case Process.whereis(module) do
          nil -> false
          _pid -> true
        end
      end)
    end
    
    if length(running_vsm) == 0 do
      IO.puts("💀 STILL NO VSM SUBSYSTEMS - SYSTEM IS FUCKED")
      return :vsm_failed
    end
    
    # Step 4: Test EventBus subscription
    IO.puts("\n4️⃣ TESTING EVENTBUS SUBSCRIPTION...")
    test_subscription()
    
    # Step 5: Test pattern publishing
    IO.puts("\n5️⃣ TESTING PATTERN PUBLISHING...")
    test_pattern_publishing(running_vsm)
    
    # Step 6: Listen for actual pattern events
    IO.puts("\n6️⃣ LISTENING FOR PATTERN EVENTS...")
    listen_for_pattern_events()
    
    IO.puts("\n🏁 BRUTAL TEST COMPLETE")
  end
  
  defp start_vsm_subsystems() do
    IO.puts("🚀 Attempting to start VSM subsystems...")
    
    # Try to start VSM supervisor
    case AutonomousOpponentV2Core.VSM.Supervisor.start_link([]) do
      {:ok, pid} -> 
        IO.puts("✅ VSM Supervisor started: #{inspect pid}")
      {:error, {:already_started, pid}} -> 
        IO.puts("✅ VSM Supervisor already running: #{inspect pid}")
      {:error, reason} -> 
        IO.puts("❌ VSM Supervisor failed: #{inspect reason}")
        
        # Try starting individual subsystems
        IO.puts("🔧 Trying individual subsystem startup...")
        start_individual_subsystems()
    end
  end
  
  defp start_individual_subsystems() do
    subsystems = [
      {"S1", AutonomousOpponentV2Core.VSM.S1.Operations},
      {"S2", AutonomousOpponentV2Core.VSM.S2.Coordination},
      {"S3", AutonomousOpponentV2Core.VSM.S3.Control},
      {"S4", AutonomousOpponentV2Core.VSM.S4.Intelligence},
      {"S5", AutonomousOpponentV2Core.VSM.S5.Policy}
    ]
    
    Enum.each(subsystems, fn {name, module} ->
      case module.start_link([]) do
        {:ok, pid} -> IO.puts("✅ Started #{name}: #{inspect pid}")
        {:error, {:already_started, pid}} -> IO.puts("✅ #{name} already running: #{inspect pid}")
        {:error, reason} -> IO.puts("❌ Failed to start #{name}: #{inspect reason}")
      end
    end)
  end
  
  defp test_subscription() do
    # Subscribe to pattern topics
    pattern_topics = [
      :vsm_s1_patterns,
      :vsm_s2_patterns,
      :vsm_s3_patterns,
      :vsm_s4_patterns,
      :vsm_s5_patterns,
      :vsm_pattern_flow
    ]
    
    Enum.each(pattern_topics, fn topic ->
      case AutonomousOpponentV2Core.EventBus.subscribe(topic) do
        :ok -> IO.puts("✅ Subscribed to #{topic}")
        error -> IO.puts("❌ Failed to subscribe to #{topic}: #{inspect error}")
      end
    end)
  end
  
  defp test_pattern_publishing(running_vsm) do
    IO.puts("🧪 Testing pattern publishing functions...")
    
    Enum.each(running_vsm, fn {name, module} ->
      IO.puts("Testing #{name}...")
      
      try do
        # Get the current state
        state = GenServer.call(module, :get_state)
        IO.puts("✅ Got state from #{name}")
        
        # Try to call the pattern publishing function directly
        case module do
          AutonomousOpponentV2Core.VSM.S1.Operations ->
            # S1 doesn't expose publish_pattern_events publicly, try triggering health report
            GenServer.cast(module, :trigger_health_report)
            IO.puts("✅ Triggered health report for #{name}")
            
          AutonomousOpponentV2Core.VSM.S2.Coordination ->
            GenServer.cast(module, :trigger_health_report)
            IO.puts("✅ Triggered health report for #{name}")
            
          AutonomousOpponentV2Core.VSM.S3.Control ->
            GenServer.cast(module, :trigger_health_report)
            IO.puts("✅ Triggered health report for #{name}")
            
          AutonomousOpponentV2Core.VSM.S4.Intelligence ->
            GenServer.cast(module, :trigger_health_report)
            IO.puts("✅ Triggered health report for #{name}")
            
          AutonomousOpponentV2Core.VSM.S5.Policy ->
            GenServer.cast(module, :trigger_health_report)
            IO.puts("✅ Triggered health report for #{name}")
        end
        
      rescue
        error ->
          IO.puts("❌ Error testing #{name}: #{inspect error}")
      end
    end)
  end
  
  defp listen_for_pattern_events() do
    IO.puts("👂 Listening for pattern events (10 seconds)...")
    pattern_count = listen_loop(0, System.monotonic_time(:millisecond))
    
    case pattern_count do
      0 -> 
        IO.puts("💀 NO PATTERN EVENTS RECEIVED")
        IO.puts("   This means:")
        IO.puts("   - Pattern publishing functions aren't being called")
        IO.puts("   - EventBus routing is broken")  
        IO.puts("   - Health reporting cycles aren't triggering")
        
      count ->
        IO.puts("🎯 SUCCESS! Received #{count} pattern events")
        IO.puts("   Pattern publishing is WORKING! 🎉")
    end
  end
  
  defp listen_loop(count, start_time) do
    current_time = System.monotonic_time(:millisecond)
    elapsed = current_time - start_time
    
    if elapsed >= 10_000 do
      count
    else
      receive do
        {:event, topic, data} ->
          IO.puts("🎯 Pattern event ##{count + 1}!")
          IO.puts("   Topic: #{topic}")
          
          # Show key data fields
          if is_map(data) do
            keys = Map.keys(data) |> Enum.take(5)
            IO.puts("   Data keys: #{inspect keys}")
            
            if Map.has_key?(data, :subsystem) do
              IO.puts("   From: #{data.subsystem}")
            end
          end
          
          listen_loop(count + 1, start_time)
          
      after
        100 ->
          listen_loop(count, start_time)
      end
    end
  end
end

# Run the test
BrutalVSMTest.test_everything()