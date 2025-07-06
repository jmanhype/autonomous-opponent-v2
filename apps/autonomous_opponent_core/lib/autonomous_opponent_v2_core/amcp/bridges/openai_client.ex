defmodule AutonomousOpponentV2Core.AMCP.Bridges.OpenAIClient do
  @moduledoc """
  OpenAI API client for the LLM Bridge.
  
  Provides a clean interface to OpenAI's chat completion API
  with proper error handling, configuration, and connection pooling.
  """
  
  require Logger
  
  alias AutonomousOpponentV2Core.Connections.PoolManager
  
  @openai_base_url "https://api.openai.com/v1"
  
  @doc """
  Sends a chat completion request to OpenAI API.
  """
  def completion(params) do
    api_key = get_api_key()
    
    unless api_key do
      {:error, :no_api_key}
    else
      headers = [
        {"content-type", "application/json"},
        {"authorization", "Bearer #{api_key}"}
      ]
      
      body = Jason.encode!(params)
      
      # Build Finch request
      request = Finch.build(:post, "#{@openai_base_url}/chat/completions", headers, body)
      
      # Use connection pool
      case PoolManager.request(:openai, request, timeout: 30_000) do
        # Handle double-nested response from CircuitBreaker + PoolManager
        {:ok, {:ok, %{status: 200, body: response_body}}} ->
          Jason.decode(response_body)
          
        {:ok, %{status: 200, body: response_body}} ->
          Jason.decode(response_body)
          
        # Handle double-nested error responses
        {:ok, {:ok, %{status: status, body: body}}} ->
          Logger.error("OpenAI API error: Status #{status}, Body: #{body}")
          
          # Try to parse error message
          case Jason.decode(body) do
            {:ok, %{"error" => error}} ->
              {:error, {:api_error, status}}
            _ ->
              {:error, {:api_error, status}}
          end
          
        {:ok, %{status: status, body: body}} ->
          Logger.error("OpenAI API error: Status #{status}, Body: #{body}")
          
          # Try to parse error message
          case Jason.decode(body) do
            {:ok, %{"error" => error}} ->
              {:error, {:api_error, status}}
            _ ->
              {:error, {:api_error, status}}
          end
          
        {:error, :circuit_open} ->
          Logger.error("OpenAI circuit breaker is open")
          {:error, :service_unavailable}
          
        {:error, reason} ->
          Logger.error("HTTP request failed: #{inspect(reason)}")
          {:error, {:http_error, reason}}
      end
    end
  end
  
  @doc """
  Sends a streaming chat completion request to OpenAI API.
  Returns a stream of Server-Sent Events.
  """
  def stream_completion(params, callback) do
    api_key = get_api_key()
    
    unless api_key do
      {:error, :no_api_key}
    else
      headers = [
        {"content-type", "application/json"},
        {"authorization", "Bearer #{api_key}"},
        {"accept", "text/event-stream"}
      ]
      
      # Enable streaming
      params = Map.put(params, :stream, true)
      body = Jason.encode!(params)
      
      # Build Finch request
      request = Finch.build(:post, "#{@openai_base_url}/chat/completions", headers, body)
      
      # Use connection pool with streaming
      case PoolManager.stream(:openai, request, "", &handle_stream_chunk(&1, &2, callback)) do
        {:ok, _result} ->
          callback.({:done, nil})
          :ok
          
        {:error, :circuit_open} ->
          Logger.error("OpenAI circuit breaker is open")
          {:error, :service_unavailable}
          
        {:error, reason} ->
          Logger.error("Failed to start stream: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end
  
  # Private functions
  
  defp get_api_key do
    System.get_env("OPENAI_API_KEY") || 
    Application.get_env(:autonomous_opponent_core, :openai_api_key)
  end
  
  defp handle_stream_chunk({:status, status}, buffer, _callback) when status != 200 do
    Logger.error("Stream error: HTTP #{status}")
    {:halt, {:error, {:http_status, status}}}
  end
  
  defp handle_stream_chunk({:headers, _headers}, buffer, _callback) do
    {:cont, buffer}
  end
  
  defp handle_stream_chunk({:data, chunk}, buffer, callback) do
    # Process SSE data
    {events, new_buffer} = parse_sse_chunk(buffer <> chunk)
    
    Enum.each(events, fn event ->
      handle_sse_event(event, callback)
    end)
    
    {:cont, new_buffer}
  end
  
  defp handle_stream_chunk(:done, _buffer, _callback) do
    {:cont, :ok}
  end
  
  defp handle_stream(id, callback, buffer) do
    receive do
      %HTTPoison.AsyncStatus{id: ^id, code: status} when status != 200 ->
        Logger.error("Stream error: HTTP #{status}")
        {:error, {:http_status, status}}
        
      %HTTPoison.AsyncHeaders{id: ^id} ->
        # Continue receiving (for backward compatibility if needed)
        handle_stream(id, callback, buffer)
        
      %HTTPoison.AsyncChunk{id: ^id, chunk: chunk} ->
        # Process SSE data
        {events, new_buffer} = parse_sse_chunk(buffer <> chunk)
        
        Enum.each(events, fn event ->
          handle_sse_event(event, callback)
        end)
        
        # Continue receiving
        handle_stream(id, callback, new_buffer)
        
      %HTTPoison.AsyncEnd{id: ^id} ->
        # Stream complete
        callback.({:done, nil})
        :ok
        
      {:error, reason} ->
        Logger.error("Stream error: #{inspect(reason)}")
        {:error, reason}
        
    after
      60_000 ->
        Logger.error("Stream timeout")
        {:error, :timeout}
    end
  end
  
  defp parse_sse_chunk(data) do
    lines = String.split(data, "\n")
    
    {complete_events, remaining} = 
      Enum.reduce(lines, {[], ""}, fn line, {events, buffer} ->
        cond do
          line == "" and buffer != "" ->
            # End of event
            {events ++ [buffer], ""}
            
          String.starts_with?(line, "data: ") ->
            # Event data
            data = String.trim_leading(line, "data: ")
            {events, buffer <> data}
            
          true ->
            # Continue building
            {events, buffer}
        end
      end)
      
    {complete_events, remaining}
  end
  
  defp handle_sse_event("[DONE]", callback) do
    callback.({:done, nil})
  end
  
  defp handle_sse_event(event_data, callback) do
    case Jason.decode(event_data) do
      {:ok, data} ->
        # Extract delta content
        delta = get_in(data, ["choices", Access.at(0), "delta", "content"])
        if delta do
          callback.({:chunk, delta})
        end
        
      {:error, _} ->
        # Ignore malformed events
        :ok
    end
  end
end