defmodule AutonomousOpponentV2Core.VSM.Clock do
  @moduledoc """
  VSM-specific clock utilities built on top of Hybrid Logical Clock.
  
  This module provides convenience functions for VSM operations while maintaining
  the deterministic, causally-ordered timestamps required for proper VSM functioning.
  
  ## Usage
  
      # Get VSM timestamp
      {:ok, timestamp} = VSM.Clock.now()
      
      # Create event with VSM timestamp
      {:ok, event_id} = VSM.Clock.event_id(:s1_operation, %{data: "..."})
      
      # Order VSM events
      VSM.Clock.order_events([event1, event2, event3])
  """
  
  alias AutonomousOpponentV2Core.Core.HybridLogicalClock
  
  @type vsm_event :: %{
    id: String.t(),
    subsystem: atom(),
    type: atom(),
    data: any(),
    timestamp: HybridLogicalClock.hlc_timestamp(),
    created_at: String.t()
  }
  
  @doc """
  Gets current VSM timestamp using HLC.
  """
  @spec now() :: {:ok, HybridLogicalClock.hlc_timestamp()} | {:error, term()}
  def now do
    HybridLogicalClock.now()
  end
  
  @doc """
  Creates a VSM event ID with subsystem and type information.
  """
  @spec event_id(atom(), atom(), any()) :: {:ok, String.t()} | {:error, term()}
  def event_id(subsystem, type, data \\ nil) do
    event_data = %{
      subsystem: subsystem,
      type: type,
      data: data,
      vsm_context: true
    }
    
    HybridLogicalClock.event_id(event_data)
  end
  
  @doc """
  Creates a complete VSM event structure with HLC timestamp.
  """
  @spec create_event(atom(), atom(), any()) :: {:ok, vsm_event()} | {:error, term()}
  def create_event(subsystem, type, data) do
    with {:ok, timestamp} <- now(),
         {:ok, event_id} <- event_id(subsystem, type, data) do
      event = %{
        id: event_id,
        subsystem: subsystem,
        type: type,
        data: data,
        timestamp: timestamp,
        created_at: HybridLogicalClock.to_string(timestamp)
      }
      
      {:ok, event}
    end
  end
  
  @doc """
  Orders a list of VSM events by their HLC timestamps.
  """
  @spec order_events([vsm_event()]) :: [vsm_event()]
  def order_events(events) when is_list(events) do
    Enum.sort(events, fn event1, event2 ->
      HybridLogicalClock.before?(event1.timestamp, event2.timestamp)
    end)
  end
  
  @doc """
  Finds the latest event in a collection based on HLC timestamp.
  """
  @spec latest_event([vsm_event()]) :: vsm_event() | nil
  def latest_event([]), do: nil
  def latest_event([event]), do: event
  def latest_event(events) when is_list(events) do
    Enum.max_by(events, fn event ->
      {event.timestamp.physical, event.timestamp.logical, event.timestamp.node_id}
    end)
  end
  
  @doc """
  Finds the earliest event in a collection based on HLC timestamp.
  """
  @spec earliest_event([vsm_event()]) :: vsm_event() | nil
  def earliest_event([]), do: nil
  def earliest_event([event]), do: event
  def earliest_event(events) when is_list(events) do
    Enum.min_by(events, fn event ->
      {event.timestamp.physical, event.timestamp.logical, event.timestamp.node_id}
    end)
  end
  
  @doc """
  Checks if an event occurred within a time window (in milliseconds).
  """
  @spec within_window?(vsm_event(), non_neg_integer()) :: boolean()
  def within_window?(event, window_ms) do
    case now() do
      {:ok, current_timestamp} ->
        age_ms = current_timestamp.physical - event.timestamp.physical
        age_ms <= window_ms
        
      {:error, _} -> false
    end
  end
  
  @doc """
  Creates a causally-ordered sequence number for VSM operations.
  """
  @spec sequence_number() :: {:ok, String.t()} | {:error, term()}
  def sequence_number do
    case now() do
      {:ok, timestamp} ->
        seq = "#{timestamp.physical}-#{timestamp.logical}"
        {:ok, seq}
        
      error -> error
    end
  end
  
  @doc """
  Synchronizes with a remote VSM timestamp to maintain causal ordering.
  """
  @spec sync_with_remote(HybridLogicalClock.hlc_timestamp()) :: 
    {:ok, HybridLogicalClock.hlc_timestamp()} | {:error, term()}
  def sync_with_remote(remote_timestamp) do
    HybridLogicalClock.update(remote_timestamp)
  end
  
  @doc """
  Converts a VSM event to a compact string representation.
  """
  @spec event_to_string(vsm_event()) :: String.t()
  def event_to_string(event) do
    "#{event.subsystem}:#{event.type}@#{event.created_at}"
  end
  
  @doc """
  Creates a time-based partition key for VSM events (useful for sharding).
  """
  @spec partition_key(vsm_event(), non_neg_integer()) :: String.t()
  def partition_key(event, num_partitions \\ 16) do
    # Use physical timestamp for temporal locality
    partition = rem(event.timestamp.physical, num_partitions)
    "vsm_partition_#{partition}"
  end
  
  @doc """
  Validates that an event has a proper VSM timestamp structure.
  """
  @spec valid_event?(vsm_event()) :: boolean()
  def valid_event?(%{timestamp: timestamp} = event) when is_map(event) do
    is_map(timestamp) and
    Map.has_key?(timestamp, :physical) and
    Map.has_key?(timestamp, :logical) and
    Map.has_key?(timestamp, :node_id) and
    is_integer(timestamp.physical) and
    is_integer(timestamp.logical) and
    is_binary(timestamp.node_id)
  end
  def valid_event?(_), do: false
  
  @doc """
  Gets the age of an event in milliseconds.
  """
  @spec event_age(vsm_event()) :: {:ok, non_neg_integer()} | {:error, term()}
  def event_age(event) do
    case now() do
      {:ok, current_timestamp} ->
        age = current_timestamp.physical - event.timestamp.physical
        {:ok, max(0, age)}
        
      error -> error
    end
  end
  
  @doc """
  Creates a correlation ID for tracking related VSM operations.
  """
  @spec correlation_id(String.t()) :: {:ok, String.t()} | {:error, term()}
  def correlation_id(operation_context) do
    case now() do
      {:ok, timestamp} ->
        context_hash = :crypto.hash(:sha256, operation_context)
        |> Base.encode16(case: :lower)
        |> String.slice(0..7)
        
        correlation_id = "vsm_#{timestamp.physical}_#{context_hash}"
        {:ok, correlation_id}
        
      error -> error
    end
  end
end