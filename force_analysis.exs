# Force semantic analysis
IO.puts("Forcing semantic analysis...")

# Send messages to trigger analysis
{:ok, pid} = GenServer.start_link(fn -> 
  Process.register(self(), :test_client)
  
  # Send perform_batch_analysis to SemanticAnalyzer if it exists
  case Process.whereis(AutonomousOpponentV2Core.AMCP.Events.SemanticAnalyzer) do
    nil -> 
      IO.puts("SemanticAnalyzer not found")
    pid -> 
      send(pid, :perform_batch_analysis)
      IO.puts("Sent perform_batch_analysis to #{inspect(pid)}")
  end
  
  # Check the endpoints after a delay
  Process.sleep(5000)
  
  case HTTPoison.get("http://localhost:4000/api/patterns") do
    {:ok, %{body: body}} ->
      case Jason.decode(body) do
        {:ok, %{"patterns" => patterns}} ->
          IO.puts("Patterns found: #{length(patterns)}")
        _ -> IO.puts("Failed to decode patterns")
      end
    _ -> IO.puts("Failed to get patterns")
  end
  
  {:ok, nil}
end, [])

Process.sleep(6000)
