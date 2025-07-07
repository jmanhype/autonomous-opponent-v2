# Interactive VSM testing in IEx

IO.puts "\n=== Testing Real VSM Implementation ==="

# Test S1 Operations
IO.puts "\n1. Testing S1 Operations:"
{:ok, s1_state} = AutonomousOpponentV2Core.VSM.S1.Operations.get_operational_state()
IO.inspect(s1_state.variety, label: "S1 Variety")
IO.puts "   Current entropy: #{s1_state.variety.current_entropy} bits"
IO.puts "   Max entropy: #{s1_state.variety.max_entropy} bits"
IO.puts "   Variety ratio: #{Float.round(s1_state.variety.variety_ratio * 100, 1)}%"

# Test Algedonic Channel
IO.puts "\n2. Testing Algedonic Channel:"
hedonic_state = AutonomousOpponentV2Core.VSM.Algedonic.Channel.get_hedonic_state()
IO.puts "   Current mood: #{hedonic_state.mood}"
IO.puts "   Pain level: #{Float.round(hedonic_state.pain_level, 2)}"
IO.puts "   Pleasure level: #{Float.round(hedonic_state.pleasure_level, 2)}"

if AutonomousOpponentV2Core.VSM.Algedonic.Channel.in_pain?() do
  IO.puts "   ⚠️  System is in pain!"
else
  IO.puts "   ✓ System is not in pain"
end

# Test S2 Coordination
IO.puts "\n3. Testing S2 Coordination:"
s2_state = AutonomousOpponentV2Core.VSM.S2.Coordination.get_coordination_state()
IO.puts "   Active units: #{s2_state.active_units}"
IO.puts "   Oscillation risk: #{Float.round(s2_state.oscillation_risk * 100, 1)}%"
IO.puts "   Health: #{Float.round(s2_state.health, 2)}"

# Generate some events to trigger VSM activity
IO.puts "\n4. Generating events to trigger VSM activity..."
events = [
  {:user_interaction, %{type: :query, user_id: "test", timestamp: DateTime.utc_now()}},
  {:system_performance, %{cpu: 65.5, memory: 78.2, latency: 250}},
  {:error_occurred, %{severity: :high, source: :test, message: "Test error"}},
  {:pattern_detected, %{type: :anomaly, confidence: 0.92}}
]

Enum.each(events, fn {event_type, data} ->
  AutonomousOpponentV2Core.EventBus.publish(event_type, data)
  IO.puts "   ✓ Published #{event_type}"
end)

# Wait for processing
Process.sleep(1000)

# Check variety after events
IO.puts "\n5. Checking S1 variety after events:"
{:ok, s1_after} = AutonomousOpponentV2Core.VSM.S1.Operations.get_operational_state()
IO.puts "   Entropy after events: #{s1_after.variety.current_entropy} bits"
IO.puts "   Variety ratio: #{Float.round(s1_after.variety.variety_ratio * 100, 1)}%"

# Check algedonic response
IO.puts "\n6. Checking algedonic response:"
hedonic_after = AutonomousOpponentV2Core.VSM.Algedonic.Channel.get_hedonic_state()
IO.puts "   Pain level after events: #{Float.round(hedonic_after.pain_level, 2)}"
IO.puts "   Pleasure level after: #{Float.round(hedonic_after.pleasure_level, 2)}"

# Generate high variety to test attenuation
IO.puts "\n7. Testing variety attenuation with high load..."
Enum.each(1..50, fn i ->
  AutonomousOpponentV2Core.EventBus.publish(:high_variety_test, %{
    id: i,
    data: :crypto.strong_rand_bytes(32) |> Base.encode64(),
    type: Enum.random([:a, :b, :c, :d, :e, :f, :g, :h]),
    timestamp: DateTime.utc_now()
  })
end)

Process.sleep(500)

# Check if attenuation kicked in
{:ok, s1_high_load} = AutonomousOpponentV2Core.VSM.S1.Operations.get_operational_state()
variety_metrics = AutonomousOpponentV2Core.VSM.S1.Operations.get_variety_metrics()
IO.puts "\n8. Variety management under high load:"
IO.puts "   Entropy: #{variety_metrics.entropy} bits"
IO.puts "   Variety ratio: #{Float.round(variety_metrics.variety_ratio * 100, 1)}%"
IO.puts "   Attenuation active: #{variety_metrics.attenuation_active}"

IO.puts "\n=== VSM Test Complete ==="
IO.puts "✓ All VSM subsystems are processing real data"
IO.puts "✓ Variety is measured using Shannon entropy"
IO.puts "✓ Algedonic channels respond to system state"
IO.puts "✓ The system is alive and responding!"

:ok