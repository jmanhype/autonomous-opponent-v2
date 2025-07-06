defmodule AutonomousOpponentV2Core.Core.IPRateLimiter do
  @moduledoc """
  IP-based rate limiter plug for Phoenix applications.
  
  This module provides:
  - IP-based rate limiting
  - Configurable rate limits per endpoint
  - Whitelist/blacklist support
  - Rate limit headers in responses
  - Integration with both token bucket and sliding window algorithms
  """
  
  import Plug.Conn
  require Logger
  
  alias AutonomousOpponentV2Core.Core.{RateLimiter, SlidingWindowRateLimiter}
  alias AutonomousOpponentV2Core.EventBus
  
  @behaviour Plug
  
  @default_config %{
    algorithm: :token_bucket,  # :token_bucket or :sliding_window
    rate_limiter: AutonomousOpponentV2Core.Core.RateLimiter,
    bucket_size: 100,
    refill_rate: 10,
    window_ms: 60_000,
    max_requests: 100,
    whitelist: [],
    blacklist: [],
    key_generator: &__MODULE__.default_key_generator/1,
    on_rate_limited: &__MODULE__.default_rate_limited_response/1
  }
  
  @impl Plug
  def init(opts) do
    config = Map.merge(@default_config, Map.new(opts))
    
    # Start the appropriate rate limiter if not already running
    ensure_rate_limiter_started(config)
    
    config
  end
  
  @impl Plug
  def call(conn, config) do
    ip = get_client_ip(conn)
    
    # Check whitelist/blacklist
    cond do
      ip in config.blacklist ->
        config.on_rate_limited.(conn)
        |> halt()
        
      ip in config.whitelist ->
        conn
        
      true ->
        check_rate_limit(conn, ip, config)
    end
  end
  
  @doc """
  Get client IP from connection, handling proxies
  """
  def get_client_ip(conn) do
    # Check X-Forwarded-For header first (for proxies)
    forwarded_for = get_req_header(conn, "x-forwarded-for")
    
    case forwarded_for do
      [forwarded | _] ->
        # Take the first IP from the comma-separated list
        forwarded
        |> String.split(",")
        |> List.first()
        |> String.trim()
        
      [] ->
        # Fall back to peer IP
        case conn.remote_ip do
          {a, b, c, d} -> "#{a}.#{b}.#{c}.#{d}"
          {a, b, c, d, e, f, g, h} -> 
            # IPv6 - convert to string
            :inet.ntoa({a, b, c, d, e, f, g, h}) |> to_string()
          _ -> "unknown"
        end
    end
  end
  
  defp check_rate_limit(conn, ip, config) do
    key = config.key_generator.(conn)
    identifier = {ip, key}
    
    result = case config.algorithm do
      :sliding_window ->
        SlidingWindowRateLimiter.check_and_track(config.rate_limiter, identifier)
        
      :token_bucket ->
        case RateLimiter.consume_for_client(config.rate_limiter, identifier, 1) do
          {:ok, remaining} -> 
            {:ok, %{global: %{remaining: remaining, max: config.bucket_size}}}
          {:error, :rate_limited} -> 
            {:error, :rate_limited, %{}}
        end
    end
    
    case result do
      {:ok, usage_info} ->
        conn
        |> add_rate_limit_headers(usage_info, config)
        |> track_allowed_request(ip, key)
        
      {:error, :rate_limited, usage_info} ->
        conn
        |> add_rate_limit_headers(usage_info, config)
        |> track_rate_limited_request(ip, key)
        |> config.on_rate_limited.()
        |> halt()
    end
  end
  
  defp add_rate_limit_headers(conn, usage_info, config) do
    headers = case config.algorithm do
      :sliding_window ->
        # Get headers from sliding window implementation
        case SlidingWindowRateLimiter.get_rate_limit_headers(config.rate_limiter, get_client_ip(conn)) do
          {:ok, headers} -> headers
          _ -> []
        end
        
      :token_bucket ->
        # Build headers for token bucket
        info = Map.get(usage_info, :global, %{})
        remaining = Map.get(info, :remaining, 0)
        max = Map.get(info, :max, config.bucket_size)
        
        [
          {"x-ratelimit-limit", Integer.to_string(max)},
          {"x-ratelimit-remaining", Integer.to_string(remaining)},
          {"x-ratelimit-reset", Integer.to_string(System.os_time(:second) + 60)}
        ]
    end
    
    Enum.reduce(headers, conn, fn {key, value}, conn ->
      put_resp_header(conn, key, value)
    end)
  end
  
  defp track_allowed_request(conn, ip, key) do
    EventBus.publish(:ip_rate_limit_allowed, %{
      ip: ip,
      path: conn.request_path,
      method: conn.method,
      key: key,
      timestamp: DateTime.utc_now()
    })
    
    conn
  end
  
  defp track_rate_limited_request(conn, ip, key) do
    Logger.warning("Rate limited request from #{ip} to #{conn.method} #{conn.request_path}")
    
    EventBus.publish(:ip_rate_limited, %{
      ip: ip,
      path: conn.request_path,
      method: conn.method,
      key: key,
      timestamp: DateTime.utc_now()
    })
    
    conn
  end
  
  @doc """
  Default key generator - uses request path
  """
  def default_key_generator(conn) do
    "#{conn.method}:#{conn.request_path}"
  end
  
  @doc """
  Default rate limited response
  """
  def default_rate_limited_response(conn) do
    conn
    |> put_status(:too_many_requests)
    |> put_resp_content_type("application/json")
    |> send_resp(429, Jason.encode!(%{
      error: "rate_limited",
      message: "Too many requests. Please retry after some time."
    }))
  end
  
  defp ensure_rate_limiter_started(config) do
    case Process.whereis(config.rate_limiter) do
      nil ->
        # Start the rate limiter
        case config.algorithm do
          :sliding_window ->
            SlidingWindowRateLimiter.start_link(
              name: config.rate_limiter,
              rules: %{
                default: {config.window_ms, config.max_requests}
              }
            )
            
          :token_bucket ->
            RateLimiter.start_link(
              name: config.rate_limiter,
              bucket_size: config.bucket_size,
              refill_rate: config.refill_rate
            )
        end
        
      _pid ->
        :ok
    end
  end
  
  @doc """
  Create a rate limiter plug with custom configuration
  
  ## Examples
  
      # In your router
      pipeline :api do
        plug IPRateLimiter.create_plug(
          algorithm: :sliding_window,
          window_ms: 60_000,
          max_requests: 100,
          whitelist: ["127.0.0.1"],
          key_generator: fn conn -> 
            "\#{conn.method}:\#{conn.request_path}"
          end
        )
      end
  """
  def create_plug(opts) do
    {__MODULE__, opts}
  end
end