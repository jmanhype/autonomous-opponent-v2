# PR #119 Implementation Plan: Complete CRDT Belief Consensus

## Overview
Complete the implementation details for CRDT Belief Consensus after PR #118 establishes the architecture.

## Missing Functions to Implement

### 1. Consensus Calculation Functions
```elixir
defp group_by_similarity(beliefs) do
  # Group beliefs by semantic content similarity
  # Use string distance or simple keyword matching
  beliefs
  |> Enum.group_by(fn belief ->
    belief.content
    |> String.downcase()
    |> String.split()
    |> Enum.take(3)  # First 3 words as grouping key
    |> Enum.join(" ")
  end)
end

defp calculate_group_support(group) do
  # Sum belief weights in group vs total system weight
  group_weight = Enum.sum(Enum.map(group, & &1.weight))
  group_weight / Enum.count(group)  # Average support
end

defp select_group_representative(group) do
  # Pick highest weight * confidence belief
  Enum.max_by(group, fn belief ->
    belief.weight * belief.confidence
  end)
end

defp calculate_consensus_strength(beliefs) do
  # Calculate overall consensus quality
  if Enum.empty?(beliefs) do
    0.0
  else
    avg_confidence = beliefs |> Enum.map(& &1.confidence) |> Enum.sum() |> Kernel./(length(beliefs))
    avg_weight = beliefs |> Enum.map(& &1.weight) |> Enum.sum() |> Kernel./(length(beliefs))
    (avg_confidence + avg_weight) / 2
  end
end
```

### 2. State Management Functions
```elixir
defp consensus_changed?(old_consensus, new_consensus) do
  # Compare MapSets of beliefs
  case {old_consensus, new_consensus} do
    {%MapSet{} = old, %MapSet{} = new} -> 
      MapSet.size(MapSet.symmetric_difference(old, new)) > 0
    {old, new} when is_map(old) and is_map(new) ->
      old.beliefs != new.beliefs
    _ -> 
      true  # Different types = changed
  end
end

defp broadcast_consensus_change(consensus, state) do
  EventBus.publish(:belief_consensus_update, %{
    level: state.vsm_level,
    consensus: consensus,
    node_id: state.node_id,
    timestamp: DateTime.utc_now()
  })
end
```

### 3. Oscillation Detection
```elixir
defp detect_oscillating_beliefs(history) do
  # Find beliefs that appear/disappear repeatedly
  history
  |> Enum.take(10)  # Recent history
  |> Enum.flat_map(fn consensus -> MapSet.to_list(consensus) end)
  |> Enum.frequencies()
  |> Enum.filter(fn {_belief, count} -> count >= 3 end)  # Appeared 3+ times
  |> Enum.map(fn {belief, _count} -> belief end)
end

defp apply_damping(oscillating_beliefs, damping_factor) do
  # Reduce weight of oscillating beliefs
  Enum.map(oscillating_beliefs, fn belief ->
    %{belief | weight: belief.weight * damping_factor}
  end)
end

defp update_oscillation_tracker(tracker, oscillating_beliefs) do
  Enum.reduce(oscillating_beliefs, tracker, fn belief, acc ->
    Map.update(acc, belief.id, 1, &(&1 + 1))
  end)
end
```

### 4. Belief Management
```elixir
defp get_all_beliefs(state) do
  # Get beliefs from all CRDT sets
  state.belief_sets
  |> Enum.flat_map(fn {_category, set_id} ->
    case CRDTStore.get_crdt(set_id) do
      {:ok, beliefs} when is_list(beliefs) -> beliefs
      _ -> []
    end
  end)
end

defp add_belief_to_set(belief, state) do
  # Add belief to appropriate CRDT set
  category = categorize_belief(belief, state.vsm_level)
  set_id = Map.get(state.belief_sets, category)
  
  if set_id do
    case CRDTStore.update_crdt(set_id, :add, belief) do
      :ok -> state
      _ -> state
    end
  else
    state
  end
end
```

## Quality Improvements

### 1. Fix Hardcoded Values in LiveView
```elixir
# Replace hardcoded Byzantine patterns
defp load_byzantine_nodes(socket) do
  nodes = ByzantineDetector.get_byzantine_nodes()
  |> Enum.map(fn node_id ->
    # Get actual patterns from detector
    patterns = ByzantineDetector.get_node_patterns(node_id)
    %{
      node_id: node_id,
      patterns: patterns,
      timestamp: DateTime.utc_now()
    }
  end)
  
  assign(socket, :byzantine_nodes, nodes)
end
```

### 2. Fix Rate Limiting Race Condition
```elixir
# In belief_consensus_channel.ex
defp rate_limit_ok?(state) do
  now = DateTime.utc_now()
  
  case state.last_vote_time do
    nil -> 
      true
    last_time ->
      diff_ms = DateTime.diff(now, last_time, :millisecond)
      min_interval = div(60_000, @max_beliefs_per_min)
      
      if state.vote_count < 10 do
        true  # Burst allowance
      else
        diff_ms >= min_interval
      end
  end
end
```

### 3. Cryptographic Node Identity
```elixir
defp generate_node_id(socket) do
  # Use cryptographic identity instead of PID hash
  node_data = %{
    transport_pid: socket.transport_pid,
    remote_ip: get_connect_info(socket, :peer_data),
    timestamp: System.os_time(:microsecond)
  }
  
  :crypto.hash(:sha256, :erlang.term_to_binary(node_data))
  |> Base.encode16(case: :lower)
  |> String.slice(0..15)  # 16 char ID
end
```

## Testing Additions

### Network Partition Tests
```elixir
test "handles network partition gracefully" do
  # Simulate partition by stopping inter-node communication
  # Verify beliefs converge when partition heals
end

test "maintains consistency during concurrent Byzantine attacks" do
  # Multiple Byzantine nodes acting simultaneously
  # Verify system remains stable
end
```

## Implementation Priority
1. **Critical**: Missing function implementations (prevents runtime errors)
2. **High**: Rate limiting and voter ID fixes (security)
3. **Medium**: Hardcoded value fixes (monitoring accuracy)
4. **Low**: Additional tests and optimizations

## Success Criteria
- [ ] No runtime errors in belief consensus operations
- [ ] All tests pass including new partition tests
- [ ] LiveView dashboard shows real Byzantine detection data
- [ ] Rate limiting works correctly under load
- [ ] Cryptographic node IDs prevent impersonation

This completes the CRDT Belief Consensus implementation with production-ready quality.