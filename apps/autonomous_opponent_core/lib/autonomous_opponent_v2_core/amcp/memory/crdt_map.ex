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
  @spec new(actor_id()) :: t()
  @spec new(actor_id(), clock() | map()) :: t()
  
  def new(actor_id, initial_clock_or_map \\ 0)
  
  def new(actor_id, initial_clock) when is_integer(initial_clock) do
    %__MODULE__{
      actor_id: actor_id,
      clock: initial_clock,
      entries: %{}
    }
  end
  
  def new(actor_id, initial_map) when is_map(initial_map) do
    base_map = new(actor_id, 0)
    
    Enum.reduce(initial_map, base_map, fn {key, value}, acc ->
      put(acc, key, value)
    end)
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
  @spec put(t(), term(), term()) :: t()
  @spec put(t(), term(), term(), clock() | term()) :: t()
  
  def put(map, key, value, clock_or_subkey \\ nil)
  
  def put(%__MODULE__{} = map, key, value, clock) when is_integer(clock) or is_nil(clock) do
    new_clock = clock || map.clock + 1
    
    %{map | 
      clock: new_clock,
      entries: Map.put(map.entries, key, {value, new_clock, map.actor_id})
    }
  end
  
  def put(%__MODULE__{} = map, key, subkey, value) do
    # Get current value for the key, default to empty map
    current_value = case Map.get(map.entries, key) do
      {val, _, _} when is_map(val) -> val
      _ -> %{}
    end
    
    # Update the nested map
    updated_value = Map.put(current_value, subkey, value)
    
    # Put the updated nested map back
    put(map, key, updated_value)
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
  @spec remove(t(), term()) :: t()
  @spec remove(t(), term(), clock() | term()) :: t()
  
  def remove(map, key, clock_or_subkey \\ nil)
  
  def remove(%__MODULE__{} = map, key, clock) when is_integer(clock) or is_nil(clock) do
    new_clock = clock || map.clock + 1
    
    %{map | 
      clock: new_clock,
      entries: Map.put(map.entries, key, {nil, new_clock, map.actor_id})
    }
  end
  
  def remove(%__MODULE__{} = map, key, subkey) do
    # Get current value for the key
    case Map.get(map.entries, key) do
      {val, _, _} when is_map(val) ->
        # Remove the subkey
        updated_value = Map.delete(val, subkey)
        
        # If the map is now empty, remove the entire key
        if map_size(updated_value) == 0 do
          remove(map, key)
        else
          put(map, key, updated_value)
        end
        
      _ ->
        # Key doesn't exist or isn't a map, nothing to do
        map
    end
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
  
  
  @doc """
  Converts CRDT Map to map for serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = map) do
    value(map)
  end
  
  @doc """
  Reconstructs CRDT Map from serialized data.
  """
  @spec reconstruct(actor_id(), map()) :: t()
  def reconstruct(actor_id, data) do
    base_map = new(actor_id)
    
    Enum.reduce(data || %{}, base_map, fn {key, value}, acc ->
      put(acc, key, value)
    end)
  end
  
end