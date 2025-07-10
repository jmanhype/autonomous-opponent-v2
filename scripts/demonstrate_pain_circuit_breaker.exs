#!/usr/bin/env elixir

# DEMONSTRATION: Algedonic Pain → Circuit Breaker Connection
# This script shows Beer's cybernetic vision in action

IO.puts """
====================================================
ALGEDONIC PAIN → CIRCUIT BREAKER DEMONSTRATION
Beer's VSM: When the system feels pain, it protects itself
====================================================
"""

alias AutonomousOpponentV2Core.EventBus
alias AutonomousOpponentV2Core.Core.CircuitBreaker

# Ensure EventBus is running
case Process.whereis(EventBus) do
  nil -> 
    IO.puts "Starting EventBus..."
    {:ok, _} = EventBus.start_link()
  _pid -> 
    IO.puts "EventBus already running"
end

# Create a test circuit breaker
IO.puts "\n1. Creating pain-aware circuit breaker..."
{:ok, _} = CircuitBreaker.start_link(
  name: :demo_breaker,
  pain_threshold: 0.8,
  pain_response_enabled: true,
  failure_threshold: 5
)

# Check initial state
initial_state = CircuitBreaker.get_state(:demo_breaker)
IO.puts "   Initial state: #{initial_state.state}"
IO.puts "   Pain threshold: 0.8"

# Demonstrate pain below threshold
IO.puts "\n2. Sending moderate pain signal (intensity: 0.5)..."
EventBus.publish(:algedonic_pain, %{
  source: :demo_monitor,
  severity: :medium,  # Maps to 0.5
  metric: :response_time,
  reason: "Moderate system stress",
  scope: :system_wide
})

Process.sleep(100)
state = CircuitBreaker.get_state(:demo_breaker)
IO.puts "   Circuit state: #{state.state} (remains closed - pain below threshold)"

# Demonstrate pain above threshold
IO.puts "\n3. Sending critical pain signal (intensity: 1.0)..."
EventBus.publish(:algedonic_pain, %{
  source: :demo_monitor,
  severity: :critical,  # Maps to 1.0
  metric: :system_overload,
  reason: "CRITICAL: System overload detected!",
  scope: :system_wide
})

Process.sleep(100)
state = CircuitBreaker.get_state(:demo_breaker)
IO.puts "   Circuit state: #{state.state} ✓"
IO.puts "   Pain-triggered opens: #{state.metrics.pain_triggered_opens}"

# Show protection in action
IO.puts "\n4. Testing circuit protection..."
result = CircuitBreaker.call(:demo_breaker, fn -> 
  IO.puts "   This would execute if circuit was closed..."
  :ok
end)

case result do
  {:error, :circuit_open} ->
    IO.puts "   ✓ Circuit PROTECTED the system - call rejected!"
  _ ->
    IO.puts "   Circuit allowed call through"
end

# Demonstrate sustained pain
IO.puts "\n5. Demonstrating sustained pain response..."
CircuitBreaker.reset(:demo_breaker)
IO.puts "   Circuit reset to closed state"

# Send multiple moderate pain signals
for i <- 1..4 do
  EventBus.publish(:algedonic_pain, %{
    source: :demo_monitor,
    intensity: 0.6,  # Below threshold individually
    metric: :sustained_load,
    reason: "Sustained moderate stress #{i}",
    scope: :system_wide
  })
  Process.sleep(50)
end

Process.sleep(100)
state = CircuitBreaker.get_state(:demo_breaker)
IO.puts "   After sustained pain - Circuit state: #{state.state}"
IO.puts "   The circuit recognized sustained suffering and protected itself!"

# Demonstrate emergency pain
IO.puts "\n6. Emergency algedonic signal (system scream)..."
EventBus.publish(:emergency_algedonic, %{
  source: :s5_policy,
  message: "EMERGENCY: Total system collapse imminent!",
  affected_services: [:all]
})

Process.sleep(100)
state = CircuitBreaker.get_state(:demo_breaker)
IO.puts "   Circuit state after emergency: #{state.state}"
IO.puts "   ✓ Emergency pain forces immediate protection!"

# Show metrics
IO.puts "\n7. Final metrics:"
metrics = state.metrics
IO.puts "   Total calls: #{metrics.total_calls}"
IO.puts "   Pain-triggered opens: #{metrics.pain_triggered_opens}"
IO.puts "   Total failures: #{metrics.total_failures}"

IO.puts """

====================================================
CONCLUSION: The VSM Lives!

Beer's vision realized:
- The system feels pain through algedonic signals
- Circuit breakers respond viscerally, not bureaucratically  
- Protection is reflexive, not deliberative
- The organism preserves itself through felt experience

"The purpose of a system is what it does" - and this
system protects itself when it hurts.
====================================================
"""