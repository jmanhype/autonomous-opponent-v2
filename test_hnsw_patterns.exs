# Test script to insert patterns into HNSW for persistence testing

# Get the HNSW index process
hnsw_name = :s4_vector_store_hnsw

# Insert test patterns
IO.puts("Inserting test patterns into HNSW index...")

for i <- 1..10 do
  # Generate a random vector
  vector = for _ <- 1..64, do: :rand.uniform()
  
  metadata = %{
    id: "test_pattern_#{i}",
    type: :test,
    confidence: 0.8 + :rand.uniform() * 0.2,
    inserted_at: DateTime.utc_now(),
    source: :persistence_test
  }
  
  case GenServer.whereis(hnsw_name) do
    nil ->
      IO.puts("HNSW index not found at #{inspect(hnsw_name)}")
    pid ->
      result = AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex.insert(pid, vector, metadata)
      IO.puts("Pattern #{i} inserted: #{inspect(result)}")
  end
  
  Process.sleep(100)
end

IO.puts("Test patterns inserted. Waiting for persistence...")

# Manually trigger persistence
case GenServer.whereis(hnsw_name) do
  nil ->
    IO.puts("Cannot trigger persistence - HNSW not found")
  pid ->
    IO.puts("Manually triggering persistence...")
    result = AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex.persist(pid)
    IO.puts("Manual persistence result: #{inspect(result)}")
end