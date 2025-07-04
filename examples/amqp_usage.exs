# AMQP Usage Examples for Autonomous Opponent V2
# 
# This file demonstrates how to use the AMQP infrastructure
# for VSM communication patterns.

alias AutonomousOpponentV2Core.AMCP.{Client, HealthMonitor}
alias AutonomousOpponentV2Core.EventBus

# First, check if AMQP is healthy
IO.puts("Checking AMQP health...")
health = HealthMonitor.get_status()
IO.inspect(health, label: "AMQP Health")

# Example 1: Publishing to VSM Subsystems
# ----------------------------------------

# Publish an operational task to S1
IO.puts("\n1. Publishing to S1 (Operations)...")
result = Client.publish_to_subsystem(:s1, %{
  operation: "process_order",
  order_id: "ORD-#{:rand.uniform(9999)}",
  items: [
    %{sku: "PROD-001", quantity: 2},
    %{sku: "PROD-002", quantity: 1}
  ],
  timestamp: DateTime.utc_now()
})
IO.puts("Result: #{inspect(result)}")

# Publish a control command to S3 with priority
IO.puts("\n2. Publishing priority control to S3...")
result = Client.publish_to_subsystem(:s3, %{
  command: "adjust_threshold",
  parameter: "cpu_limit",
  new_value: 85,
  reason: "peak_hours"
}, priority: 8)
IO.puts("Result: #{inspect(result)}")

# Example 2: Algedonic Signals
# ----------------------------

# Send a pain signal when something goes wrong
IO.puts("\n3. Sending pain signal...")
result = Client.send_algedonic(:pain, %{
  source: "resource_monitor",
  severity: "warning",
  message: "Memory usage approaching limit",
  current_value: 78.5,
  threshold: 80.0,
  node: node()
})
IO.puts("Result: #{inspect(result)}")

# Send a pleasure signal for positive feedback
IO.puts("\n4. Sending pleasure signal...")
result = Client.send_algedonic(:pleasure, %{
  source: "goal_tracker",
  achievement: "daily_target_met",
  metric: "processed_orders",
  actual: 1250,
  target: 1000
})
IO.puts("Result: #{inspect(result)}")

# Example 3: Event Broadcasting
# -----------------------------

IO.puts("\n5. Broadcasting system event...")
result = Client.publish_event(:configuration_changed, %{
  component: "rate_limiter",
  changes: %{
    requests_per_minute: %{old: 100, new: 150},
    burst_size: %{old: 20, new: 30}
  },
  changed_by: "admin",
  reason: "increased_capacity"
})
IO.puts("Result: #{inspect(result)}")

# Example 4: Work Queue Pattern
# -----------------------------

IO.puts("\n6. Creating and using work queue...")

# Create a work queue
queue_result = Client.create_work_queue("data_import", 
  ttl: 600_000,      # 10 minutes to process
  max_length: 500    # Max 500 pending jobs
)
IO.puts("Queue creation: #{inspect(queue_result)}")

# Send work items
for i <- 1..5 do
  work_result = Client.send_work("data_import", %{
    job_id: "JOB-#{i}",
    file_path: "/imports/batch_#{i}.csv",
    operations: ["validate", "normalize", "insert"],
    priority: rem(i, 3)  # Vary priority
  }, priority: rem(i, 3))
  
  IO.puts("Work item #{i}: #{inspect(work_result)}")
end

# Example 5: Subscribing to Subsystems
# ------------------------------------

IO.puts("\n7. Setting up S4 Intelligence subscriber...")

# Start a subscriber for S4 (Intelligence)
{:ok, task} = Client.subscribe_to_subsystem(:s4, fn message, meta ->
  IO.puts("S4 received: #{inspect(message)}")
  IO.puts("Metadata: #{inspect(meta)}")
  
  # Process the message
  case message["task"] do
    "analyze_pattern" ->
      IO.puts("Running pattern analysis...")
      :ok
      
    "generate_report" ->
      IO.puts("Generating report...")
      :ok
      
    _ ->
      IO.puts("Unknown task type")
      {:error, :unknown_task}
  end
end)

# Let it run for a moment
Process.sleep(1000)

# Clean up the subscriber
Process.exit(task, :normal)

# Example 6: Health Monitoring Integration
# ----------------------------------------

IO.puts("\n8. Integrating with EventBus for health monitoring...")

# Subscribe to health check events
EventBus.subscribe(:amqp_health_check)

# Force a health check
check_result = HealthMonitor.force_check()
IO.puts("Forced check result: #{inspect(check_result)}")

# Wait for the event
receive do
  {:event_bus, :amqp_health_check, payload} ->
    IO.puts("Received health event via EventBus:")
    IO.inspect(payload, pretty: true)
after
  2000 ->
    IO.puts("No health event received")
end

EventBus.unsubscribe(:amqp_health_check)

# Example 7: Error Handling
# -------------------------

IO.puts("\n9. Demonstrating error handling...")

# Try to publish with invalid subsystem
try do
  Client.publish_to_subsystem(:s6, %{data: "test"})
rescue
  e in FunctionClauseError ->
    IO.puts("Caught expected error: Invalid subsystem")
end

# Handle connection failures gracefully
case Client.publish_to_subsystem(:s1, %{large_data: String.duplicate("x", 10_000)}) do
  :ok ->
    IO.puts("Large message published successfully")
    
  {:error, :max_retries_exceeded} ->
    IO.puts("Failed after retries - falling back to EventBus")
    EventBus.publish(:s1_fallback, %{note: "Published via EventBus due to AMQP failure"})
    
  {:error, reason} ->
    IO.puts("Unexpected error: #{inspect(reason)}")
end

# Example 8: Performance Monitoring
# ---------------------------------

IO.puts("\n10. Checking connection pool performance...")

# Get pool health
pool_health = Client.health_check()
IO.inspect(pool_health, label: "Connection Pool Status")

# Measure publish latency
start_time = System.monotonic_time(:microsecond)

results = for i <- 1..10 do
  Client.publish_to_subsystem(:s1, %{
    test_id: i,
    timestamp: System.monotonic_time()
  })
end

end_time = System.monotonic_time(:microsecond)
elapsed_ms = (end_time - start_time) / 1000

IO.puts("\nPublished 10 messages in #{elapsed_ms}ms")
IO.puts("Average: #{elapsed_ms / 10}ms per message")
IO.puts("Success rate: #{Enum.count(results, & &1 == :ok)}/10")

IO.puts("\n✅ AMQP examples completed!")
IO.puts("\nKey takeaways:")
IO.puts("- Always check health before critical operations")
IO.puts("- Use appropriate priorities for time-sensitive messages")
IO.puts("- Fall back to EventBus when AMQP is unavailable")
IO.puts("- Monitor performance and set alerts for production")