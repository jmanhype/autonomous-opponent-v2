defmodule AutonomousOpponentV2Core.AMCP.Memory.PNCounter do
  @moduledoc """
  A PN-Counter (Positive-Negative Counter) CRDT implementation.
  
  A PN-Counter combines two G-Counters (grow-only counters) to create a counter
  that supports both increment and decrement operations while maintaining
  eventual consistency in a distributed system.
  
  The counter maintains separate positive and negative counts for each replica,
  allowing conflict-free merges.
  """
  
  @type replica_id :: term()
  @type count_map :: %{replica_id() => non_neg_integer()}
  @type t :: %__MODULE__{
    replica_id: replica_id(),
    positive: count_map(),
    negative: count_map()
  }
  
  defstruct [:replica_id, :positive, :negative]
  
  @doc """
  Creates a new PN-Counter for the given replica.
  
  ## Parameters
    - replica_id: Unique identifier for this replica
    - initial_value: Optional initial value (defaults to 0)
  
  ## Examples
      iex> counter = PNCounter.new(:replica1)
      %PNCounter{replica_id: :replica1, positive: %{}, negative: %{}}
      
      iex> counter = PNCounter.new(:replica1, 10)
      %PNCounter{replica_id: :replica1, positive: %{replica1: 10}, negative: %{}}
  """
  @spec new(replica_id(), integer()) :: t()
  def new(replica_id, initial_value \\ 0) do
    {positive, negative} = 
      cond do
        initial_value > 0 ->
          {%{replica_id => initial_value}, %{}}
        initial_value < 0 ->
          {%{}, %{replica_id => abs(initial_value)}}
        true ->
          {%{}, %{}}
      end
    
    %__MODULE__{
      replica_id: replica_id,
      positive: positive,
      negative: negative
    }
  end
  
  @doc """
  Increments the counter by the given amount.
  
  ## Parameters
    - counter: The PN-Counter to increment
    - amount: The amount to increment by (must be positive)
  
  ## Examples
      iex> counter = PNCounter.new(:replica1)
      iex> counter = PNCounter.increment(counter, 5)
      iex> PNCounter.value(counter)
      5
  """
  @spec increment(t(), pos_integer()) :: t()
  def increment(%__MODULE__{} = counter, amount) when amount > 0 do
    current_positive = Map.get(counter.positive, counter.replica_id, 0)
    updated_positive = Map.put(counter.positive, counter.replica_id, current_positive + amount)
    
    %{counter | positive: updated_positive}
  end
  
  def increment(_counter, amount) when amount <= 0 do
    raise ArgumentError, "Increment amount must be positive, got: #{amount}"
  end
  
  @doc """
  Decrements the counter by the given amount.
  
  ## Parameters
    - counter: The PN-Counter to decrement
    - amount: The amount to decrement by (must be positive)
  
  ## Examples
      iex> counter = PNCounter.new(:replica1, 10)
      iex> counter = PNCounter.decrement(counter, 3)
      iex> PNCounter.value(counter)
      7
  """
  @spec decrement(t(), pos_integer()) :: t()
  def decrement(%__MODULE__{} = counter, amount) when amount > 0 do
    current_negative = Map.get(counter.negative, counter.replica_id, 0)
    updated_negative = Map.put(counter.negative, counter.replica_id, current_negative + amount)
    
    %{counter | negative: updated_negative}
  end
  
  def decrement(_counter, amount) when amount <= 0 do
    raise ArgumentError, "Decrement amount must be positive, got: #{amount}"
  end
  
  @doc """
  Returns the current value of the counter.
  
  The value is calculated as the sum of all positive counts minus
  the sum of all negative counts.
  
  ## Examples
      iex> counter = PNCounter.new(:replica1)
      iex> counter = PNCounter.increment(counter, 10)
      iex> counter = PNCounter.decrement(counter, 3)
      iex> PNCounter.value(counter)
      7
  """
  @spec value(t()) :: integer()
  def value(%__MODULE__{positive: positive, negative: negative}) do
    positive_sum = positive |> Map.values() |> Enum.sum()
    negative_sum = negative |> Map.values() |> Enum.sum()
    
    positive_sum - negative_sum
  end
  
  @doc """
  Merges two PN-Counters, taking the maximum count for each replica
  in both positive and negative maps.
  
  This operation is commutative, associative, and idempotent,
  making it a proper CRDT merge operation.
  
  ## Examples
      iex> counter1 = PNCounter.new(:replica1) |> PNCounter.increment(5)
      iex> counter2 = PNCounter.new(:replica2) |> PNCounter.increment(3)
      iex> merged = PNCounter.merge(counter1, counter2)
      iex> PNCounter.value(merged)
      8
  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{} = counter1, %__MODULE__{} = counter2) do
    merged_positive = merge_maps(counter1.positive, counter2.positive)
    merged_negative = merge_maps(counter1.negative, counter2.negative)
    
    %__MODULE__{
      replica_id: counter1.replica_id,
      positive: merged_positive,
      negative: merged_negative
    }
  end
  
  # Private helper to merge two count maps, taking the maximum value for each key
  @spec merge_maps(count_map(), count_map()) :: count_map()
  defp merge_maps(map1, map2) do
    Map.merge(map1, map2, fn _key, val1, val2 -> max(val1, val2) end)
  end
  
  @doc """
  Converts PN-Counter to map for serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{positive: positive, negative: negative}) do
    %{increments: positive, decrements: negative}
  end
  
  @doc """
  Reconstructs PN-Counter from serialized data.
  """
  @spec reconstruct(replica_id(), map(), map()) :: t()
  def reconstruct(replica_id, increments, decrements) do
    %__MODULE__{
      replica_id: replica_id,
      positive: increments,
      negative: decrements
    }
  end
end