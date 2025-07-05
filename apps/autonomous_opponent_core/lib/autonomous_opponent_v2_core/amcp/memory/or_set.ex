defmodule AutonomousOpponentV2Core.AMCP.Memory.ORSet do
  @moduledoc """
  Observed-Remove Set (OR-Set) CRDT implementation for aMCP.
  
  An OR-Set is a CRDT that supports both add and remove operations while maintaining
  consistency in a distributed environment. It achieves this by tracking unique
  identifiers for each addition, allowing elements to be added and removed concurrently
  without conflicts.
  
  Key properties:
  - Elements can be added and removed multiple times
  - Concurrent adds and removes are handled correctly
  - Merging two OR-Sets produces a consistent result
  - An element is in the set if it has been added at least once and not all additions have been removed
  
  Implementation uses a combination of:
  - adds: Map of element -> Set of unique identifiers (UIDs)
  - removes: Map of element -> Set of removed UIDs
  """
  
  defstruct [
    :node_id,
    :adds,
    :removes,
    :counter
  ]
  
  @type element :: term()
  @type uid :: {node_id :: String.t(), counter :: non_neg_integer()}
  @type t :: %__MODULE__{
    node_id: String.t(),
    adds: %{element() => MapSet.t(uid())},
    removes: %{element() => MapSet.t(uid())},
    counter: non_neg_integer()
  }
  
  @doc """
  Creates a new OR-Set.
  
  ## Parameters
    - node_id: Unique identifier for the node creating this OR-Set
    - initial_elements: Optional list of initial elements to add
  
  ## Examples
      iex> ORSet.new("node1", ["apple", "banana"])
      %ORSet{...}
  """
  @spec new(String.t(), list(element())) :: t()
  def new(node_id, initial_elements \\ []) do
    base_set = %__MODULE__{
      node_id: node_id,
      adds: %{},
      removes: %{},
      counter: 0
    }
    
    Enum.reduce(initial_elements, base_set, fn element, set ->
      add(set, element)
    end)
  end
  
  @doc """
  Adds an element to the OR-Set.
  
  ## Parameters
    - or_set: The OR-Set to add to
    - element: The element to add
  
  ## Examples
      iex> set = ORSet.new("node1", [])
      iex> ORSet.add(set, "apple")
      %ORSet{...}
  """
  @spec add(t(), element()) :: t()
  def add(%__MODULE__{} = or_set, element) do
    # Generate a unique identifier for this addition
    uid = {or_set.node_id, or_set.counter}
    
    # Add the UID to the adds map for this element
    new_adds = Map.update(
      or_set.adds,
      element,
      MapSet.new([uid]),
      fn existing_uids -> MapSet.put(existing_uids, uid) end
    )
    
    %{or_set | 
      adds: new_adds,
      counter: or_set.counter + 1
    }
  end
  
  @doc """
  Removes an element from the OR-Set.
  
  Only removes the element if it exists in the set. Removes all current
  occurrences of the element.
  
  ## Parameters
    - or_set: The OR-Set to remove from
    - element: The element to remove
  
  ## Examples
      iex> set = ORSet.new("node1", ["apple"])
      iex> ORSet.remove(set, "apple")
      %ORSet{...}
  """
  @spec remove(t(), element()) :: t()
  def remove(%__MODULE__{} = or_set, element) do
    case Map.get(or_set.adds, element) do
      nil ->
        # Element has never been added, nothing to remove
        or_set
        
      add_uids ->
        # Get the UIDs that are currently active (not already removed)
        remove_uids = Map.get(or_set.removes, element, MapSet.new())
        active_uids = MapSet.difference(add_uids, remove_uids)
        
        if MapSet.size(active_uids) > 0 do
          # Remove all active UIDs
          new_removes = Map.put(or_set.removes, element, MapSet.union(remove_uids, active_uids))
          %{or_set | removes: new_removes}
        else
          # No active UIDs to remove
          or_set
        end
    end
  end
  
  @doc """
  Returns the current value of the OR-Set as a list.
  
  An element is included in the result if it has at least one UID that
  has been added but not removed.
  
  ## Parameters
    - or_set: The OR-Set to get the value from
  
  ## Examples
      iex> set = ORSet.new("node1", ["apple", "banana"])
      iex> ORSet.value(set)
      ["apple", "banana"]
  """
  @spec value(t()) :: list(element())
  def value(%__MODULE__{} = or_set) do
    or_set.adds
    |> Enum.filter(fn {element, add_uids} ->
      remove_uids = Map.get(or_set.removes, element, MapSet.new())
      active_uids = MapSet.difference(add_uids, remove_uids)
      MapSet.size(active_uids) > 0
    end)
    |> Enum.map(fn {element, _} -> element end)
    |> Enum.sort()
  end
  
  @doc """
  Returns the number of elements in the OR-Set.
  
  ## Parameters
    - or_set: The OR-Set to get the size from
  
  ## Examples
      iex> set = ORSet.new("node1", ["apple", "banana"])
      iex> ORSet.size(set)
      2
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{} = or_set) do
    or_set
    |> value()
    |> length()
  end
  
  @doc """
  Merges two OR-Sets, producing a new OR-Set that contains the combined state.
  
  The merge operation:
  - Combines all adds from both sets
  - Combines all removes from both sets
  - Uses the maximum counter value to avoid UID collisions
  
  ## Parameters
    - or_set1: The first OR-Set
    - or_set2: The second OR-Set
  
  ## Examples
      iex> set1 = ORSet.new("node1", ["apple"])
      iex> set2 = ORSet.new("node2", ["banana"])
      iex> merged = ORSet.merge(set1, set2)
      iex> ORSet.value(merged)
      ["apple", "banana"]
  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{} = or_set1, %__MODULE__{} = or_set2) do
    # Merge adds maps
    merged_adds = merge_uid_maps(or_set1.adds, or_set2.adds)
    
    # Merge removes maps
    merged_removes = merge_uid_maps(or_set1.removes, or_set2.removes)
    
    # Use the maximum counter to avoid collisions
    max_counter = max(or_set1.counter, or_set2.counter)
    
    %__MODULE__{
      node_id: or_set1.node_id,  # Keep the first set's node_id
      adds: merged_adds,
      removes: merged_removes,
      counter: max_counter
    }
  end
  
  # Private helper functions
  
  defp merge_uid_maps(map1, map2) do
    Map.merge(map1, map2, fn _element, uids1, uids2 ->
      MapSet.union(uids1, uids2)
    end)
  end
end