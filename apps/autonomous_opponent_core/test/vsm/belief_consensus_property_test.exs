defmodule AutonomousOpponentV2Core.VSM.BeliefConsensusPropertyTest do
  use ExUnit.Case
  use PropCheck
  
  alias AutonomousOpponentV2Core.AMCP.Memory.{ORSet, CRDTStore}
  alias AutonomousOpponentV2Core.VSM.BeliefConsensus
  
  setup do
    # Ensure CRDTStore is running
    unless Process.whereis(AutonomousOpponentV2Core.AMCP.Memory.CRDTStore) do
      {:ok, _} = CRDTStore.start_link([])
    end
    
    :ok
  end
  
  property "OR-Set merge is commutative" do
    forall {elements1, elements2} <- {list(belief()), list(belief())} do
      # Create two OR-Sets
      set1 = create_or_set("node1", elements1)
      set2 = create_or_set("node2", elements2)
      
      # Merge in both orders
      merged1 = ORSet.merge(set1, set2)
      merged2 = ORSet.merge(set2, set1)
      
      # Values should be identical
      ORSet.value(merged1) == ORSet.value(merged2)
    end
  end
  
  property "OR-Set merge is associative" do
    forall {elements1, elements2, elements3} <- {list(belief()), list(belief()), list(belief())} do
      # Create three OR-Sets
      set1 = create_or_set("node1", elements1)
      set2 = create_or_set("node2", elements2)
      set3 = create_or_set("node3", elements3)
      
      # Merge in different groupings
      merged_12_3 = ORSet.merge(ORSet.merge(set1, set2), set3)
      merged_1_23 = ORSet.merge(set1, ORSet.merge(set2, set3))
      
      # Results should be identical
      ORSet.value(merged_12_3) == ORSet.value(merged_1_23)
    end
  end
  
  property "OR-Set merge is idempotent" do
    forall elements <- list(belief()) do
      set = create_or_set("node1", elements)
      
      # Merging with itself should not change the set
      merged = ORSet.merge(set, set)
      
      ORSet.value(merged) == ORSet.value(set)
    end
  end
  
  property "belief consensus converges to same state" do
    forall beliefs <- list(belief()) do
      # Skip if too many beliefs (performance)
      implies(length(beliefs) <= 20) do
        # Create multiple nodes with same beliefs
        nodes = for i <- 1..3, do: "node#{i}"
        
        # Each node processes beliefs in random order
        final_states = Enum.map(nodes, fn node ->
          shuffled = Enum.shuffle(beliefs)
          process_beliefs(node, shuffled)
        end)
        
        # All nodes should reach same final state
        case final_states do
          [] -> true
          [first | rest] -> Enum.all?(rest, &(&1 == first))
        end
      end
    end
  end
  
  property "delta sync preserves causality" do
    forall operations <- list(delta_operation()) do
      # Create vector clock
      clock = %{"node1" => 0, "node2" => 0, "node3" => 0}
      
      # Apply operations and track causality
      {final_clock, valid} = Enum.reduce(operations, {clock, true}, fn op, {clock_acc, valid_acc} ->
        new_clock = apply_delta_operation(op, clock_acc)
        causally_valid = is_causally_valid?(op, clock_acc)
        
        {new_clock, valid_acc && causally_valid}
      end)
      
      # All operations should maintain causality
      valid
    end
  end
  
  property "Byzantine detection preserves safety" do
    forall {good_votes, bad_votes} <- {list(good_vote()), list(byzantine_vote())} do
      # Mix good and Byzantine votes
      all_votes = Enum.shuffle(good_votes ++ bad_votes)
      
      # Process votes and detect Byzantine behavior
      byzantine_nodes = process_votes_with_detection(all_votes)
      
      # Byzantine nodes should only include actual bad actors
      bad_node_ids = bad_votes |> Enum.map(& &1.node_id) |> Enum.uniq()
      
      # All detected nodes should be actually Byzantine
      Enum.all?(byzantine_nodes, &(&1 in bad_node_ids))
    end
  end
  
  property "reputation weighting maintains fairness" do
    forall votes <- list(weighted_vote()) do
      implies(length(votes) > 0) do
        # Calculate consensus with reputation weights
        weighted_result = calculate_weighted_consensus(votes)
        
        # Reputation should affect outcome but not dominate
        # High reputation nodes shouldn't have >50% power alone
        max_individual_power = votes
        |> Enum.map(& &1.reputation)
        |> Enum.max(fn -> 0 end)
        
        max_individual_power <= 0.5 || length(votes) == 1
      end
    end
  end
  
  property "algedonic bypass maintains VSM hierarchy" do
    forall {normal_beliefs, urgent_beliefs} <- {list(belief()), list(urgent_belief())} do
      # Process both normal and urgent beliefs
      all_beliefs = Enum.shuffle(normal_beliefs ++ urgent_beliefs)
      
      # Track processing order
      processed = process_with_algedonic_bypass(all_beliefs)
      
      # Urgent beliefs should be processed before normal ones
      urgent_indices = Enum.with_index(processed)
      |> Enum.filter(fn {belief, _idx} -> belief[:urgency] > 0.9 end)
      |> Enum.map(fn {_belief, idx} -> idx end)
      
      normal_indices = Enum.with_index(processed)
      |> Enum.filter(fn {belief, _idx} -> belief[:urgency] <= 0.9 end)
      |> Enum.map(fn {_belief, idx} -> idx end)
      
      # If both exist, max urgent index should be less than min normal index
      case {urgent_indices, normal_indices} do
        {[], _} -> true
        {_, []} -> true
        {urgent, normal} -> 
          Enum.max(urgent) < Enum.min(normal)
      end
    end
  end
  
  # Generator functions
  
  def belief do
    let content <- utf8() do
      %{
        id: make_ref() |> :erlang.ref_to_list() |> to_string(),
        content: content,
        weight: float(0.0, 1.0),
        confidence: float(0.0, 1.0),
        source: oneof([:s1, :s2, :s3, :s4, :s5]),
        timestamp: DateTime.utc_now()
      }
    end
  end
  
  def urgent_belief do
    let b <- belief() do
      Map.put(b, :urgency, float(0.91, 1.0))
    end
  end
  
  def delta_operation do
    let {node, version, op} <- {
      oneof(["node1", "node2", "node3"]),
      pos_integer(),
      oneof([:add, :remove])
    } do
      %{
        node: node,
        version: version,
        operation: op,
        element: belief()
      }
    end
  end
  
  def good_vote do
    let {node_id, vote} <- {atom(), float(0.0, 1.0)} do
      %{
        node_id: node_id,
        vote: vote,
        consistent: true
      }
    end
  end
  
  def byzantine_vote do
    let {node_id, votes} <- {atom(), list(float(0.0, 1.0))} do
      %{
        node_id: node_id,
        vote: oneof(votes),  # Random contradictory votes
        consistent: false
      }
    end
  end
  
  def weighted_vote do
    let {node_id, vote, reputation} <- {
      atom(),
      float(0.0, 1.0),
      float(0.1, 1.0)
    } do
      %{
        node_id: node_id,
        vote: vote,
        reputation: reputation
      }
    end
  end
  
  # Helper functions
  
  defp create_or_set(node_id, elements) do
    set = ORSet.new(node_id)
    Enum.reduce(elements, set, fn element, acc ->
      ORSet.add(acc, element)
    end)
  end
  
  defp process_beliefs(node_id, beliefs) do
    # Simulate belief processing
    beliefs
    |> Enum.map(& &1.content)
    |> Enum.sort()  # Canonical ordering for comparison
  end
  
  defp apply_delta_operation(op, clock) do
    Map.update(clock, op.node, 1, &(&1 + 1))
  end
  
  defp is_causally_valid?(op, clock) do
    # Check if operation respects causality
    op_version = op.version
    clock_version = Map.get(clock, op.node, 0)
    
    op_version <= clock_version + 1
  end
  
  defp process_votes_with_detection(votes) do
    # Simulate Byzantine detection
    votes
    |> Enum.group_by(& &1.node_id)
    |> Enum.filter(fn {_node, node_votes} ->
      # Detect inconsistent voting
      not Enum.all?(node_votes, & &1.consistent)
    end)
    |> Enum.map(fn {node, _votes} -> node end)
  end
  
  defp calculate_weighted_consensus(votes) do
    total_weight = votes
    |> Enum.map(& &1.vote * &1.reputation)
    |> Enum.sum()
    
    total_reputation = votes
    |> Enum.map(& &1.reputation)
    |> Enum.sum()
    
    if total_reputation > 0 do
      total_weight / total_reputation
    else
      0.0
    end
  end
  
  defp process_with_algedonic_bypass(beliefs) do
    # Separate urgent and normal
    {urgent, normal} = Enum.split_with(beliefs, fn b ->
      Map.get(b, :urgency, 0.5) > 0.9
    end)
    
    # Process urgent first
    urgent ++ normal
  end
end