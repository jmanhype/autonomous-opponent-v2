defmodule AutonomousOpponentV2Core.Intelligence.GoogleAIClient do
  @moduledoc """
  Google AI (Gemini) API client with connection pooling.
  
  This module provides secure access to Google's Gemini API with:
  - Automatic API key retrieval from SecretsManager
  - Connection pooling via PoolManager
  - Circuit breaker for API failures
  - Rate limiting to prevent quota exhaustion
  - Support for streaming responses
  
  ## Usage
  
      # Make a completion request
      {:ok, response} = GoogleAIClient.generate_content(%{
        model: "gemini-pro",
        contents: [%{
          parts: [%{text: "Hello"}],
          role: "user"
        }]
      })
  """
  
  require Logger
  
  alias AutonomousOpponentV2Core.Security.SecretsManager
  alias AutonomousOpponentV2Core.Core.RateLimiter
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.Connections.PoolManager
  
  @base_url "https://generativelanguage.googleapis.com/v1beta"
  @timeout 60_000
  
  # Client API
  
  @doc """
  Generate content using Google AI.
  """
  def generate_content(params, opts \\ []) do
    with_api_key(fn api_key ->
      model = Map.get(params, :model, "gemini-pro")
      path = "/models/#{model}:generateContent"
      
      # Remove model from params as it's in the URL
      params = Map.delete(params, :model)
      
      request(:post, path, params, api_key, opts)
    end)
  end
  
  @doc """
  Stream content generation from Google AI.
  """
  def stream_content(params, callback, opts \\ []) do
    with_api_key(fn api_key ->
      model = Map.get(params, :model, "gemini-pro")
      path = "/models/#{model}:streamGenerateContent"
      
      # Remove model from params as it's in the URL
      params = Map.delete(params, :model)
      
      stream_request(:post, path, params, api_key, callback, opts)
    end)
  end
  
  @doc """
  List available models.
  """
  def list_models(opts \\ []) do
    with_api_key(fn api_key ->
      request(:get, "/models", %{}, api_key, opts)
    end)
  end
  
  @doc """
  Get embeddings for text.
  """
  def embed_content(params, opts \\ []) do
    with_api_key(fn api_key ->
      model = Map.get(params, :model, "embedding-001")
      path = "/models/#{model}:embedContent"
      
      # Remove model from params as it's in the URL
      params = Map.delete(params, :model)
      
      request(:post, path, params, api_key, opts)
    end)
  end
  
  # Private Functions
  
  defp with_api_key(fun) do
    # Try environment variable first, then fall back to SecretsManager
    api_key = System.get_env("GOOGLE_AI_API_KEY") || 
              Application.get_env(:autonomous_opponent_core, :google_ai_api_key)
    
    if api_key && api_key != "" do
      fun.(api_key)
    else
      # Try SecretsManager as fallback
      case SecretsManager.get_secret("GOOGLE_AI_API_KEY") do
        {:ok, api_key} ->
          fun.(api_key)
          
        {:error, reason} ->
          Logger.error("Failed to retrieve Google AI API key: #{inspect(reason)}")
          {:error, :api_key_unavailable}
      end
    end
  end
  
  defp request(method, path, params, api_key, opts) do
    # Check if rate limiting is disabled (for development/testing)
    skip_rate_limit = Application.get_env(:autonomous_opponent_core, :skip_rate_limiting, false)
    
    # Apply rate limiting unless disabled
    if skip_rate_limit do
      execute_request(method, path, params, api_key, opts)
    else
      case RateLimiter.consume(AutonomousOpponentV2Core.Core.RateLimiter, 1) do
        {:ok, _tokens_remaining} ->
          execute_request(method, path, params, api_key, opts)
        
        {:error, :rate_limited} ->
          {:error, :rate_limited}
      end
    end
  end
  
  defp execute_request(method, path, params, api_key, opts) do
    # Add API key to URL parameters
    url_params = URI.encode_query(key: api_key)
    url = "#{@base_url}#{path}?#{url_params}"
    
    headers = [
      {"content-type", "application/json"}
    ]
    
    body = if method == :get, do: nil, else: Jason.encode!(params)
    
    # Build Finch request
    request = Finch.build(method, url, headers, body)
    
    # Use connection pool
    case PoolManager.request(:google_ai, request, timeout: opts[:timeout] || @timeout) do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} -> 
            track_usage(data)
            {:ok, data}
          {:error, _} -> 
            {:error, :invalid_response}
        end
        
      {:ok, %{status: 401}} ->
        EventBus.publish(:api_key_invalid, %{
          service: :google_ai,
          timestamp: DateTime.utc_now()
        })
        {:error, :unauthorized}
        
      {:ok, %{status: 429, headers: headers}} ->
        retry_after = get_retry_after(headers)
        EventBus.publish(:google_ai_rate_limited, %{
          retry_after: retry_after,
          timestamp: DateTime.utc_now()
        })
        {:error, {:rate_limited, retry_after}}
        
      {:ok, %{status: status, body: body}} ->
        Logger.error("Google AI API error #{status}: #{body}")
        
        # Try to parse error
        case Jason.decode(body) do
          {:ok, %{"error" => error}} ->
            {:error, {:api_error, error["message"] || "Unknown error"}}
          _ ->
            {:error, {:api_error, status}}
        end
        
      {:error, :circuit_open} ->
        Logger.error("Google AI circuit breaker is open")
        {:error, :service_unavailable}
        
      {:error, reason} ->
        Logger.error("Google AI request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp stream_request(method, path, params, api_key, callback, opts) do
    # Add API key and alt=sse to URL parameters for streaming
    url_params = URI.encode_query(key: api_key, alt: "sse")
    url = "#{@base_url}#{path}?#{url_params}"
    
    headers = [
      {"content-type", "application/json"},
      {"accept", "text/event-stream"}
    ]
    
    body = Jason.encode!(params)
    
    # Build Finch request
    request = Finch.build(method, url, headers, body)
    
    # Use connection pool with streaming
    case PoolManager.stream(:google_ai, request, "", &handle_stream_chunk(&1, &2, callback)) do
      {:ok, _result} ->
        callback.({:done, nil})
        :ok
        
      {:error, :circuit_open} ->
        Logger.error("Google AI circuit breaker is open")
        {:error, :service_unavailable}
        
      {:error, reason} ->
        Logger.error("Failed to start stream: #{inspect(reason)}")
        {:error, reason}
    end
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
  
  defp handle_sse_event(event_data, callback) do
    case Jason.decode(event_data) do
      {:ok, data} ->
        # Extract text from candidates
        case get_in(data, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"]) do
          nil -> :ok
          text -> callback.({:chunk, text})
        end
        
        # Check if response is finished
        case data["candidates"] do
          [%{"finishReason" => reason}] when reason != nil ->
            callback.({:done, reason})
          _ ->
            :ok
        end
        
      {:error, _} ->
        # Ignore malformed events
        :ok
    end
  end
  
  defp track_usage(response) do
    case response["usageMetadata"] do
      nil -> :ok
      usage ->
        EventBus.publish(:google_ai_usage, %{
          prompt_tokens: usage["promptTokenCount"],
          candidates_tokens: usage["candidatesTokenCount"],
          total_tokens: usage["totalTokenCount"],
          timestamp: DateTime.utc_now()
        })
    end
  end
  
  defp get_retry_after(headers) do
    case List.keyfind(headers, "retry-after", 0) do
      {_, value} -> String.to_integer(value)
      nil -> 60  # Default to 60 seconds
    end
  end
end