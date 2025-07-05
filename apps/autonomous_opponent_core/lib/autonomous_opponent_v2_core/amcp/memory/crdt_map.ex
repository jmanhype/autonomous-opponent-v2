defmodule AutonomousOpponentV2Core.AMCP.Memory.CRDTMap do
  @moduledoc """
  A basic implementation of a CRDT (Conflict-free Replicated Data Type) Map.
  
  This implementation uses a state-based CRDT approach with vector clocks
  for conflict resolution. Each entry in the map is tagged with a logical
  timestamp to enable deterministic merging.
  """

  @type actor_id :: term()
  @type clock :: non_neg_integer()
  @type entry :: {term(), clock(), actor_id()}
  @type t :: %__MODULE__{
          actor_id: actor_id(),
          clock: clock(),
          entries: %{optional(term()) => entry()}
        }

  defstruct actor_id: nil,
            clock: 0,
            entries: %{}

  @doc """
  Creates a new CRDT Map with the given actor ID and optional initial clock value.
  
  ## Examples
  
      iex> CRDTMap.new(:node1)
      %CRDTMap{actor_id: :node1, clock: 0, entries: %{}}
      
      iex> CRDTMap.new(:node2, 10)
      %CRDTMap{actor_id: :node2, clock: 10, entries: %{}}
  """
  @spec new(actor_id(), clock()) :: t()
  def new(actor_id, initial_clock \\ 0) do
    %__MODULE__{
      actor_id: actor_id,
      clock: initial_clock,
      entries: %{}
    }
  end

  @doc """
  Adds or updates a key-value pair in the CRDT Map.
  
  The operation increments the actor's logical clock and tags the entry
  with the new timestamp and actor ID for conflict resolution during merges.
  
  ## Examples
  
      iex> map = CRDTMap.new(:node1)
      iex> map = CRDTMap.put(map, :key1, "value1")
      iex> CRDTMap.value(map)
      %{key1: "value1"}
  """
  @spec put(t(), term(), term(), clock()) :: t()
  def put(%__MODULE__{} = map, key, value, clock \\ nil) do
    new_clock = clock || map.clock + 1
    
    %{map | 
      clock: new_clock,
      entries: Map.put(map.entries, key, {value, new_clock, map.actor_id})
    }
  end

  @doc """
  Removes a key from the CRDT Map.
  
  In CRDT semantics, removal is typically implemented as a tombstone
  (a special marker indicating deletion). This implementation uses nil
  as the tombstone value.
  
  ## Examples
  
      iex> map = CRDTMap.new(:node1)
      iex> map = CRDTMap.put(map, :key1, "value1")
      iex> map = CRDTMap.remove(map, :key1)
      iex> CRDTMap.value(map)
      %{}
  """
  @spec remove(t(), term(), clock()) :: t()
  def remove(%__MODULE__{} = map, key, clock \\ nil) do
    new_clock = clock || map.clock + 1
    
    %{map | 
      clock: new_clock,
      entries: Map.put(map.entries, key, {nil, new_clock, map.actor_id})
    }
  end

  @doc """
  Returns the current value of the CRDT Map as a regular Elixir map.
  
  Filters out tombstoned (nil) values to present only active entries.
  
  ## Examples
  
      iex> map = CRDTMap.new(:node1)
      iex> map = CRDTMap.put(map, :a, 1)
      iex> map = CRDTMap.put(map, :b, 2)
      iex> CRDTMap.value(map)
      %{a: 1, b: 2}
  """
  @spec value(t()) :: map()
  def value(%__MODULE__{entries: entries}) do
    entries
    |> Enum.reduce(%{}, fn
      {_key, {nil, _clock, _actor}}, acc -> acc
      {key, {value, _clock, _actor}}, acc -> Map.put(acc, key, value)
    end)
  end

  @doc """
  Returns the number of active (non-tombstoned) entries in the CRDT Map.
  
  ## Examples
  
      iex> map = CRDTMap.new(:node1)
      iex> map = CRDTMap.put(map, :a, 1)
      iex> map = CRDTMap.put(map, :b, 2)
      iex> CRDTMap.size(map)
      2
      iex> map = CRDTMap.remove(map, :a)
      iex> CRDTMap.size(map)
      1
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{} = map) do
    map
    |> value()
    |> map_size()
  end

  @doc """
  Merges two CRDT Maps into a single consistent state.
  
  The merge operation is commutative, associative, and idempotent, making it
  suitable for distributed systems. Conflicts are resolved using Last-Write-Wins
  based on logical timestamps, with actor ID as a tiebreaker.
  
  ## Examples
  
      iex> map1 = CRDTMap.new(:node1) |> CRDTMap.put(:key, "value1")
      iex> map2 = CRDTMap.new(:node2) |> CRDTMap.put(:key, "value2")
      iex> merged = CRDTMap.merge(map1, map2)
      iex> CRDTMap.value(merged)
      %{key: "value2"}  # Assuming node2's clock was higher
  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{} = map1, %__MODULE__{} = map2) do
    merged_entries = 
      Map.merge(map1.entries, map2.entries, fn _key, entry1, entry2 ->
        resolve_conflict(entry1, entry2)
      end)
    
    %__MODULE__{
      actor_id: map1.actor_id,
      clock: max(map1.clock, map2.clock),
      entries: merged_entries
    }
  end

  # Private helper function to resolve conflicts between entries
  defp resolve_conflict({_value1, clock1, actor1} = entry1, {_value2, clock2, actor2} = entry2) do
    cond do
      clock1 > clock2 -> entry1
      clock2 > clock1 -> entry2
      actor1 > actor2 -> entry1
      true -> entry2
    end
  end
end