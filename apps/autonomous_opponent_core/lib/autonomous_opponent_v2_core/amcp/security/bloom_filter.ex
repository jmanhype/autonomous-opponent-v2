defmodule AutonomousOpponentV2Core.AMCP.Security.BloomFilter do
  @moduledoc """
  High-performance Bloom Filter implementation for aMCP security.
  
  Provides probabilistic membership testing with configurable false positive rates.
  Used for rapid nonce duplicate detection without heavy memory cost.
  
  Features:
  - Configurable size and false positive rate
  - Multiple hash functions for better distribution
  - Memory-efficient bitset implementation
  - Thread-safe operations
  """
  
  use Bitwise
  require Logger
  
  defstruct [
    :bitset,
    :size,
    :hash_count,
    :expected_items,
    :false_positive_rate,
    :item_count
  ]
  
  @type t :: %__MODULE__{}
  
  @doc """
  Creates a new Bloom filter.
  
  Parameters:
  - expected_items: Number of items expected to be added
  - false_positive_rate: Desired false positive rate (0.0 to 1.0)
  
  Example:
      iex> BloomFilter.new(1_000_000, 0.001)
  """
  def new(expected_items, false_positive_rate \\ 0.01) 
      when expected_items > 0 and false_positive_rate > 0 and false_positive_rate < 1 do
    
    # Calculate optimal filter size
    size = optimal_size(expected_items, false_positive_rate)
    
    # Calculate optimal number of hash functions
    hash_count = optimal_hash_count(size, expected_items)
    
    # Initialize bitset
    bitset = :array.new(size, default: 0)
    
    %__MODULE__{
      bitset: bitset,
      size: size,
      hash_count: hash_count,
      expected_items: expected_items,
      false_positive_rate: false_positive_rate,
      item_count: 0
    }
  end
  
  @doc """
  Adds an item to the Bloom filter.
  """
  def add(%__MODULE__{} = bloom_filter, item) do
    hashes = generate_hashes(item, bloom_filter.hash_count, bloom_filter.size)
    
    new_bitset = Enum.reduce(hashes, bloom_filter.bitset, fn index, bitset ->
      :array.set(index, 1, bitset)
    end)
    
    %{bloom_filter |
      bitset: new_bitset,
      item_count: bloom_filter.item_count + 1
    }
  end
  
  @doc """
  Checks if an item might be in the Bloom filter.
  
  Returns:
  - true: Item might be in the set (could be false positive)
  - false: Item is definitely not in the set
  """
  def contains?(%__MODULE__{} = bloom_filter, item) do
    hashes = generate_hashes(item, bloom_filter.hash_count, bloom_filter.size)
    
    Enum.all?(hashes, fn index ->
      :array.get(index, bloom_filter.bitset) == 1
    end)
  end
  
  @doc """
  Gets the estimated number of items in the filter.
  """
  def estimated_count(%__MODULE__{} = bloom_filter) do
    # Count set bits
    set_bits = count_set_bits(bloom_filter.bitset, bloom_filter.size)
    
    if set_bits == 0 do
      0
    else
      # Estimate using the formula: -m * ln(1 - X/m) / k
      # where m = filter size, X = set bits, k = hash count
      m = bloom_filter.size
      k = bloom_filter.hash_count
      x = set_bits
      
      estimated = -m * :math.log(1 - x / m) / k
      round(estimated)
    end
  end
  
  @doc """
  Calculates the current false positive rate.
  """
  def false_positive_rate(%__MODULE__{} = bloom_filter) do
    set_bits = count_set_bits(bloom_filter.bitset, bloom_filter.size)
    bit_ratio = set_bits / bloom_filter.size
    
    # False positive rate = (1 - e^(-k * n / m))^k
    # where k = hash count, n = items added, m = filter size
    k = bloom_filter.hash_count
    n = bloom_filter.item_count
    m = bloom_filter.size
    
    rate = :math.pow(1 - :math.exp(-k * n / m), k)
    min(rate, 1.0)
  end
  
  @doc """
  Merges two Bloom filters (they must have the same parameters).
  """
  def merge(%__MODULE__{size: size, hash_count: hash_count} = filter1,
            %__MODULE__{size: size, hash_count: hash_count} = filter2) do
    
    new_bitset = merge_bitsets(filter1.bitset, filter2.bitset, size)
    
    %{filter1 |
      bitset: new_bitset,
      item_count: filter1.item_count + filter2.item_count
    }
  end
  
  def merge(%__MODULE__{}, %__MODULE__{}) do
    {:error, :incompatible_filters}
  end
  
  @doc """
  Clears the Bloom filter.
  """
  def clear(%__MODULE__{} = bloom_filter) do
    new_bitset = :array.new(bloom_filter.size, default: 0)
    %{bloom_filter | bitset: new_bitset, item_count: 0}
  end
  
  @doc """
  Gets filter statistics.
  """
  def stats(%__MODULE__{} = bloom_filter) do
    set_bits = count_set_bits(bloom_filter.bitset, bloom_filter.size)
    
    %{
      size: bloom_filter.size,
      hash_count: bloom_filter.hash_count,
      expected_items: bloom_filter.expected_items,
      item_count: bloom_filter.item_count,
      set_bits: set_bits,
      bit_ratio: set_bits / bloom_filter.size,
      expected_false_positive_rate: bloom_filter.false_positive_rate,
      actual_false_positive_rate: false_positive_rate(bloom_filter),
      memory_usage_bits: bloom_filter.size,
      memory_usage_bytes: div(bloom_filter.size, 8)
    }
  end
  
  # Private Functions
  
  defp optimal_size(expected_items, false_positive_rate) do
    # m = -(n * ln(p)) / (ln(2)^2)
    # where n = expected items, p = false positive rate
    size = -(expected_items * :math.log(false_positive_rate)) / (:math.log(2) * :math.log(2))
    round(size) |> max(1)
  end
  
  defp optimal_hash_count(size, expected_items) do
    # k = (m / n) * ln(2)
    # where m = filter size, n = expected items
    hash_count = (size / expected_items) * :math.log(2)
    round(hash_count) |> max(1) |> min(10)  # Practical limit
  end
  
  defp generate_hashes(item, hash_count, size) do
    # Convert item to binary for hashing
    binary_item = case item do
      binary when is_binary(binary) -> binary
      atom when is_atom(atom) -> Atom.to_string(atom)
      other -> inspect(other)
    end
    
    # Generate multiple hashes using different methods
    base_hash = :erlang.phash2(binary_item, size)
    secondary_hash = :crypto.hash(:sha256, binary_item) |> :binary.bin_to_list() |> Enum.take(4) |> hash_to_int()
    
    # Generate hash_count different hash values
    for i <- 0..(hash_count - 1) do
      # Double hashing: h1(x) + i * h2(x)
      hash_value = (base_hash + i * secondary_hash) |> abs()
      rem(hash_value, size)
    end
  end
  
  defp hash_to_int([a, b, c, d]) do
    (a <<< 24) ||| (b <<< 16) ||| (c <<< 8) ||| d
  end
  
  defp count_set_bits(bitset, size) do
    0..(size - 1)
    |> Enum.reduce(0, fn index, acc ->
      case :array.get(index, bitset) do
        1 -> acc + 1
        _ -> acc
      end
    end)
  end
  
  defp merge_bitsets(bitset1, bitset2, size) do
    0..(size - 1)
    |> Enum.reduce(:array.new(size, default: 0), fn index, acc ->
      bit1 = :array.get(index, bitset1)
      bit2 = :array.get(index, bitset2)
      merged_bit = bit1 ||| bit2
      :array.set(index, merged_bit, acc)
    end)
  end
  
  @doc """
  Creates a Bloom filter optimized for nonce validation.
  
  Optimized for:
  - 1M expected nonces
  - 0.1% false positive rate
  - High throughput validation
  """
  def new_for_nonces do
    new(1_000_000, 0.001)
  end
  
  @doc """
  Creates a small Bloom filter for testing.
  """
  def new_for_testing do
    new(1000, 0.01)
  end
  
  @doc """
  Bulk add multiple items to the filter.
  """
  def add_many(%__MODULE__{} = bloom_filter, items) when is_list(items) do
    Enum.reduce(items, bloom_filter, &add(&2, &1))
  end
  
  @doc """
  Checks multiple items at once.
  """
  def contains_any?(%__MODULE__{} = bloom_filter, items) when is_list(items) do
    Enum.any?(items, &contains?(bloom_filter, &1))
  end
  
  @doc """
  Checks if all items are contained.
  """
  def contains_all?(%__MODULE__{} = bloom_filter, items) when is_list(items) do
    Enum.all?(items, &contains?(bloom_filter, &1))
  end
  
  @doc """
  Serializes the Bloom filter to binary for storage.
  """
  def serialize(%__MODULE__{} = bloom_filter) do
    bitset_data = :array.to_list(bloom_filter.bitset)
    
    data = %{
      bitset: bitset_data,
      size: bloom_filter.size,
      hash_count: bloom_filter.hash_count,
      expected_items: bloom_filter.expected_items,
      false_positive_rate: bloom_filter.false_positive_rate,
      item_count: bloom_filter.item_count
    }
    
    :erlang.term_to_binary(data)
  end
  
  @doc """
  Deserializes a Bloom filter from binary.
  """
  def deserialize(binary) when is_binary(binary) do
    try do
      data = :erlang.binary_to_term(binary)
      bitset = :array.from_list(data.bitset)
      
      {:ok, %__MODULE__{
        bitset: bitset,
        size: data.size,
        hash_count: data.hash_count,
        expected_items: data.expected_items,
        false_positive_rate: data.false_positive_rate,
        item_count: data.item_count
      }}
    rescue
      _ -> {:error, :invalid_binary}
    end
  end
end