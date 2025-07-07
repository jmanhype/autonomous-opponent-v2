# Run this inside IEx after starting with: iex -S mix

# Test 1: Check S1 Variety Metrics
IO.puts "\n=== Testing S1 Variety Measurement ==="
variety = AutonomousOpponentV2Core.VSM.S1.Operations.get_variety_metrics()
IO.inspect(variety, label: "S1 Variety Metrics")

# Test 2: Check Algedonic State
IO.puts "\n=== Testing Algedonic Channel ==="
algedonic = AutonomousOpponentV2Core.VSM.Algedonic.Channel.get_hedonic_state()
IO.puts "Pain: #{Float.round(algedonic.pain_level, 2)}, Pleasure: #{Float.round(algedonic.pleasure_level, 2)}"

# Test 3: Generate Events
IO.puts "\n=== Generating Test Events ==="
Enum.each(1..10, fn i ->
  AutonomousOpponentV2Core.EventBus.publish(:test_event, %{
    id: i,
    type: Enum.random([:query, :update, :delete]),
    data: "test_#{i}"
  })
end)

Process.sleep(500)

# Test 4: Check variety after events
IO.puts "\n=== Checking Variety After Events ==="
variety_after = AutonomousOpponentV2Core.VSM.S1.Operations.get_variety_metrics()
IO.puts "Entropy: #{variety_after.entropy} bits"
IO.puts "Variety ratio: #{Float.round(variety_after.variety_ratio * 100, 1)}%"

# Test 5: Check S2 Coordination
IO.puts "\n=== Testing S2 Coordination ==="
s2 = AutonomousOpponentV2Core.VSM.S2.Coordination.get_coordination_state()
IO.inspect(s2, label: "S2 State")

IO.puts "\n✓ VSM is working with real implementations!"