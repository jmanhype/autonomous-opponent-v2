defmodule AutonomousOpponentV2Core.Connections.HTTPClient do
  @moduledoc """
  Unified HTTP client interface using connection pools.
  
  This module provides a simple interface for making HTTP requests
  using the underlying PoolManager infrastructure. It handles:
  - Connection pooling
  - Circuit breaking
  - Automatic retries
  - Request/response transformation
  
  ## Usage
  
      # Simple GET request
      {:ok, response} = HTTPClient.get("https://api.example.com/data")
      
      # POST with JSON body
      {:ok, response} = HTTPClient.post(
        "https://api.example.com/users",
        %{name: "John", email: "john@example.com"},
        headers: [{"authorization", "Bearer token"}]
      )
      
      # Custom pool
      {:ok, response} = HTTPClient.get(
        "https://api.openai.com/v1/models",
        pool: :openai
      )
  """
  
  alias AutonomousOpponentV2Core.Connections.PoolManager
  
  @default_timeout 30_000
  @default_pool :default
  
  @type url :: String.t()
  @type body :: map() | String.t() | nil
  @type headers :: [{String.t(), String.t()}]
  @type options :: keyword()
  @type response :: %{
    status: non_neg_integer(),
    headers: headers(),
    body: String.t()
  }
  
  # HTTP Methods
  
  @doc """
  Performs a GET request.
  """
  @spec get(url(), options()) :: {:ok, response()} | {:error, term()}
  def get(url, opts \\ []) do
    request(:get, url, nil, opts)
  end
  
  @doc """
  Performs a POST request.
  """
  @spec post(url(), body(), options()) :: {:ok, response()} | {:error, term()}
  def post(url, body, opts \\ []) do
    request(:post, url, body, opts)
  end
  
  @doc """
  Performs a PUT request.
  """
  @spec put(url(), body(), options()) :: {:ok, response()} | {:error, term()}
  def put(url, body, opts \\ []) do
    request(:put, url, body, opts)
  end
  
  @doc """
  Performs a PATCH request.
  """
  @spec patch(url(), body(), options()) :: {:ok, response()} | {:error, term()}
  def patch(url, body, opts \\ []) do
    request(:patch, url, body, opts)
  end
  
  @doc """
  Performs a DELETE request.
  """
  @spec delete(url(), options()) :: {:ok, response()} | {:error, term()}
  def delete(url, opts \\ []) do
    request(:delete, url, nil, opts)
  end
  
  @doc """
  Performs a HEAD request.
  """
  @spec head(url(), options()) :: {:ok, response()} | {:error, term()}
  def head(url, opts \\ []) do
    request(:head, url, nil, opts)
  end
  
  @doc """
  Performs an OPTIONS request.
  """
  @spec options(url(), options()) :: {:ok, response()} | {:error, term()}
  def options(url, opts \\ []) do
    request(:options, url, nil, opts)
  end
  
  @doc """
  Performs a generic HTTP request.
  
  Options:
  - `:pool` - The connection pool to use (default: `:default`)
  - `:headers` - Request headers
  - `:timeout` - Request timeout in milliseconds
  - `:json` - If true, automatically encode/decode JSON
  - `:retry` - Number of retries on failure
  - `:retry_delay` - Delay between retries in milliseconds
  """
  @spec request(atom(), url(), body(), options()) :: {:ok, response()} | {:error, term()}
  def request(method, url, body, opts \\ []) do
    pool = Keyword.get(opts, :pool, determine_pool(url))
    headers = build_headers(opts)
    body = encode_body(body, opts)
    
    # Build Finch request
    finch_request = Finch.build(method, url, headers, body)
    
    # Execute with retries
    with_retries(opts, fn ->
      case PoolManager.request(pool, finch_request, timeout: get_timeout(opts)) do
        {:ok, response} ->
          {:ok, transform_response(response, opts)}
          
        {:error, reason} = error ->
          error
      end
    end)
  end
  
  @doc """
  Performs a streaming request.
  
  The callback function receives chunks of data as they arrive.
  """
  @spec stream(atom(), url(), body(), (term(), term() -> term()), term(), options()) :: 
    {:ok, term()} | {:error, term()}
  def stream(method, url, body, fun, acc, opts \\ []) do
    pool = Keyword.get(opts, :pool, determine_pool(url))
    headers = build_headers(opts)
    body = encode_body(body, opts)
    
    # Build Finch request
    finch_request = Finch.build(method, url, headers, body)
    
    # Execute streaming request
    PoolManager.stream(pool, finch_request, acc, fun)
  end
  
  # Private Functions
  
  defp determine_pool(url) do
    uri = URI.parse(url)
    
    case uri.host do
      "api.openai.com" -> :openai
      "api.anthropic.com" -> :anthropic
      "generativelanguage.googleapis.com" -> :google_ai
      "localhost" when uri.port == 11434 -> :local_llm
      "localhost" when uri.port == 8200 -> :vault
      _ -> @default_pool
    end
  end
  
  defp build_headers(opts) do
    base_headers = Keyword.get(opts, :headers, [])
    
    if Keyword.get(opts, :json, false) and not has_content_type?(base_headers) do
      [{"content-type", "application/json"} | base_headers]
    else
      base_headers
    end
  end
  
  defp has_content_type?(headers) do
    Enum.any?(headers, fn {name, _value} ->
      String.downcase(name) == "content-type"
    end)
  end
  
  defp encode_body(nil, _opts), do: nil
  defp encode_body(body, opts) when is_binary(body), do: body
  
  defp encode_body(body, opts) do
    if Keyword.get(opts, :json, true) do
      Jason.encode!(body)
    else
      to_string(body)
    end
  end
  
  defp transform_response(response, opts) do
    response = %{
      status: response.status,
      headers: response.headers,
      body: response.body
    }
    
    if Keyword.get(opts, :json, false) and json_response?(response) do
      case Jason.decode(response.body) do
        {:ok, decoded} ->
          %{response | body: decoded}
          
        {:error, _} ->
          response
      end
    else
      response
    end
  end
  
  defp json_response?(%{headers: headers}) do
    Enum.any?(headers, fn {name, value} ->
      String.downcase(name) == "content-type" and
      String.contains?(value, "application/json")
    end)
  end
  
  defp get_timeout(opts) do
    Keyword.get(opts, :timeout, @default_timeout)
  end
  
  defp with_retries(opts, fun) do
    max_retries = Keyword.get(opts, :retry, 0)
    retry_delay = Keyword.get(opts, :retry_delay, 1_000)
    
    do_with_retries(fun, max_retries, retry_delay, 0)
  end
  
  defp do_with_retries(fun, max_retries, _retry_delay, attempt) when attempt > max_retries do
    fun.()
  end
  
  defp do_with_retries(fun, max_retries, retry_delay, attempt) do
    case fun.() do
      {:error, reason} = _error when attempt < max_retries ->
        if should_retry?(reason) do
          Process.sleep(retry_delay * (attempt + 1))
          do_with_retries(fun, max_retries, retry_delay, attempt + 1)
        else
          {:error, reason}
        end
        
      result ->
        result
    end
  end
  
  defp should_retry?(:timeout), do: true
  defp should_retry?(:econnrefused), do: true
  defp should_retry?({:closed, _}), do: true
  defp should_retry?(_), do: false
end