defmodule AutonomousOpponentV2Core.Core.HybridLogicalClock do
  @moduledoc """
  Hybrid Logical Clock (HLC) implementation for deterministic, causally-ordered timestamps.
  
  This module provides a centralized clock that combines physical time with logical counters
  to ensure total ordering of events even when physical clocks may have slight differences.
  
  ## Features
  
  - Combines wall-clock time with logical counters
  - Generates content-based IDs for events
  - Provides total ordering for distributed events
  - Thread-safe with proper synchronization
  - Handles clock skew gracefully
  
  ## Usage
  
      # Get current HLC timestamp
      {:ok, hlc} = HybridLogicalClock.now()
      
      # Generate event ID with content
      {:ok, event_id} = HybridLogicalClock.event_id(%{type: :vsm_event, data: "..."})
      
      # Compare timestamps
      HybridLogicalClock.compare(hlc1, hlc2)
      
      # Update clock with remote timestamp
      {:ok, updated} = HybridLogicalClock.update(remote_hlc)
  """
  
  use GenServer
  require Logger
  
  @type hlc_timestamp :: %{
    physical: non_neg_integer(),
    logical: non_neg_integer(),
    node_id: String.t()
  }
  
  @type comparison :: :lt | :eq | :gt
  
  # Maximum clock drift allowed (in milliseconds)
  @max_drift 60_000
  
  # Node ID for this instance
  @node_id_key :hlc_node_id
  
  defmodule State do
    @moduledoc false
    defstruct [
      :node_id,
      :last_physical,
      :logical_counter,
      :max_offset
    ]
  end
  
  # Client API
  
  @doc """
  Starts the HLC GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Gets the current HLC timestamp.
  """
  @spec now() :: {:ok, hlc_timestamp()} | {:error, term()}
  def now do
    GenServer.call(__MODULE__, :now)
  end
  
  @doc """
  Updates the clock with a remote timestamp, ensuring monotonicity.
  """
  @spec update(hlc_timestamp()) :: {:ok, hlc_timestamp()} | {:error, term()}
  def update(remote_hlc) do
    GenServer.call(__MODULE__, {:update, remote_hlc})
  end
  
  @doc """
  Generates a content-based event ID using HLC timestamp and event data.
  """
  @spec event_id(map()) :: {:ok, String.t()} | {:error, term()}
  def event_id(event_data) do
    case now() do
      {:ok, hlc} ->
        # Create deterministic ID from timestamp and content
        content_hash = :crypto.hash(:sha256, :erlang.term_to_binary(event_data))
        |> Base.encode16(case: :lower)
        |> String.slice(0..7)
        
        id = "#{hlc.physical}-#{hlc.logical}-#{hlc.node_id}-#{content_hash}"
        {:ok, id}
        
      error -> error
    end
  end
  
  @doc """
  Compares two HLC timestamps for ordering.
  Returns :lt, :eq, or :gt.
  """
  @spec compare(hlc_timestamp(), hlc_timestamp()) :: comparison()
  def compare(%{physical: p1, logical: l1, node_id: n1}, 
              %{physical: p2, logical: l2, node_id: n2}) do
    cond do
      p1 < p2 -> :lt
      p1 > p2 -> :gt
      l1 < l2 -> :lt
      l1 > l2 -> :gt
      n1 < n2 -> :lt
      n1 > n2 -> :gt
      true -> :eq
    end
  end
  
  @doc """
  Checks if first timestamp is before second.
  """
  @spec before?(hlc_timestamp(), hlc_timestamp()) :: boolean()
  def before?(hlc1, hlc2), do: compare(hlc1, hlc2) == :lt
  
  @doc """
  Checks if first timestamp is after second.
  """
  @spec after?(hlc_timestamp(), hlc_timestamp()) :: boolean()
  def after?(hlc1, hlc2), do: compare(hlc1, hlc2) == :gt
  
  @doc """
  Checks if timestamps are equal.
  """
  @spec equal?(hlc_timestamp(), hlc_timestamp()) :: boolean()
  def equal?(hlc1, hlc2), do: compare(hlc1, hlc2) == :eq
  
  @doc """
  Converts HLC timestamp to ISO8601 string with logical counter.
  """
  @spec to_string(hlc_timestamp()) :: String.t()
  def to_string(%{physical: physical, logical: logical, node_id: node_id}) do
    dt = DateTime.from_unix!(physical, :millisecond)
    "#{DateTime.to_iso8601(dt)}.#{logical}@#{node_id}"
  end
  
  @doc """
  Parses HLC timestamp from string format.
  """
  @spec from_string(String.t()) :: {:ok, hlc_timestamp()} | {:error, :invalid_format}
  def from_string(str) do
    with [timestamp_part, node_id] <- String.split(str, "@"),
         # Find the last dot to separate logical counter
         parts <- String.split(timestamp_part, "."),
         true <- length(parts) >= 2,
         {logical_str, iso_parts} <- List.pop_at(parts, -1),
         iso_part <- Enum.join(iso_parts, "."),
         {:ok, datetime, _} <- DateTime.from_iso8601(iso_part),
         {logical, ""} <- Integer.parse(logical_str) do
      {:ok, %{
        physical: DateTime.to_unix(datetime, :millisecond),
        logical: logical,
        node_id: node_id
      }}
    else
      _ -> {:error, :invalid_format}
    end
  end
  
  @doc """
  Gets or generates a unique node ID for this instance.
  """
  @spec node_id() :: String.t()
  def node_id do
    case :persistent_term.get(@node_id_key, nil) do
      nil ->
        # Generate node ID from machine characteristics
        node_id = generate_node_id()
        :persistent_term.put(@node_id_key, node_id)
        node_id
        
      id -> id
    end
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    node_id = Keyword.get(opts, :node_id, node_id())
    max_offset = Keyword.get(opts, :max_offset, @max_drift)
    
    state = %State{
      node_id: node_id,
      last_physical: 0,
      logical_counter: 0,
      max_offset: max_offset
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:now, _from, state) do
    now_ms = System.system_time(:millisecond)
    
    {physical, logical} = 
      if now_ms > state.last_physical do
        # Physical clock has advanced
        {now_ms, 0}
      else
        # Physical clock same or behind, increment logical
        {state.last_physical, state.logical_counter + 1}
      end
    
    hlc = %{
      physical: physical,
      logical: logical,
      node_id: state.node_id
    }
    
    new_state = %{state | 
      last_physical: physical,
      logical_counter: logical
    }
    
    {:reply, {:ok, hlc}, new_state}
  end
  
  @impl true
  def handle_call({:update, remote_hlc}, _from, state) do
    now_ms = System.system_time(:millisecond)
    
    # Check for excessive drift
    if abs(remote_hlc.physical - now_ms) > state.max_offset do
      {:reply, {:error, :clock_drift_exceeded}, state}
    else
      # Calculate new timestamp
      {physical, logical} = 
        cond do
          # Local physical time is ahead
          now_ms > remote_hlc.physical and now_ms > state.last_physical ->
            {now_ms, 0}
            
          # Remote physical time is ahead
          remote_hlc.physical > now_ms and remote_hlc.physical > state.last_physical ->
            {remote_hlc.physical, remote_hlc.logical + 1}
            
          # Same physical time, use max logical + 1
          true ->
            max_physical = Enum.max([now_ms, remote_hlc.physical, state.last_physical])
            max_logical = 
              if max_physical == state.last_physical do
                Enum.max([remote_hlc.logical, state.logical_counter]) + 1
              else
                0
              end
            {max_physical, max_logical}
        end
      
      hlc = %{
        physical: physical,
        logical: logical,
        node_id: state.node_id
      }
      
      new_state = %{state |
        last_physical: physical,
        logical_counter: logical
      }
      
      {:reply, {:ok, hlc}, new_state}
    end
  end
  
  # Private functions
  
  defp generate_node_id do
    # Combine hostname, PID, and random component for uniqueness
    hostname = :inet.gethostname() |> elem(1) |> List.to_string()
    pid_hash = :erlang.phash2(self())
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    
    "#{hostname}-#{pid_hash}-#{random}"
    |> String.slice(0..15)  # Limit length
  end
end