defmodule AutonomousOpponentV2Core.AMCP.Memory.EPMDDiscovery do
  @moduledoc """
  EPMD-based CRDT Node Discovery - Maximum Cybernetic Intensity!
  
  This module implements automatic peer discovery using Erlang's EPMD (Erlang Port Mapper Daemon).
  It replaces hardcoded CRDT peers with dynamic discovery, fulfilling issue #89.
  
  ## Features
  - Automatic node discovery via Node.list()
  - Periodic polling for new nodes (10 second requirement)
  - Automatic cleanup of removed nodes
  - Support for both --sname and --name node naming
  - VSM-aligned variety management
  
  ## Cybernetic Principles
  - S1: Autonomous peer discovery operations
  - S2: Anti-oscillation for stable peer sets
  - S3: Resource optimization via peer selection
  - S4: Environmental scanning for new nodes
  - S5: Policy constraints on peer limits
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.AMCP.Memory.CRDTStore
  alias AutonomousOpponentV2Core.EventBus
  
  defstruct [
    :discovery_interval,
    :node_filter,
    :max_peers,
    :known_nodes,
    :peer_stability,
    :last_discovery,
    :discovery_enabled,
    :stability_threshold,
    :sync_cooldown_ms,
    :last_sync_time,
    :pending_syncs
  ]
  
  # Constants aligned with issue #89 requirements
  @default_discovery_interval 10_000  # 10 seconds as specified
  @default_max_peers 100
  @default_stability_threshold 3  # Node must be seen 3 times before considered stable
  @default_sync_cooldown_ms 1_000  # 1 second cooldown between syncs to prevent storms
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Manually trigger peer discovery
  """
  def discover_now do
    GenServer.cast(__MODULE__, :discover_peers)
  end
  
  @doc """
  Get current discovery status
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end
  
  @doc """
  Enable or disable automatic discovery
  """
  def set_enabled(enabled) when is_boolean(enabled) do
    GenServer.call(__MODULE__, {:set_enabled, enabled})
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    # Enable node monitoring for real-time discovery
    :net_kernel.monitor_nodes(true, node_type: :all)
    
    state = %__MODULE__{
      discovery_interval: Keyword.get(opts, :discovery_interval, @default_discovery_interval),
      node_filter: Keyword.get(opts, :node_filter, &default_node_filter/1),
      max_peers: Keyword.get(opts, :max_peers, @default_max_peers),
      known_nodes: MapSet.new(),
      peer_stability: %{},
      last_discovery: nil,
      discovery_enabled: Keyword.get(opts, :enabled, true),
      stability_threshold: Keyword.get(opts, :stability_threshold, @default_stability_threshold),
      sync_cooldown_ms: Keyword.get(opts, :sync_cooldown_ms, @default_sync_cooldown_ms),
      last_sync_time: 0,
      pending_syncs: MapSet.new()
    }
    
    # Schedule first discovery
    if state.discovery_enabled do
      schedule_discovery(100)  # Quick first discovery
    end
    
    Logger.info("🚀 EPMD Discovery initialized - Maximum intensity peer discovery activated!")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:status, _from, state) do
    adaptive_interval = calculate_adaptive_interval(state)
    
    status = %{
      discovery_enabled: state.discovery_enabled,
      known_nodes: MapSet.to_list(state.known_nodes),
      peer_stability: state.peer_stability,
      last_discovery: state.last_discovery,
      next_discovery: if(state.discovery_enabled, do: "in #{adaptive_interval}ms", else: "disabled"),
      stability_threshold: state.stability_threshold,
      sync_cooldown_ms: state.sync_cooldown_ms,
      pending_syncs: MapSet.to_list(state.pending_syncs),
      adaptive_interval: adaptive_interval
    }
    {:reply, status, state}
  end
  
  @impl true
  def handle_call({:set_enabled, enabled}, _from, state) do
    new_state = %{state | discovery_enabled: enabled}
    
    if enabled and not state.discovery_enabled do
      # Just enabled - trigger immediate discovery
      schedule_discovery(100)
    end
    
    Logger.info("EPMD Discovery #{if enabled, do: "enabled", else: "disabled"}")
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_cast(:discover_peers, state) do
    new_state = perform_discovery(state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:scheduled_discovery, state) do
    if state.discovery_enabled do
      new_state = perform_discovery(state)
      
      # Calculate adaptive discovery interval based on cluster size
      # More nodes = longer interval to reduce network chatter
      adaptive_interval = calculate_adaptive_interval(new_state)
      schedule_discovery(adaptive_interval)
      
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:nodeup, node, _info}, state) do
    Logger.info("⚡ EPMD: Node detected via monitor - #{node}")
    
    # Track node but don't immediately add as CRDT peer
    if should_add_node?(node, state) do
      new_nodes = MapSet.put(state.known_nodes, node)
      new_stability = increment_stability(state.peer_stability, node)
      
      # Only add as CRDT peer if stability threshold is met
      state = if get_stability_score(new_stability, node) >= state.stability_threshold do
        Logger.info("✅ EPMD Discovery: Adding #{node} as CRDT peer (stability threshold met)")
        add_crdt_peer(node, state)
      else
        Logger.debug("⏳ EPMD Discovery: Tracking #{node} (stability: #{get_stability_score(new_stability, node)}/#{state.stability_threshold})")
        state
      end
      
      {:noreply, %{state | known_nodes: new_nodes, peer_stability: new_stability}}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:nodedown, node, _info}, state) do
    Logger.warning("💔 EPMD: Node departed - #{node}")
    
    # Remove from CRDT peers
    CRDTStore.remove_sync_peer(to_string(node))
    
    # Clean up state
    new_nodes = MapSet.delete(state.known_nodes, node)
    new_stability = Map.delete(state.peer_stability, node)
    new_pending_syncs = MapSet.delete(state.pending_syncs, node)
    
    {:noreply, %{state | 
      known_nodes: new_nodes, 
      peer_stability: new_stability,
      pending_syncs: new_pending_syncs
    }}
  end
  
  @impl true
  def handle_info({:process_pending_sync, node}, state) do
    # Process a pending sync for a specific node
    if MapSet.member?(state.pending_syncs, node) do
      current_time = System.monotonic_time(:millisecond)
      time_since_last_sync = current_time - state.last_sync_time
      
      if time_since_last_sync >= state.sync_cooldown_ms do
        # Enough time has passed, perform the sync
        Logger.debug("🔄 Processing pending sync for #{node}")
        CRDTStore.sync_with_peers()
        
        new_pending_syncs = MapSet.delete(state.pending_syncs, node)
        {:noreply, %{state | 
          pending_syncs: new_pending_syncs,
          last_sync_time: current_time
        }}
      else
        # Still in cooldown, reschedule
        remaining_cooldown = state.sync_cooldown_ms - time_since_last_sync
        Process.send_after(self(), {:process_pending_sync, node}, remaining_cooldown)
        {:noreply, state}
      end
    else
      # Node no longer in pending syncs (maybe removed)
      {:noreply, state}
    end
  end
  
  # Private Functions
  
  defp perform_discovery(state) do
    start_time = System.monotonic_time(:millisecond)
    Logger.debug("🔍 EPMD Discovery: Scanning for CRDT peers...")
    
    # Get all visible nodes via EPMD
    current_nodes = discover_nodes_via_epmd()
    
    # Find new nodes
    new_nodes = MapSet.difference(MapSet.new(current_nodes), state.known_nodes)
    
    # Find removed nodes
    removed_nodes = MapSet.difference(state.known_nodes, MapSet.new(current_nodes))
    
    # Process new nodes
    state = Enum.reduce(new_nodes, state, fn node, acc_state ->
      if should_add_node?(node, acc_state) do
        Logger.info("✨ EPMD Discovery: Found new node #{node}")
        
        # Update stability tracking
        new_stability = increment_stability(acc_state.peer_stability, node)
        
        # Only add as CRDT peer if stable enough
        acc_state = if get_stability_score(new_stability, node) >= acc_state.stability_threshold do
          Logger.info("✅ EPMD Discovery: Adding #{node} as CRDT peer (stability threshold met)")
          add_crdt_peer(node, acc_state)
        else
          Logger.debug("⏳ EPMD Discovery: Tracking #{node} (stability: #{get_stability_score(new_stability, node)}/#{acc_state.stability_threshold})")
          acc_state
        end
        
        %{acc_state | 
          known_nodes: MapSet.put(acc_state.known_nodes, node),
          peer_stability: new_stability
        }
      else
        acc_state
      end
    end)
    
    # Process removed nodes
    state = Enum.reduce(removed_nodes, state, fn node, acc_state ->
      Logger.info("🗑️ EPMD Discovery: Removing departed node #{node}")
      CRDTStore.remove_sync_peer(to_string(node))
      
      %{acc_state | 
        known_nodes: MapSet.delete(acc_state.known_nodes, node),
        peer_stability: Map.delete(acc_state.peer_stability, node)
      }
    end)
    
    # Calculate discovery duration
    discovery_duration = System.monotonic_time(:millisecond) - start_time
    
    # Emit telemetry for discovery completion
    :telemetry.execute(
      [:epmd_discovery, :discovery_completed],
      %{
        discovered: MapSet.size(new_nodes),
        removed: MapSet.size(removed_nodes),
        total_peers: MapSet.size(state.known_nodes),
        duration_ms: discovery_duration
      },
      %{discovery_type: :periodic}
    )
    
    # Update last discovery time
    %{state | last_discovery: System.system_time(:second)}
  end
  
  defp discover_nodes_via_epmd do
    # Primary discovery method: Node.list()
    visible_nodes = Node.list(:visible)
    hidden_nodes = Node.list(:hidden)
    known_nodes = Node.list(:known)
    
    # Combine all discovered nodes
    all_nodes = MapSet.new(visible_nodes ++ hidden_nodes ++ known_nodes)
    
    # Also try net_adm:names() for local EPMD
    local_epmd_nodes = try do
      case :net_adm.names() do
        {:ok, names} ->
          # Convert EPMD entries to node names
          Enum.map(names, fn {name, _port} ->
            # Handle both short and long names
            if String.contains?(to_string(node()), "@") do
              [_local_name, host] = String.split(to_string(node()), "@")
              :"#{name}@#{host}"
            else
              :"#{name}"
            end
          end)
        {:error, :address} ->
          Logger.debug("EPMD not reachable on local host")
          []
        {:error, reason} ->
          Logger.warning("Failed to query EPMD: #{inspect(reason)}")
          []
      end
    rescue
      error in [ArgumentError, RuntimeError] ->
        Logger.warning("Error querying EPMD: #{inspect(error)}")
        []
    end
    
    # Combine all sources
    all_discovered = MapSet.union(all_nodes, MapSet.new(local_epmd_nodes))
    
    # Filter out self
    all_discovered
    |> MapSet.delete(node())
    |> MapSet.to_list()
  end
  
  defp should_add_node?(node, state) do
    # Apply node filter
    state.node_filter.(node) and
    # Check peer limit
    MapSet.size(state.known_nodes) < state.max_peers and
    # Not already known
    not MapSet.member?(state.known_nodes, node)
  end
  
  defp default_node_filter(node) do
    # Default filter: Accept nodes with similar naming pattern
    node_str = to_string(node)
    self_str = to_string(node())
    
    # Extract node name patterns
    self_prefix = extract_node_prefix(self_str)
    node_prefix = extract_node_prefix(node_str)
    
    # Accept nodes with same prefix (e.g., "autonomous_opponent")
    self_prefix == node_prefix
  end
  
  defp extract_node_prefix(node_str) do
    # Extract prefix before @ or first number
    node_str
    |> String.split(~r/[@0-9]/, parts: 2)
    |> List.first()
  end
  
  defp add_crdt_peer(node, state) do
    # Convert node atom to string for CRDT Store
    peer_id = to_string(node)
    
    # Add to CRDT sync peers
    case CRDTStore.add_sync_peer(peer_id) do
      :ok ->
        # Schedule sync with cooldown to prevent sync storms
        current_time = System.monotonic_time(:millisecond)
        time_since_last_sync = current_time - state.last_sync_time
        
        new_state = if time_since_last_sync >= state.sync_cooldown_ms do
          # Can sync immediately
          CRDTStore.sync_with_peers()
          %{state | last_sync_time: current_time}
        else
          # Schedule for later
          remaining_cooldown = state.sync_cooldown_ms - time_since_last_sync
          Process.send_after(self(), {:process_pending_sync, node}, remaining_cooldown)
          %{state | pending_syncs: MapSet.put(state.pending_syncs, node)}
        end
        
        # Emit telemetry
        :telemetry.execute(
          [:epmd_discovery, :peer_added],
          %{peer_count: 1, sync_scheduled: MapSet.member?(new_state.pending_syncs, node)},
          %{node: node}
        )
        
        new_state
        
      {:error, reason} ->
        Logger.warning("Failed to add CRDT peer #{peer_id}: #{inspect(reason)}")
        state
    end
  end
  
  defp increment_stability(stability_map, node) do
    Map.update(stability_map, node, 1, &(&1 + 1))
  end
  
  defp get_stability_score(stability_map, node) do
    Map.get(stability_map, node, 0)
  end
  
  defp schedule_discovery(delay) do
    Process.send_after(self(), :scheduled_discovery, delay)
  end
  
  defp calculate_adaptive_interval(state) do
    # Base interval grows with cluster size
    # 10s for <10 nodes, 20s for 10-25 nodes, 30s for 25-50 nodes, etc.
    node_count = MapSet.size(state.known_nodes)
    
    multiplier = cond do
      node_count < 10 -> 1.0
      node_count < 25 -> 2.0
      node_count < 50 -> 3.0
      node_count < 100 -> 4.0
      true -> 6.0  # Large clusters
    end
    
    # Calculate interval with max cap of 60 seconds
    interval = round(state.discovery_interval * multiplier)
    min(interval, 60_000)
  end
end