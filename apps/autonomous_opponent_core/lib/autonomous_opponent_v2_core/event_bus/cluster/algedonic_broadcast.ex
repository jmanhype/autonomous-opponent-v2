defmodule AutonomousOpponentV2Core.EventBus.Cluster.AlgedonicBroadcast do
  @moduledoc """
  Algedonic Broadcast - Zero-Latency Pain/Pleasure Signal Propagation
  
  This module implements the critical algedonic bypass channel for the distributed VSM.
  Following Stafford Beer's cybernetic principles, algedonic signals must:
  
  1. **Bypass all filters** - No variety constraints apply
  2. **Achieve zero-latency** - Multiple redundant paths
  3. **Guarantee delivery** - Confirmation and retry mechanisms
  4. **Trigger immediate response** - Direct S5 notification
  
  ## Cybernetic Theory
  
  In Beer's VSM, algedonic signals represent the organism's pain/pleasure responses
  that must reach the highest control levels immediately. These signals:
  
  - Short-circuit the normal variety absorption mechanisms
  - Trigger immediate policy intervention (S5)
  - Can override all other system activities
  - Represent existential threats or opportunities
  
  ## Implementation
  
  Uses multiple communication channels for redundancy:
  - Primary: Direct GenServer message passing
  - Secondary: Erlang RPC calls
  - Tertiary: Phoenix.PubSub broadcast
  - Emergency: UDP broadcast on local network
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.Telemetry
  alias AutonomousOpponentV2Core.VSM.S5.Policy
  
  @emergency_port 45893  # UDP port for emergency broadcasts
  @confirmation_timeout 1000  # 1 second timeout for confirmations
  @max_retries 3
  
  defstruct [
    :node_id,
    :udp_socket,
    :pending_screams,
    :scream_confirmations,
    :stats
  ]
  
  @type algedonic_signal :: %{
    type: :pain | :pleasure | :emergency,
    severity: 1..10,
    source: atom(),
    data: map(),
    timestamp: DateTime.t()
  }
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  @doc """
  Broadcast a critical pain signal to all nodes immediately.
  This function blocks until confirmation is received from all nodes or timeout.
  
  ## Examples
  
      iex> emergency_scream(%{
        type: :pain,
        severity: 10,
        source: :resource_exhaustion,
        data: %{memory_used: 95, cpu_used: 99}
      })
      {:ok, %{confirmed_nodes: [:node1@host, :node2@host], failed_nodes: []}}
  """
  def emergency_scream(signal, opts \\ []) do
    timeout = opts[:timeout] || @confirmation_timeout * 2
    GenServer.call(__MODULE__, {:emergency_scream, signal}, timeout)
  end
  
  @doc """
  Broadcast a pleasure signal indicating positive system state.
  """
  def pleasure_signal(signal) do
    GenServer.cast(__MODULE__, {:pleasure_signal, signal})
  end
  
  @doc """
  Get algedonic broadcast statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    # Open UDP socket for emergency broadcasts
    {:ok, udp_socket} = :gen_udp.open(@emergency_port, [
      :binary,
      {:broadcast, true},
      {:reuseaddr, true},
      {:active, true}
    ])
    
    state = %__MODULE__{
      node_id: node(),
      udp_socket: udp_socket,
      pending_screams: %{},
      scream_confirmations: %{},
      stats: init_stats()
    }
    
    # Subscribe to algedonic events
    EventBus.subscribe(:emergency_algedonic)
    EventBus.subscribe(:algedonic_pain)
    EventBus.subscribe(:algedonic_pleasure)
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:emergency_scream, signal}, from, state) do
    # Generate unique scream ID
    scream_id = generate_scream_id()
    
    # Prepare the algedonic package
    algedonic_package = prepare_algedonic_package(signal, scream_id, state.node_id)
    
    # Get all known nodes
    target_nodes = Node.list(:known)
    
    if target_nodes == [] do
      # No other nodes - just process locally
      process_local_algedonic(algedonic_package)
      {:reply, {:ok, %{confirmed_nodes: [], failed_nodes: []}}, state}
    else
      # Initialize confirmation tracking
      new_pending = Map.put(state.pending_screams, scream_id, %{
        from: from,
        signal: signal,
        targets: MapSet.new(target_nodes),
        confirmations: MapSet.new(),
        start_time: System.monotonic_time(:millisecond),
        retry_count: 0
      })
      
      new_state = %{state | pending_screams: new_pending}
      
      # Broadcast through all channels
      broadcast_algedonic_all_channels(algedonic_package, target_nodes, new_state)
      
      # Set confirmation timeout
      Process.send_after(self(), {:confirmation_timeout, scream_id}, @confirmation_timeout)
      
      # Don't reply yet - will reply when confirmations arrive or timeout
      {:noreply, new_state}
    end
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end
  
  @impl true
  def handle_cast({:pleasure_signal, signal}, state) do
    # Pleasure signals are important but not emergency level
    algedonic_package = prepare_algedonic_package(signal, generate_scream_id(), state.node_id)
    
    # Broadcast with normal priority
    target_nodes = Node.list(:known)
    broadcast_pleasure_signal(algedonic_package, target_nodes)
    
    # Update stats
    new_stats = Map.update!(state.stats, :pleasure_signals_sent, &(&1 + 1))
    
    {:noreply, %{state | stats: new_stats}}
  end
  
  @impl true
  def handle_info({:udp, _socket, ip, port, data}, state) do
    # Handle incoming UDP algedonic broadcast
    case decode_algedonic_package(data) do
      {:ok, package} ->
        handle_incoming_algedonic(package, {:udp, ip, port}, state)
      {:error, reason} ->
        Logger.warn("Algedonic: Failed to decode UDP package - #{reason}")
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:algedonic_broadcast, package, from_node}, state) do
    # Handle incoming algedonic signal from another node
    handle_incoming_algedonic(package, {:erlang, from_node}, state)
  end
  
  @impl true
  def handle_info({:algedonic_confirmation, scream_id, from_node}, state) do
    # Handle confirmation from remote node
    case Map.get(state.pending_screams, scream_id) do
      nil ->
        # Late confirmation - ignore
        {:noreply, state}
        
      pending ->
        # Record confirmation
        updated_pending = %{pending | 
          confirmations: MapSet.put(pending.confirmations, from_node)
        }
        
        # Check if all confirmations received
        if MapSet.equal?(updated_pending.confirmations, updated_pending.targets) do
          # All confirmed - send success reply
          GenServer.reply(pending.from, {:ok, %{
            confirmed_nodes: MapSet.to_list(updated_pending.confirmations),
            failed_nodes: [],
            latency_ms: System.monotonic_time(:millisecond) - pending.start_time
          }})
          
          # Clean up
          new_pending = Map.delete(state.pending_screams, scream_id)
          new_stats = Map.update!(state.stats, :screams_confirmed, &(&1 + 1))
          
          {:noreply, %{state | pending_screams: new_pending, stats: new_stats}}
        else
          # Still waiting for more confirmations
          new_pending = Map.put(state.pending_screams, scream_id, updated_pending)
          {:noreply, %{state | pending_screams: new_pending}}
        end
    end
  end
  
  @impl true
  def handle_info({:confirmation_timeout, scream_id}, state) do
    case Map.get(state.pending_screams, scream_id) do
      nil ->
        # Already handled
        {:noreply, state}
        
      pending ->
        # Check retry count
        if pending.retry_count < @max_retries do
          # Retry for missing confirmations
          missing_nodes = MapSet.difference(pending.targets, pending.confirmations)
          
          Logger.warn("Algedonic: Retrying scream #{scream_id} for nodes: #{inspect(missing_nodes)}")
          
          # Prepare package for retry
          algedonic_package = prepare_algedonic_package(
            pending.signal,
            scream_id,
            state.node_id
          )
          
          # Retry only to missing nodes
          retry_algedonic_broadcast(algedonic_package, MapSet.to_list(missing_nodes))
          
          # Update retry count and set new timeout
          updated_pending = %{pending | retry_count: pending.retry_count + 1}
          new_pending = Map.put(state.pending_screams, scream_id, updated_pending)
          
          Process.send_after(self(), {:confirmation_timeout, scream_id}, @confirmation_timeout)
          
          {:noreply, %{state | pending_screams: new_pending}}
        else
          # Max retries reached - send partial success
          confirmed = MapSet.to_list(pending.confirmations)
          failed = MapSet.to_list(MapSet.difference(pending.targets, pending.confirmations))
          
          Logger.error("Algedonic: Scream #{scream_id} failed to reach nodes: #{inspect(failed)}")
          
          GenServer.reply(pending.from, {:ok, %{
            confirmed_nodes: confirmed,
            failed_nodes: failed,
            latency_ms: System.monotonic_time(:millisecond) - pending.start_time
          }})
          
          # Clean up and update stats
          new_pending = Map.delete(state.pending_screams, scream_id)
          new_stats = state.stats
          |> Map.update!(:screams_partial, &(&1 + 1))
          |> Map.update!(:total_failed_nodes, &(&1 + length(failed)))
          
          {:noreply, %{state | pending_screams: new_pending, stats: new_stats}}
        end
    end
  end
  
  @impl true
  def handle_info({:event_bus_hlc, %{event_name: event_name} = event}, state) 
      when event_name in [:emergency_algedonic, :algedonic_pain, :algedonic_pleasure] do
    # Handle local algedonic events that need broadcasting
    signal = extract_algedonic_signal(event)
    
    case event_name do
      :emergency_algedonic ->
        # Use emergency scream for critical events
        Task.start(fn ->
          emergency_scream(signal)
        end)
        
      :algedonic_pain ->
        # Broadcast pain signal
        GenServer.cast(self(), {:pain_signal, signal})
        
      :algedonic_pleasure ->
        # Broadcast pleasure signal
        GenServer.cast(self(), {:pleasure_signal, signal})
    end
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  @impl true
  def terminate(_reason, state) do
    # Close UDP socket
    :gen_udp.close(state.udp_socket)
    :ok
  end
  
  # Private Functions
  
  defp init_stats do
    %{
      screams_sent: 0,
      screams_received: 0,
      screams_confirmed: 0,
      screams_partial: 0,
      pain_signals_sent: 0,
      pain_signals_received: 0,
      pleasure_signals_sent: 0,
      pleasure_signals_received: 0,
      total_failed_nodes: 0,
      avg_confirmation_time_ms: 0
    }
  end
  
  defp generate_scream_id do
    "scream_#{node()}_#{System.unique_integer([:positive, :monotonic])}"
  end
  
  defp prepare_algedonic_package(signal, scream_id, source_node) do
    %{
      id: scream_id,
      type: signal[:type] || :pain,
      severity: signal[:severity] || 5,
      source_node: source_node,
      source_component: signal[:source] || :unknown,
      data: signal[:data] || %{},
      timestamp: signal[:timestamp] || DateTime.utc_now(),
      vsm_directive: determine_vsm_directive(signal)
    }
  end
  
  defp determine_vsm_directive(signal) do
    case {signal[:type], signal[:severity]} do
      {:pain, severity} when severity >= 8 ->
        :immediate_intervention_required
      {:pain, severity} when severity >= 5 ->
        :policy_review_required
      {:pleasure, severity} when severity >= 8 ->
        :maintain_current_state
      _ ->
        :monitor_closely
    end
  end
  
  defp broadcast_algedonic_all_channels(package, target_nodes, state) do
    # Log the emergency
    Logger.error("ALGEDONIC SCREAM: #{package.id} - Type: #{package.type}, Severity: #{package.severity}")
    
    # 1. Direct GenServer messages (fastest)
    Enum.each(target_nodes, fn node ->
      send({__MODULE__, node}, {:algedonic_broadcast, package, state.node_id})
    end)
    
    # 2. RPC calls (reliable)
    Task.start(fn ->
      Enum.each(target_nodes, fn node ->
        :rpc.cast(node, __MODULE__, :handle_remote_algedonic, [package])
      end)
    end)
    
    # 3. Phoenix.PubSub if available
    if Code.ensure_loaded?(Phoenix.PubSub) do
      Phoenix.PubSub.broadcast(
        AutonomousOpponentV2Web.PubSub,
        "algedonic:emergency",
        {:algedonic_emergency, package}
      )
    end
    
    # 4. UDP broadcast (last resort)
    broadcast_udp_algedonic(package, state.udp_socket)
    
    # 5. Direct EventBus notification for local S5
    EventBus.publish(:algedonic_broadcast_sent, package)
    
    # Update stats
    new_stats = Map.update!(state.stats, :screams_sent, &(&1 + 1))
    %{state | stats: new_stats}
  end
  
  defp broadcast_pleasure_signal(package, target_nodes) do
    # Pleasure signals use normal channels only
    Enum.each(target_nodes, fn node ->
      send({__MODULE__, node}, {:algedonic_broadcast, package, node()})
    end)
  end
  
  defp retry_algedonic_broadcast(package, missing_nodes) do
    # Retry with increased urgency
    Enum.each(missing_nodes, fn node ->
      # Try all methods again
      send({__MODULE__, node}, {:algedonic_broadcast, package, node()})
      
      Task.start(fn ->
        :rpc.cast(node, __MODULE__, :handle_remote_algedonic, [package])
      end)
    end)
  end
  
  defp broadcast_udp_algedonic(package, socket) do
    # Encode package for UDP
    encoded = encode_algedonic_package(package)
    
    # Broadcast to all interfaces
    broadcast_addresses = get_broadcast_addresses()
    
    Enum.each(broadcast_addresses, fn addr ->
      case :gen_udp.send(socket, addr, @emergency_port, encoded) do
        :ok -> :ok
        {:error, reason} ->
          Logger.error("Algedonic UDP broadcast failed to #{inspect(addr)}: #{inspect(reason)}")
      end
    end)
  end
  
  defp get_broadcast_addresses do
    # Get all network interfaces and their broadcast addresses
    {:ok, interfaces} = :inet.getifaddrs()
    
    interfaces
    |> Enum.flat_map(fn {_name, opts} ->
      case Keyword.get(opts, :broadaddr) do
        nil -> []
        addr -> [addr]
      end
    end)
    |> Enum.uniq()
  end
  
  defp encode_algedonic_package(package) do
    # Use ETF for reliable encoding
    :erlang.term_to_binary(package)
  end
  
  defp decode_algedonic_package(binary) do
    try do
      {:ok, :erlang.binary_to_term(binary)}
    rescue
      _ -> {:error, :decode_failed}
    end
  end
  
  defp handle_incoming_algedonic(package, source, state) do
    Logger.warn("ALGEDONIC RECEIVED: #{package.id} from #{inspect(source)} - Type: #{package.type}, Severity: #{package.severity}")
    
    # Send confirmation back to source
    send_confirmation(package.id, package.source_node)
    
    # Process the algedonic signal
    process_algedonic_signal(package)
    
    # Update stats
    stat_key = case package.type do
      :pain -> :pain_signals_received
      :pleasure -> :pleasure_signals_received
      _ -> :screams_received
    end
    
    new_stats = Map.update!(state.stats, stat_key, &(&1 + 1))
    
    {:noreply, %{state | stats: new_stats}}
  end
  
  defp send_confirmation(scream_id, source_node) do
    if source_node != node() do
      send({__MODULE__, source_node}, {:algedonic_confirmation, scream_id, node()})
    end
  end
  
  defp process_algedonic_signal(package) do
    # Local processing of received algedonic signal
    
    # 1. Notify S5 immediately
    Policy.algedonic_intervention(package)
    
    # 2. Publish to local EventBus
    EventBus.publish(:algedonic_signal_received, package)
    
    # 3. Log for audit trail
    Logger.error("ALGEDONIC SIGNAL: Processing #{package.id} - VSM Directive: #{package.vsm_directive}")
    
    # 4. Trigger telemetry
    Telemetry.execute(
      [:vsm, :algedonic, :signal_received],
      %{severity: package.severity},
      %{
        type: package.type,
        source_node: package.source_node,
        source_component: package.source_component,
        directive: package.vsm_directive
      }
    )
  end
  
  defp process_local_algedonic(package) do
    # When no other nodes exist, still process locally
    process_algedonic_signal(package)
  end
  
  defp extract_algedonic_signal(event) do
    %{
      type: event.data[:type] || :pain,
      severity: event.data[:severity] || 5,
      source: event.data[:source] || event.metadata[:source] || :unknown,
      data: event.data,
      timestamp: event.timestamp
    }
  end
  
  # Public function for RPC calls
  def handle_remote_algedonic(package) do
    # This is called via RPC from remote nodes
    send(__MODULE__, {:algedonic_broadcast, package, package.source_node})
  end
end