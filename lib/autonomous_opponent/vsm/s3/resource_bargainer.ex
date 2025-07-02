defmodule AutonomousOpponent.VSM.S3.ResourceBargainer do
  @moduledoc """
  Implements Beer's resource bargaining algorithms for S3 Control.

  This module handles negotiation between S1 operational units for
  optimal resource allocation based on performance metrics and
  system-wide objectives.
  """

  require Logger

  @type participant :: String.t()
  @type allocation :: map()
  @type resource_pool :: map()
  @type performance_targets :: map()

  @doc """
  Run a bargaining round between participants
  """
  def negotiate(participants, current_allocations, resource_pool, performance_targets) do
    Logger.info("Starting resource bargaining with #{length(participants)} participants")

    # Calculate initial state
    initial_state = %{
      participants: participants,
      allocations: current_allocations,
      pool: resource_pool,
      targets: performance_targets,
      bids: %{},
      offers: %{},
      round: 0
    }

    # Run bargaining rounds until convergence or max rounds
    final_state = run_bargaining_rounds(initial_state)

    # Extract reallocations from final state
    calculate_reallocations(initial_state.allocations, final_state.allocations)
  end

  # Private functions

  defp run_bargaining_rounds(state, max_rounds \\ 10) do
    if converged?(state) or state.round >= max_rounds do
      state
    else
      state
      |> collect_bids()
      |> collect_offers()
      |> match_bids_and_offers()
      |> apply_trades()
      |> Map.update!(:round, &(&1 + 1))
      |> run_bargaining_rounds(max_rounds)
    end
  end

  defp collect_bids(state) do
    # Each participant evaluates their needs and creates bids
    bids =
      Enum.map(state.participants, fn participant ->
        current_alloc = Map.get(state.allocations, participant, %{})
        performance = estimate_performance(participant, current_alloc)

        # Generate bids for resources they need more of
        resource_bids =
          Enum.map([:cpu, :memory, :variety_capacity], fn resource ->
            if needs_more_resource?(participant, resource, performance, state.targets) do
              %{
                participant: participant,
                resource: resource,
                amount: calculate_bid_amount(resource, performance),
                urgency: calculate_urgency(performance, state.targets),
                max_price: calculate_max_price(resource, performance)
              }
            end
          end)
          |> Enum.filter(&(&1 != nil))

        {participant, resource_bids}
      end)
      |> Map.new()

    %{state | bids: bids}
  end

  defp collect_offers(state) do
    # Participants with excess resources create offers
    offers =
      Enum.map(state.participants, fn participant ->
        current_alloc = Map.get(state.allocations, participant, %{})
        performance = estimate_performance(participant, current_alloc)

        # Generate offers for resources they can spare
        resource_offers =
          Enum.map([:cpu, :memory, :variety_capacity], fn resource ->
            if can_spare_resource?(participant, resource, performance, state.targets) do
              %{
                participant: participant,
                resource: resource,
                amount: calculate_offer_amount(resource, performance, current_alloc),
                min_price: calculate_min_price(resource, performance)
              }
            end
          end)
          |> Enum.filter(&(&1 != nil))

        {participant, resource_offers}
      end)
      |> Map.new()

    %{state | offers: offers}
  end

  defp match_bids_and_offers(state) do
    # Use Beer's bargaining algorithm to match bids and offers
    matches = []

    # Sort bids by urgency (descending) and offers by price (ascending)
    all_bids =
      state.bids
      |> Map.values()
      |> List.flatten()
      |> Enum.sort_by(& &1.urgency, :desc)

    all_offers =
      state.offers
      |> Map.values()
      |> List.flatten()
      |> Enum.sort_by(& &1.min_price, :asc)

    # Match using greedy algorithm with price discovery
    {matched_trades, _remaining_bids, _remaining_offers} =
      match_greedy(all_bids, all_offers, [])

    Map.put(state, :matched_trades, matched_trades)
  end

  defp match_greedy([], _offers, matches), do: {matches, [], []}
  defp match_greedy(_bids, [], matches), do: {matches, [], []}

  defp match_greedy([bid | rest_bids] = bids, [offer | rest_offers] = offers, matches) do
    if can_match?(bid, offer) do
      # Create a trade
      trade_amount = min(bid.amount, offer.amount)

      trade = %{
        from: offer.participant,
        to: bid.participant,
        resource: bid.resource,
        amount: trade_amount,
        price: (bid.max_price + offer.min_price) / 2
      }

      # Update bid and offer amounts
      new_bid = %{bid | amount: bid.amount - trade_amount}
      new_offer = %{offer | amount: offer.amount - trade_amount}

      # Continue matching with updated amounts
      new_bids = if new_bid.amount > 0, do: [new_bid | rest_bids], else: rest_bids
      new_offers = if new_offer.amount > 0, do: [new_offer | rest_offers], else: rest_offers

      match_greedy(new_bids, new_offers, [trade | matches])
    else
      # Try next offer for this bid
      case match_greedy([bid], rest_offers, matches) do
        {matches, _, _} when matches != [] ->
          match_greedy(rest_bids, offers, matches)

        _ ->
          # No match for this bid, try next bid
          match_greedy(rest_bids, offers, matches)
      end
    end
  end

  defp can_match?(bid, offer) do
    bid.resource == offer.resource and
      bid.max_price >= offer.min_price and
      bid.participant != offer.participant
  end

  defp apply_trades(state) do
    # Apply matched trades to allocations
    new_allocations =
      Enum.reduce(state.matched_trades, state.allocations, fn trade, allocs ->
        allocs
        |> update_in([trade.from, :resources, trade.resource], &((&1 || 0) - trade.amount))
        |> update_in([trade.to, :resources, trade.resource], &((&1 || 0) + trade.amount))
      end)

    %{state | allocations: new_allocations}
  end

  defp converged?(state) do
    # Check if bargaining has converged
    state.round > 0 and Enum.empty?(state.matched_trades || [])
  end

  defp calculate_reallocations(initial_allocations, final_allocations) do
    # Calculate the net reallocations needed
    reallocations = []

    Enum.each(final_allocations, fn {participant, final_alloc} ->
      initial_alloc = Map.get(initial_allocations, participant, %{resources: %{}})

      Enum.each([:cpu, :memory, :variety_capacity], fn resource ->
        initial_amount = get_in(initial_alloc, [:resources, resource]) || 0
        final_amount = get_in(final_alloc, [:resources, resource]) || 0

        if final_amount != initial_amount do
          # Record reallocation
          # This is simplified - real implementation would batch these
          {:reallocation, participant, resource, final_amount - initial_amount}
        end
      end)
    end)

    %{
      reallocations: reallocations,
      trades: Map.get(state, :matched_trades, []),
      rounds: state.round
    }
  end

  defp estimate_performance(participant, allocation) do
    # Estimate performance based on current allocation
    # In reality, this would query actual S1 performance metrics
    %{
      variety_absorption: 0.7 + :rand.uniform() * 0.2,
      response_time: 80 + :rand.uniform() * 40,
      utilization: calculate_utilization(allocation)
    }
  end

  defp needs_more_resource?(participant, resource, performance, targets) do
    case resource do
      :cpu ->
        performance.response_time > targets.response_time

      :memory ->
        performance.utilization > 0.9

      :variety_capacity ->
        performance.variety_absorption < targets.variety_absorption

      _ ->
        false
    end
  end

  defp can_spare_resource?(participant, resource, performance, targets) do
    case resource do
      :cpu ->
        performance.response_time < targets.response_time * 0.8

      :memory ->
        performance.utilization < 0.6

      :variety_capacity ->
        performance.variety_absorption > targets.variety_absorption

      _ ->
        false
    end
  end

  defp calculate_bid_amount(resource, performance) do
    # Calculate how much of a resource to bid for
    case resource do
      :cpu ->
        max(10, (performance.response_time - 80) * 2)

      :memory ->
        max(64, (performance.utilization - 0.7) * 512)

      :variety_capacity ->
        max(100, (0.9 - performance.variety_absorption) * 1000)

      _ ->
        0
    end
  end

  defp calculate_offer_amount(resource, performance, allocation) do
    # Calculate how much of a resource can be offered
    current = get_in(allocation, [:resources, resource]) || 0

    case resource do
      :cpu ->
        # Offer up to 20% of CPU
        max(0, current * 0.2)

      :memory ->
        # Offer up to 30% of memory
        max(0, current * 0.3)

      :variety_capacity ->
        # Offer up to 25% of variety capacity
        max(0, current * 0.25)

      _ ->
        0
    end
  end

  defp calculate_urgency(performance, targets) do
    # Higher urgency for worse performance relative to targets
    variety_gap = max(0, targets.variety_absorption - performance.variety_absorption)

    response_gap =
      max(0, performance.response_time - targets.response_time) / targets.response_time

    (variety_gap + response_gap) * 10
  end

  defp calculate_max_price(resource, performance) do
    # Maximum "price" willing to pay (in abstract units)
    base_price =
      case resource do
        :cpu -> 10
        :memory -> 5
        :variety_capacity -> 8
        _ -> 1
      end

    base_price *
      (1 + calculate_urgency(performance, %{variety_absorption: 0.9, response_time: 100}) / 10)
  end

  defp calculate_min_price(resource, performance) do
    # Minimum "price" to accept for resource
    base_price =
      case resource do
        :cpu -> 10
        :memory -> 5
        :variety_capacity -> 8
        _ -> 1
      end

    # Willing to accept 50% of base price
    base_price * 0.5
  end

  defp calculate_utilization(allocation) do
    # Simple utilization calculation
    resources = allocation[:resources] || %{}

    if map_size(resources) == 0 do
      0.0
    else
      # Average utilization across resources
      total = Enum.sum(Map.values(resources))
      if total > 0, do: min(1.0, total / 1000), else: 0.0
    end
  end
end
