defmodule AutonomousOpponentV2Core.AMCP.Memory.LWWRegister do
  @moduledoc """
  Last-Write-Wins Register (LWW-Register) CRDT implementation.
  
  A LWW-Register is a CRDT that maintains a single value with a timestamp.
  When merging, the value with the latest timestamp wins. In case of
  timestamp ties, a deterministic tiebreaker (node_id comparison) is used.
  """

  @type t :: %__MODULE__{
          value: any(),
          timestamp: integer(),
          node_id: String.t()
        }

  defstruct [:value, :timestamp, :node_id]

  @doc """
  Creates a new LWW-Register with an initial value and node identifier.

  ## Examples

      iex> reg = LWWRegister.new("initial_value", "node1")
      iex> reg.value
      "initial_value"
  """
  @spec new(any(), String.t()) :: t()
  def new(initial_value, node_id) when is_binary(node_id) do
    %__MODULE__{
      value: initial_value,
      timestamp: System.system_time(:nanosecond),
      node_id: node_id
    }
  end

  @doc """
  Sets a new value in the register with current timestamp.

  ## Examples

      iex> reg = LWWRegister.new("old", "node1")
      iex> updated = LWWRegister.set(reg, "new")
      iex> updated.value
      "new"
  """
  @spec set(t(), any()) :: t()
  def set(%__MODULE__{node_id: node_id} = _register, new_value) do
    %__MODULE__{
      value: new_value,
      timestamp: System.system_time(:nanosecond),
      node_id: node_id
    }
  end

  @doc """
  Returns the current value of the register.

  ## Examples

      iex> reg = LWWRegister.new("hello", "node1")
      iex> LWWRegister.value(reg)
      "hello"
  """
  @spec value(t()) :: any()
  def value(%__MODULE__{value: val}), do: val

  @doc """
  Merges two LWW-Registers, keeping the value with the latest timestamp.
  
  In case of timestamp ties, the value from the register with the
  lexicographically larger node_id wins (deterministic tiebreaker).

  ## Examples

      iex> reg1 = LWWRegister.new("value1", "node1")
      iex> Process.sleep(1) # Ensure different timestamp
      iex> reg2 = LWWRegister.new("value2", "node2")
      iex> merged = LWWRegister.merge(reg1, reg2)
      iex> merged.value
      "value2"
  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{} = reg1, %__MODULE__{} = reg2) do
    cond do
      reg1.timestamp > reg2.timestamp ->
        reg1

      reg2.timestamp > reg1.timestamp ->
        reg2

      # Timestamps are equal, use node_id as tiebreaker
      reg1.node_id >= reg2.node_id ->
        reg1

      true ->
        reg2
    end
  end
  
  @doc """
  Converts LWW-Register to map for serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{value: value, timestamp: timestamp}) do
    %{value: value, timestamp: timestamp}
  end
  
  @doc """
  Reconstructs LWW-Register from serialized data.
  """
  @spec reconstruct(String.t(), any(), integer()) :: t()
  def reconstruct(node_id, value, timestamp) do
    %__MODULE__{
      node_id: node_id,
      value: value,
      timestamp: timestamp
    }
  end
end