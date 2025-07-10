# Check if ETS table already exists
IO.puts("Checking ETS tables...")

tables = :ets.all()
IO.puts("Total ETS tables: #{length(tables)}")

# Check for event_bus_subscriptions
case :ets.info(:event_bus_subscriptions) do
  :undefined -> 
    IO.puts("❌ event_bus_subscriptions table does NOT exist")
  info ->
    IO.puts("✅ event_bus_subscriptions exists with #{info[:size]} entries")
end

# Check for metrics table
case :ets.info(:metrics_store) do
  :undefined -> 
    IO.puts("❌ metrics_store table does NOT exist")
  info ->
    IO.puts("✅ metrics_store exists")
end

# Try to create a new event_bus_subscriptions table
try do
  :ets.new(:event_bus_subscriptions, [:named_table, :bag, :public])
  IO.puts("✅ Successfully created event_bus_subscriptions table")
catch
  :error, :badarg ->
    IO.puts("❌ Cannot create event_bus_subscriptions - already exists\!")
end
