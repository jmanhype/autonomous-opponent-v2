#!/usr/bin/env elixir

# Demo script showing VSM Pattern Library in action
#
# Prerequisites:
# 1. Ensure RabbitMQ is running (or set AMQP_ENABLED=false)
# 2. Run: mix compile
# 3. Execute: mix run demo_vsm_patterns.exs

IO.puts("\n=== VSM PATTERN LIBRARY DEMO ===\n")

# Load the application with error handling
case Application.ensure_all_started(:autonomous_opponent_core) do
  {:ok, _} -> 
    IO.puts("✓ Application started successfully")
  {:error, reason} -> 
    IO.puts("✗ Failed to start: #{inspect(reason)}")
    System.halt(1)
end

# Give the system time to initialize
Process.sleep(1000)

alias AutonomousOpponentV2Core.AMCP.Goldrush.{VSMPatternLibrary, PatternRegistry, VSMPatternExamples}
alias AutonomousOpponentV2Core.EventBus

IO.puts("1. VSM Pattern Library Statistics:")
IO.puts("==================================")

all_patterns = VSMPatternLibrary.all_patterns()

Enum.each(all_patterns, fn {domain, patterns} ->
  count = map_size(patterns)
  IO.puts("   #{String.capitalize(to_string(domain))} domain: #{count} patterns")
end)

IO.puts("\n2. Critical VSM Patterns:")
IO.puts("=========================")

critical = VSMPatternLibrary.patterns_by_severity(:critical)
Enum.each(critical, fn {name, pattern} ->
  IO.puts("   - #{name}: #{pattern.description}")
  IO.puts("     Pain level: #{pattern.algedonic_response.pain_level}")
end)

IO.puts("\n3. Running Pattern Simulations:")
IO.puts("================================")

# Subscribe to events
EventBus.subscribe(:vsm_events)
EventBus.subscribe(:algedonic_signals)
EventBus.subscribe(:pattern_matches)

# Monitor in background with statistics tracking
event_count = :counters.new(1, [])
pattern_match_count = :counters.new(1, [])
algedonic_count = :counters.new(1, [])
start_time = System.monotonic_time(:millisecond)

monitor_task = Task.async(fn ->
  IO.puts("   [Monitor] Starting event monitoring...")
  
  Enum.each(1..30, fn _ ->
    receive do
      {:event_bus, %{type: :algedonic_signal} = signal} ->
        severity = case signal.intensity do
          i when i >= 0.8 -> "CRITICAL"
          i when i >= 0.6 -> "HIGH"
          _ -> "MEDIUM"
        end
        IO.puts("   🚨 #{severity} ALGEDONIC: #{signal.source} - Pain: #{signal.intensity}")
        :counters.add(algedonic_count, 1, 1)
        
      {:event_bus, %{type: :pattern_match} = match} ->
        IO.puts("   ✓ PATTERN DETECTED: #{match.pattern_name}")
        :counters.add(pattern_match_count, 1, 1)
        
      {:event_bus, _event} ->
        # Count but don't display all events
        :counters.add(event_count, 1, 1)
    after
      100 -> :ok
    end
  end)
end)

# Run simulations
IO.puts("\n   Running variety overflow simulation...")
VSMPatternExamples.simulate_variety_overflow()

Process.sleep(2000)

IO.puts("\n   Running control oscillation simulation...")
VSMPatternExamples.simulate_control_oscillation()

Process.sleep(2000)

IO.puts("\n   Running circuit breaker pain loop simulation...")
VSMPatternExamples.simulate_circuit_breaker_pain_loop()

# Wait for monitor to finish
Task.await(monitor_task, 5000)

IO.puts("\n4. Pattern Registry Status:")
IO.puts("===========================")

active = PatternRegistry.active_patterns()
IO.puts("   Active patterns: #{length(active)}")

Enum.each(active, fn pattern_info ->
  stats = pattern_info.stats
  IO.puts("   - #{pattern_info.name}")
  IO.puts("     Matches: #{stats[:matches] || 0}")
  IO.puts("     No matches: #{stats[:no_matches] || 0}")
end)

IO.puts("\n5. Early Warning System:")
IO.puts("========================")

warnings = VSMPatternLibrary.early_warning_patterns()
|> Enum.take(5)

Enum.each(warnings, fn {pattern, threshold} ->
  IO.puts("   #{pattern}: #{threshold}")
end)

IO.puts("\n6. Demo Statistics:")
IO.puts("===================")
end_time = System.monotonic_time(:millisecond)
total_events = :counters.get(event_count, 1)
total_patterns = :counters.get(pattern_match_count, 1)
total_algedonic = :counters.get(algedonic_count, 1)
avg_time = if total_patterns > 0, do: div(end_time - start_time, total_patterns), else: 0

IO.puts("   Total events processed: #{total_events}")
IO.puts("   Patterns triggered: #{total_patterns}")
IO.puts("   Algedonic signals sent: #{total_algedonic}")
IO.puts("   Average detection time: #{avg_time}ms")

IO.puts("\n=== DEMO COMPLETE ===\n")
IO.puts("The VSM Pattern Library provides #{map_size(critical)} critical patterns")
IO.puts("for detecting system failures before they cascade.\n")
IO.puts("These patterns follow Stafford Beer's cybernetic principles")
IO.puts("and integrate with the algedonic (pain/pleasure) signaling system.\n")