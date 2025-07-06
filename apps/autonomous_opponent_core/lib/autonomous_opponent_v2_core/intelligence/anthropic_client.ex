defmodule AutonomousOpponentV2Core.Intelligence.AnthropicClient do
  @moduledoc """
  Anthropic Claude API client with connection pooling.
  
  This module provides secure access to Anthropic's Claude API with:
  - Automatic API key retrieval from SecretsManager
  - Connection pooling via PoolManager
  - Circuit breaker for API failures
  - Rate limiting to prevent quota exhaustion
  - Support for streaming responses
  
  ## Usage
  
      # Make a completion request
      {:ok, response} = AnthropicClient.completion(%{
        model: "claude-3-opus-20240229",
        messages: [%{role: "user", content: "Hello"}],
        max_tokens: 100
      })
  """
  
  require Logger
  
  alias AutonomousOpponentV2Core.Security.SecretsManager
  alias AutonomousOpponentV2Core.Core.RateLimiter
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.Connections.PoolManager
  
  @base_url "https://api.anthropic.com/v1"
  @timeout 60_000
  @anthropic_version "2023-06-01"
  
  # Client API
  
  @doc """
  Make a completion request to Anthropic.
  """
  def completion(params, opts \\ []) do
    with_api_key(fn api_key ->
      request(:post, "/messages", params, api_key, opts)
    end)
  end
  
  @doc """
  Stream a completion response from Anthropic.
  """
  def stream_completion(params, callback, opts \\ []) do
    with_api_key(fn api_key ->
      params = Map.put(params, :stream, true)
      stream_request(:post, "/messages", params, api_key, callback, opts)
    end)
  end
  
  @doc """
  List available models.
  """
  def list_models(opts \\ []) do
    # Anthropic doesn't have a models endpoint, return known models
    {:ok, %{
      "models" => [
        %{"id" => "claude-3-opus-20240229", "name" => "Claude 3 Opus"},
        %{"id" => "claude-3-sonnet-20240229", "name" => "Claude 3 Sonnet"},
        %{"id" => "claude-3-haiku-20240307", "name" => "Claude 3 Haiku"},
        %{"id" => "claude-2.1", "name" => "Claude 2.1"},
        %{"id" => "claude-2.0", "name" => "Claude 2.0"},
        %{"id" => "claude-instant-1.2", "name" => "Claude Instant 1.2"}
      ]
    }}
  end
  
  # Private Functions
  
  defp with_api_key(fun) do
    # Try environment variable first, then fall back to SecretsManager
    api_key = System.get_env("ANTHROPIC_API_KEY") || 
              Application.get_env(:autonomous_opponent_core, :anthropic_api_key)
    
    if api_key && api_key != "" do
      fun.(api_key)
    else
      # Try SecretsManager as fallback
      case SecretsManager.get_secret("ANTHROPIC_API_KEY") do
        {:ok, api_key} ->
          fun.(api_key)
          
        {:error, reason} ->
          Logger.error("Failed to retrieve Anthropic API key: #{inspect(reason)}")
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
    url = @base_url <> path
    
    headers = [
      {"x-api-key", api_key},
      {"content-type", "application/json"},
      {"anthropic-version", @anthropic_version}
    ]
    
    body = if method == :get, do: nil, else: Jason.encode!(params)
    
    # Build Finch request
    request = Finch.build(method, url, headers, body)
    
    # Use connection pool
    case PoolManager.request(:anthropic, request, timeout: opts[:timeout] || @timeout) do
      # Handle double-nested response from CircuitBreaker + PoolManager
      {:ok, {:ok, %{status: 200, body: body}}} ->
        case Jason.decode(body) do
          {:ok, data} -> 
            track_usage(data)
            {:ok, data}
          {:error, _} -> 
            {:error, :invalid_response}
        end
        
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} -> 
            track_usage(data)
            {:ok, data}
          {:error, _} -> 
            {:error, :invalid_response}
        end
        
      # Handle double-nested responses for error cases too
      {:ok, {:ok, %{status: 401}}} ->
        EventBus.publish(:api_key_invalid, %{
          service: :anthropic,
          timestamp: DateTime.utc_now()
        })
        {:error, :unauthorized}
        
      {:ok, %{status: 401}} ->
        EventBus.publish(:api_key_invalid, %{
          service: :anthropic,
          timestamp: DateTime.utc_now()
        })
        {:error, :unauthorized}
        
      {:ok, {:ok, %{status: 429, headers: headers}}} ->
        retry_after = get_retry_after(headers)
        EventBus.publish(:anthropic_rate_limited, %{
          retry_after: retry_after,
          timestamp: DateTime.utc_now()
        })
        {:error, {:rate_limited, retry_after}}
        
      {:ok, %{status: 429, headers: headers}} ->
        retry_after = get_retry_after(headers)
        EventBus.publish(:anthropic_rate_limited, %{
          retry_after: retry_after,
          timestamp: DateTime.utc_now()
        })
        {:error, {:rate_limited, retry_after}}
        
      {:ok, {:ok, %{status: status, body: body}}} ->
        Logger.error("Anthropic API error #{status}: #{body}")
        {:error, {:api_error, status}}
        
      {:ok, %{status: status, body: body}} ->
        Logger.error("Anthropic API error #{status}: #{body}")
        {:error, {:api_error, status}}
        
      {:error, :circuit_open} ->
        Logger.error("Anthropic circuit breaker is open")
        {:error, :service_unavailable}
        
      {:error, reason} ->
        Logger.error("Anthropic request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp stream_request(method, path, params, api_key, callback, opts) do
    url = @base_url <> path
    
    headers = [
      {"x-api-key", api_key},
      {"content-type", "application/json"},
      {"anthropic-version", @anthropic_version},
      {"accept", "text/event-stream"}
    ]
    
    body = Jason.encode!(params)
    
    # Build Finch request
    request = Finch.build(method, url, headers, body)
    
    # Use connection pool with streaming
    case PoolManager.stream(:anthropic, request, "", &handle_stream_chunk(&1, &2, callback)) do
      {:ok, _result} ->
        callback.({:done, nil})
        :ok
        
      {:error, :circuit_open} ->
        Logger.error("Anthropic circuit breaker is open")
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
            
          String.starts_with?(line, "event: ") ->
            # Event type (we'll handle this separately if needed)
            {events, buffer}
            
          true ->
            # Continue building
            {events, buffer}
        end
      end)
      
    {complete_events, remaining}
  end
  
  defp handle_sse_event(event_data, callback) do
    case Jason.decode(event_data) do
      {:ok, %{"type" => "message_start"}} ->
        # Message started
        :ok
        
      {:ok, %{"type" => "content_block_delta", "delta" => %{"text" => text}}} ->
        # Content chunk
        callback.({:chunk, text})
        
      {:ok, %{"type" => "message_stop"}} ->
        # Message completed
        callback.({:done, nil})
        
      {:ok, %{"type" => "error", "error" => error}} ->
        Logger.error("Anthropic stream error: #{inspect(error)}")
        callback.({:error, error})
        
      {:ok, _data} ->
        # Other event types
        :ok
        
      {:error, _} ->
        # Ignore malformed events
        :ok
    end
  end
  
  defp track_usage(response) do
    case response["usage"] do
      nil -> :ok
      usage ->
        EventBus.publish(:anthropic_usage, %{
          input_tokens: usage["input_tokens"],
          output_tokens: usage["output_tokens"],
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