defmodule AutonomousOpponentV2Core.Intelligence.OpenAIClient do
  @moduledoc """
  Secure OpenAI API client with automatic key rotation support.
  
  This module provides secure access to OpenAI APIs with:
  - Automatic API key retrieval from SecretsManager
  - Support for key rotation during runtime
  - Circuit breaker for API failures
  - Rate limiting to prevent quota exhaustion
  - Connection pooling via PoolManager
  
  ## Usage
  
      # Make a completion request
      {:ok, response} = OpenAIClient.completion(%{
        model: "gpt-4",
        messages: [%{role: "user", content: "Hello"}]
      })
  """
  
  require Logger
  
  alias AutonomousOpponentV2Core.Security.SecretsManager
  alias AutonomousOpponentV2Core.Core.RateLimiter
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.Connections.PoolManager
  
  @base_url "https://api.openai.com/v1"
  @timeout 30_000
  
  # Client API
  
  @doc """
  Make a completion request to OpenAI.
  """
  def completion(params, opts \\ []) do
    with_api_key(fn api_key ->
      request(:post, "/chat/completions", params, api_key, opts)
    end)
  end
  
  @doc """
  Create embeddings using OpenAI.
  """
  def embeddings(params, opts \\ []) do
    with_api_key(fn api_key ->
      request(:post, "/embeddings", params, api_key, opts)
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
  Get current API usage.
  """
  def get_usage(opts \\ []) do
    with_api_key(fn api_key ->
      request(:get, "/usage", %{}, api_key, opts)
    end)
  end
  
  # Private Functions
  
  defp with_api_key(fun) do
    # Try environment variable first, then fall back to SecretsManager
    api_key = System.get_env("OPENAI_API_KEY") || 
              Application.get_env(:autonomous_opponent_core, :openai_api_key)
    
    if api_key && api_key != "" do
      fun.(api_key)
    else
      # Try SecretsManager as fallback
      case SecretsManager.get_secret("OPENAI_API_KEY") do
        {:ok, api_key} ->
          fun.(api_key)
          
        {:error, reason} ->
          Logger.error("Failed to retrieve OpenAI API key: #{inspect(reason)}")
          {:error, :api_key_unavailable}
      end
    end
  end
  
  defp request(method, path, params, api_key, opts) do
    # Check if rate limiting is disabled (for development/testing)
    skip_rate_limit = Application.get_env(:autonomous_opponent_core, :skip_rate_limiting, false)
    
    # Initialize rate limiter and circuit breaker if needed
    with :ok <- ensure_rate_limiter(),
         :ok <- ensure_circuit_breaker() do
      # Apply rate limiting unless disabled
      if skip_rate_limit do
        # Skip rate limiting in development
        execute_request(method, path, params, api_key, opts)
      else
        case RateLimiter.consume(AutonomousOpponentV2Core.Core.RateLimiter, 1) do
          {:ok, _tokens_remaining} ->
            execute_request(method, path, params, api_key, opts)
          
          {:error, :rate_limited} ->
            {:error, :rate_limited}
        end
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp ensure_rate_limiter do
    # Use the global RateLimiter that's already started in the application
    # The global RateLimiter is named AutonomousOpponentV2Core.Core.RateLimiter
    :ok
  end
  
  defp ensure_circuit_breaker do
    # Circuit breaker is initialized on-demand
    :ok
  end
  
  defp execute_request(method, path, params, api_key, opts) do
    url = @base_url <> path
    
    headers = [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"},
      {"openai-organization", opts[:organization] || ""}
    ]
    
    body = if method == :get, do: nil, else: Jason.encode!(params)
    
    # Build Finch request
    request = Finch.build(method, url, headers, body)
    
    # Use connection pool
    case PoolManager.request(:openai, request, timeout: opts[:timeout] || @timeout) do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} -> 
            track_usage(data)
            {:ok, data}
          {:error, _} -> 
            {:error, :invalid_response}
        end
        
      {:ok, %{status: 401}} ->
        # API key might be invalid or rotated
        EventBus.publish(:api_key_invalid, %{
          service: :openai,
          timestamp: DateTime.utc_now()
        })
        {:error, :unauthorized}
        
      {:ok, %{status: 429, headers: headers}} ->
        # Rate limited by OpenAI
        retry_after = get_retry_after(headers)
        EventBus.publish(:openai_rate_limited, %{
          retry_after: retry_after,
          timestamp: DateTime.utc_now()
        })
        {:error, {:rate_limited, retry_after}}
        
      {:ok, %{status: status, body: body}} ->
        Logger.error("OpenAI API error #{status}: #{body}")
        {:error, {:api_error, status}}
        
      {:error, :circuit_open} ->
        Logger.error("OpenAI circuit breaker is open")
        {:error, :service_unavailable}
        
      {:error, reason} ->
        Logger.error("OpenAI request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp track_usage(response) do
    case response["usage"] do
      nil -> :ok
      usage ->
        EventBus.publish(:openai_usage, %{
          prompt_tokens: usage["prompt_tokens"],
          completion_tokens: usage["completion_tokens"],
          total_tokens: usage["total_tokens"],
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