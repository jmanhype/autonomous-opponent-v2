# Run the population script
Code.eval_file("populate_system_interactive.exs")

# Wait for processing
Process.sleep(5000)

# Check endpoints
IO.puts("\n\n=== CHECKING ENDPOINTS AFTER POPULATION ===")

# Check patterns
case HTTPoison.get("http://localhost:4000/api/patterns") do
  {:ok, %{body: body}} -> 
    {:ok, json} = Jason.decode(body)
    IO.puts("Patterns found: #{length(json["patterns"])}")
  _ -> IO.puts("Failed to get patterns")
end

# Check trending topics
case HTTPoison.get("http://localhost:4000/api/events/analyze") do
  {:ok, %{body: body}} -> 
    {:ok, json} = Jason.decode(body)
    IO.puts("Trending topics: #{length(json["analysis"]["trending_topics"])}")
  _ -> IO.puts("Failed to get event analysis")
end
