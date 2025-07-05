defmodule AutonomousOpponentV2Core.Intelligence.OpenAIClient do
  @moduledoc """
  Secure OpenAI API client with automatic key rotation support.
  
  This module provides secure access to OpenAI APIs with:
  - Automatic API key retrieval from SecretsManager
  - Support for key rotation during runtime
  - Circuit breaker for API failures
  - Rate limiting to prevent quota exhaustion
  
  ## Usage
  
      # Make a completion request
      {:ok, response} = OpenAIClient.completion(%{
        model: "gpt-4",
        messages: [%{role: "user", content: "Hello"}]
      })
  """
  
  require Logger
  
  alias AutonomousOpponentV2Core.Security.SecretsManager
  alias AutonomousOpponentV2Core.Core.CircuitBreaker
  alias AutonomousOpponentV2Core.Core.RateLimiter
  alias AutonomousOpponentV2Core.EventBus
  
  @base_url "https://api.openai.com/v1"
  @timeout 30_000
  @rate_limit_name :openai_api_rate_limiter
  @circuit_breaker_name :openai_circuit_breaker
  
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
    case SecretsManager.get_secret("OPENAI_API_KEY") do
      {:ok, api_key} ->
        fun.(api_key)
        
      {:error, reason} ->
        Logger.error("Failed to retrieve OpenAI API key: #{inspect(reason)}")
        {:error, :api_key_unavailable}
    end
  end
  
  defp request(method, path, params, api_key, opts) do
    # Initialize rate limiter and circuit breaker if needed
    with :ok <- ensure_rate_limiter(),
         :ok <- ensure_circuit_breaker() do
      # Apply rate limiting
      case RateLimiter.consume(@rate_limit_name, 1) do
        {:ok, _tokens_remaining} ->
          # Apply circuit breaker
          CircuitBreaker.call(@circuit_breaker_name, fn ->
            execute_request(method, path, params, api_key, opts)
          end)
        
        {:error, :rate_limited} ->
          {:error, :rate_limited}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp ensure_rate_limiter do
    # Check if rate limiter is running, start if needed
    case Process.whereis(@rate_limit_name) do
      nil ->
        # Start rate limiter with appropriate config
        case RateLimiter.start_link(
          name: @rate_limit_name,
          bucket_size: 100,
          refill_rate: 50,
          refill_interval_ms: 1000
        ) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          error -> error
        end
      _pid ->
        :ok
    end
  end
  
  defp ensure_circuit_breaker do
    case Process.whereis(@circuit_breaker_name) do
      nil ->
        # Start circuit breaker with appropriate config
        case CircuitBreaker.start_link(
          name: @circuit_breaker_name,
          failure_threshold: 5,
          recovery_time_ms: 60_000,
          timeout_ms: 30_000
        ) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          error -> error
        end
      _pid ->
        :ok
    end
  end
  
  defp execute_request(method, path, params, api_key, opts) do
    url = @base_url <> path
    
    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"},
      {"OpenAI-Organization", opts[:organization] || ""}
    ]
    
    body = if method == :get, do: "", else: Jason.encode!(params)
    
    options = [
      timeout: opts[:timeout] || @timeout,
      recv_timeout: opts[:timeout] || @timeout
    ]
    
    case HTTPoison.request(method, url, body, headers, options) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} -> 
            track_usage(data)
            {:ok, data}
          {:error, _} -> 
            {:error, :invalid_response}
        end
        
      {:ok, %{status_code: 401}} ->
        # API key might be invalid or rotated
        EventBus.publish(:api_key_invalid, %{
          service: :openai,
          timestamp: DateTime.utc_now()
        })
        {:error, :unauthorized}
        
      {:ok, %{status_code: 429, headers: headers}} ->
        # Rate limited by OpenAI
        retry_after = get_retry_after(headers)
        EventBus.publish(:openai_rate_limited, %{
          retry_after: retry_after,
          timestamp: DateTime.utc_now()
        })
        {:error, {:rate_limited, retry_after}}
        
      {:ok, %{status_code: status, body: body}} ->
        Logger.error("OpenAI API error #{status}: #{body}")
        {:error, {:api_error, status}}
        
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
    case List.keyfind(headers, "Retry-After", 0) do
      {_, value} -> String.to_integer(value)
      nil -> 60  # Default to 60 seconds
    end
  end
end