defmodule AutonomousOpponentV2Core.AMCP.Bridges.OpenAIClient do
  @moduledoc """
  OpenAI API client for the LLM Bridge.
  
  Provides a clean interface to OpenAI's chat completion API
  with proper error handling and configuration.
  """
  
  require Logger
  
  @openai_base_url "https://api.openai.com/v1"
  
  @doc """
  Sends a chat completion request to OpenAI API.
  """
  def completion(params) do
    api_key = get_api_key()
    
    unless api_key do
      return {:error, :no_api_key}
    end
    
    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{api_key}"}
    ]
    
    body = Jason.encode!(params)
    
    options = [
      timeout: 30_000,
      recv_timeout: 30_000
    ]
    
    case HTTPoison.post("#{@openai_base_url}/chat/completions", body, headers, options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        Jason.decode(response_body)
        
      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        Logger.error("OpenAI API error: Status #{status}, Body: #{body}")
        
        # Try to parse error message
        case Jason.decode(body) do
          {:ok, %{"error" => error}} ->
            {:error, {:api_error, error["message"] || "Unknown error"}}
          _ ->
            {:error, {:api_error, status}}
        end
        
      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end
  
  @doc """
  Sends a streaming chat completion request to OpenAI API.
  Returns a stream of Server-Sent Events.
  """
  def stream_completion(params, callback) do
    api_key = get_api_key()
    
    unless api_key do
      return {:error, :no_api_key}
    end
    
    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{api_key}"},
      {"Accept", "text/event-stream"}
    ]
    
    # Enable streaming
    params = Map.put(params, :stream, true)
    body = Jason.encode!(params)
    
    # Use streaming options
    options = [
      stream_to: self(),
      async: :once
    ]
    
    case HTTPoison.post("#{@openai_base_url}/chat/completions", body, headers, options) do
      {:ok, %HTTPoison.AsyncResponse{id: id}} ->
        handle_stream(id, callback, "")
        
      {:error, reason} ->
        Logger.error("Failed to start stream: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  # Private functions
  
  defp get_api_key do
    System.get_env("OPENAI_API_KEY") || 
    Application.get_env(:autonomous_opponent_core, :openai_api_key)
  end
  
  defp handle_stream(id, callback, buffer) do
    receive do
      %HTTPoison.AsyncStatus{id: ^id, code: status} when status != 200 ->
        Logger.error("Stream error: HTTP #{status}")
        {:error, {:http_status, status}}
        
      %HTTPoison.AsyncHeaders{id: ^id} ->
        # Continue receiving
        HTTPoison.stream_next(id)
        handle_stream(id, callback, buffer)
        
      %HTTPoison.AsyncChunk{id: ^id, chunk: chunk} ->
        # Process SSE data
        {events, new_buffer} = parse_sse_chunk(buffer <> chunk)
        
        Enum.each(events, fn event ->
          handle_sse_event(event, callback)
        end)
        
        # Continue receiving
        HTTPoison.stream_next(id)
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