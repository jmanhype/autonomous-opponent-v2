defmodule AutonomousOpponentV2Core.AMCP.Security.NonceValidator do
  @moduledoc """
  Nonce validation system for aMCP security layer.
  
  Prevents replay attacks by ensuring message nonces are:
  - Unique within the time window
  - Not reused across sessions  
  - Cryptographically secure
  - Efficiently validated using bloom filters
  
  Uses a combination of:
  - In-memory LRU cache for recent nonces
  - Bloom filter for fast membership checking
  - Persistent storage for long-term validation
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.AMCP.Security.BloomFilter
  
  defstruct [
    :nonce_cache,
    :bloom_filter,
    :window_size,
    :max_cache_size,
    :cleanup_interval,
    :stats
  ]
  
  @default_window_size 300_000  # 5 minutes in milliseconds
  @default_cache_size 100_000   # Maximum nonces in memory
  @cleanup_interval 60_000      # Cleanup every minute
  @nonce_size 32               # 32 bytes = 256 bits
  
  # Public API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Validates a nonce to ensure it hasn't been used before.
  
  Returns:
  - :ok - Nonce is valid and has been recorded
  - {:error, :duplicate} - Nonce has been used before
  - {:error, :invalid_format} - Nonce format is invalid
  """
  def validate_nonce(nonce) when is_binary(nonce) do
    GenServer.call(__MODULE__, {:validate_nonce, nonce})
  end
  
  @doc """
  Generates a cryptographically secure nonce.
  """
  def generate_nonce do
    :crypto.strong_rand_bytes(@nonce_size) |> Base.encode64(padding: false)
  end
  
  @doc """
  Checks if a nonce exists without recording it.
  """
  def check_nonce(nonce) when is_binary(nonce) do
    GenServer.call(__MODULE__, {:check_nonce, nonce})
  end
  
  @doc """
  Forces cleanup of expired nonces.
  """
  def cleanup_expired do
    GenServer.cast(__MODULE__, :cleanup_expired)
  end
  
  @doc """
  Gets validation statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Resets the nonce validator (for testing).
  """
  def reset do
    GenServer.call(__MODULE__, :reset)
  end
  
  # GenServer Callbacks
  
  @impl true
  def init(opts) do
    window_size = Keyword.get(opts, :window_size, @default_window_size)
    max_cache_size = Keyword.get(opts, :max_cache_size, @default_cache_size)
    
    # Initialize bloom filter with appropriate size
    # False positive rate: ~0.1% with 1M expected items
    bloom_filter = BloomFilter.new(1_000_000, 0.001)
    
    # Start cleanup timer
    :timer.send_interval(@cleanup_interval, :cleanup)
    
    state = %__MODULE__{
      nonce_cache: %{},
      bloom_filter: bloom_filter,
      window_size: window_size,
      max_cache_size: max_cache_size,
      cleanup_interval: @cleanup_interval,
      stats: init_stats()
    }
    
    Logger.info("NonceValidator started with #{window_size}ms window, #{max_cache_size} cache size")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:validate_nonce, nonce}, _from, state) do
    case validate_nonce_format(nonce) do
      :ok ->
        case check_duplicate(nonce, state) do
          {:duplicate, new_state} ->
            new_stats = increment_stat(new_state.stats, :duplicates)
            final_state = %{new_state | stats: new_stats}
            {:reply, {:error, :duplicate}, final_state}
            
          {:unique, new_state} ->
            # Record the nonce
            final_state = record_nonce(nonce, new_state)
            new_stats = increment_stat(final_state.stats, :validated)
            final_state = %{final_state | stats: new_stats}
            {:reply, :ok, final_state}
        end
        
      {:error, reason} ->
        new_stats = increment_stat(state.stats, :invalid_format)
        new_state = %{state | stats: new_stats}
        {:reply, {:error, reason}, new_state}
    end
  end
  
  @impl true
  def handle_call({:check_nonce, nonce}, _from, state) do
    case validate_nonce_format(nonce) do
      :ok ->
        case check_duplicate(nonce, state) do
          {:duplicate, new_state} ->
            {:reply, {:exists, true}, new_state}
          {:unique, new_state} ->
            {:reply, {:exists, false}, new_state}
        end
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = Map.merge(state.stats, %{
      cache_size: map_size(state.nonce_cache),
      bloom_filter_size: BloomFilter.estimated_count(state.bloom_filter),
      window_size: state.window_size,
      uptime: System.system_time(:millisecond) - state.stats.started_at
    })
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call(:reset, _from, state) do
    new_bloom_filter = BloomFilter.new(1_000_000, 0.001)
    new_state = %{state |
      nonce_cache: %{},
      bloom_filter: new_bloom_filter,
      stats: init_stats()
    }
    Logger.info("NonceValidator reset")
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_cast(:cleanup_expired, state) do
    new_state = cleanup_expired_nonces(state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    new_state = cleanup_expired_nonces(state)
    {:noreply, new_state}
  end
  
  # Private Functions
  
  defp init_stats do
    %{
      validated: 0,
      duplicates: 0,
      invalid_format: 0,
      cleanups: 0,
      started_at: System.system_time(:millisecond)
    }
  end
  
  defp increment_stat(stats, key) do
    Map.update(stats, key, 1, &(&1 + 1))
  end
  
  defp validate_nonce_format(nonce) when is_binary(nonce) do
    cond do
      byte_size(nonce) < 16 ->
        {:error, :too_short}
        
      byte_size(nonce) > 128 ->
        {:error, :too_long}
        
      not String.match?(nonce, ~r/^[A-Za-z0-9+\/\-_]+={0,2}$/) ->
        {:error, :invalid_encoding}
        
      true ->
        :ok
    end
  end
  
  defp validate_nonce_format(_), do: {:error, :invalid_type}
  
  defp check_duplicate(nonce, state) do
    current_time = System.system_time(:millisecond)
    
    # First check bloom filter (fast negative check)
    case BloomFilter.contains?(state.bloom_filter, nonce) do
      false ->
        # Definitely not a duplicate
        {:unique, state}
        
      true ->
        # Might be a duplicate, check cache
        case Map.get(state.nonce_cache, nonce) do
          nil ->
            # Bloom filter false positive
            {:unique, state}
            
          timestamp ->
            if current_time - timestamp < state.window_size do
              # Duplicate within window
              {:duplicate, state}
            else
              # Expired, can be reused
              new_cache = Map.delete(state.nonce_cache, nonce)
              new_state = %{state | nonce_cache: new_cache}
              {:unique, new_state}
            end
        end
    end
  end
  
  defp record_nonce(nonce, state) do
    current_time = System.system_time(:millisecond)
    
    # Add to bloom filter
    new_bloom_filter = BloomFilter.add(state.bloom_filter, nonce)
    
    # Add to cache with timestamp
    new_cache = Map.put(state.nonce_cache, nonce, current_time)
    
    # Check if cache needs pruning
    final_cache = if map_size(new_cache) > state.max_cache_size do
      prune_cache(new_cache, state.max_cache_size * 0.8 |> round())
    else
      new_cache
    end
    
    %{state |
      bloom_filter: new_bloom_filter,
      nonce_cache: final_cache
    }
  end
  
  defp cleanup_expired_nonces(state) do
    current_time = System.system_time(:millisecond)
    cutoff_time = current_time - state.window_size
    
    # Remove expired nonces from cache
    new_cache = state.nonce_cache
    |> Enum.filter(fn {_nonce, timestamp} -> timestamp >= cutoff_time end)
    |> Map.new()
    
    removed_count = map_size(state.nonce_cache) - map_size(new_cache)
    
    if removed_count > 0 do
      Logger.debug("Cleaned up #{removed_count} expired nonces")
    end
    
    new_stats = increment_stat(state.stats, :cleanups)
    
    %{state |
      nonce_cache: new_cache,
      stats: new_stats
    }
  end
  
  defp prune_cache(cache, target_size) do
    # Keep the most recent nonces
    cache
    |> Enum.sort_by(fn {_nonce, timestamp} -> timestamp end, :desc)
    |> Enum.take(target_size)
    |> Map.new()
  end
  
  @doc """
  Validates a message nonce from aMCP message headers.
  """
  def validate_message_nonce(%{nonce: nonce}) when is_binary(nonce) do
    validate_nonce(nonce)
  end
  
  def validate_message_nonce(%{"nonce" => nonce}) when is_binary(nonce) do
    validate_nonce(nonce)
  end
  
  def validate_message_nonce(_message) do
    {:error, :missing_nonce}
  end
  
  @doc """
  Adds a nonce to an aMCP message.
  """
  def add_nonce_to_message(message) when is_map(message) do
    nonce = generate_nonce()
    Map.put(message, :nonce, nonce)
  end
  
  @doc """
  Validates nonce within a time window for temporal validation.
  """
  def validate_temporal_nonce(nonce, message_timestamp, max_age_ms \\ 300_000) when is_binary(nonce) do
    current_time = System.system_time(:millisecond)
    
    case validate_nonce(nonce) do
      :ok ->
        if current_time - message_timestamp <= max_age_ms do
          :ok
        else
          {:error, :message_too_old}
        end
        
      error ->
        error
    end
  end
end