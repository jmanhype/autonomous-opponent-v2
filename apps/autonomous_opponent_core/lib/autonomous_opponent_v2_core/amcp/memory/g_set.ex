defmodule AutonomousOpponentV2Core.AMCP.Memory.GSet do
  @moduledoc """
  A Grow-only Set (G-Set) CRDT implementation.
  
  G-Set is a simple CRDT that only supports adding elements.
  Once an element is added, it cannot be removed.
  Merging two G-Sets results in the union of both sets.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          elements: MapSet.t()
        }

  defstruct [:id, elements: MapSet.new()]

  @doc """
  Creates a new G-Set with the given ID.

  ## Examples

      iex> gset = GSet.new("node1")
      %GSet{id: "node1", elements: #MapSet<[]>}
  """
  @spec new(String.t()) :: t()
  def new(id) when is_binary(id) do
    %__MODULE__{id: id, elements: MapSet.new()}
  end

  @doc """
  Adds an element to the G-Set.

  ## Examples

      iex> gset = GSet.new("node1")
      iex> gset = GSet.add(gset, "apple")
      iex> GSet.value(gset)
      #MapSet<["apple"]>
  """
  @spec add(t(), any()) :: t()
  def add(%__MODULE__{elements: elements} = gset, element) do
    %{gset | elements: MapSet.put(elements, element)}
  end

  @doc """
  Returns the current value of the G-Set as a MapSet.

  ## Examples

      iex> gset = GSet.new("node1")
      iex> gset = GSet.add(gset, "apple")
      iex> gset = GSet.add(gset, "banana")
      iex> GSet.value(gset)
      #MapSet<["apple", "banana"]>
  """
  @spec value(t()) :: MapSet.t()
  def value(%__MODULE__{elements: elements}) do
    elements
  end

  @doc """
  Returns the number of elements in the G-Set.

  ## Examples

      iex> gset = GSet.new("node1")
      iex> gset = GSet.add(gset, "apple")
      iex> gset = GSet.add(gset, "banana")
      iex> GSet.size(gset)
      2
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{elements: elements}) do
    MapSet.size(elements)
  end

  @doc """
  Merges two G-Sets by computing their union.
  
  The merge operation is commutative, associative, and idempotent,
  making G-Set a valid CRDT.

  ## Examples

      iex> gset1 = GSet.new("node1") |> GSet.add("apple") |> GSet.add("banana")
      iex> gset2 = GSet.new("node2") |> GSet.add("banana") |> GSet.add("cherry")
      iex> merged = GSet.merge(gset1, gset2)
      iex> GSet.value(merged)
      #MapSet<["apple", "banana", "cherry"]>
  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{id: id1, elements: elements1}, %__MODULE__{elements: elements2}) do
    %__MODULE__{
      id: id1,
      elements: MapSet.union(elements1, elements2)
    }
  end
end