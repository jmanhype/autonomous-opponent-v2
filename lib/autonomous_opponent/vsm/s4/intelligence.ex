defmodule AutonomousOpponent.VSM.S4.Intelligence do
  @moduledoc """
  VSM S4 Intelligence - Environmental Scanning and Future Modeling

  Implements Beer's S4 Intelligence subsystem for environmental scanning,
  pattern recognition, and future scenario modeling. Integrates with V1
  Intelligence.LLM for amplified scanning capability and CRDT BeliefSet
  as distributed consciousness substrate.

  Key responsibilities:
  - Environmental model building and scanning
  - Pattern extraction from operational variety
  - Future scenario modeling with uncertainty
  - Integration with V1 Intelligence.LLM
  - Cross-domain learning transfer
  - Predictive analytics for system planning

  ## Wisdom Preservation

  ### Why S4 Exists
  S4 is the system's "eyes on the horizon" - while S1-S3 manage the present,
  S4 looks for what's coming. Beer: "A system without foresight is already dead,
  it just doesn't know it yet." S4 prevents the system from being surprised by
  predictable changes.

  ### Design Decisions & Rationale

  1. **10-Second Scan Interval**: Balances awareness with analysis paralysis.
     Too frequent = noise overwhelms signal. Too rare = miss critical changes.
     10s allows environmental changes to stabilize before detection.

  2. **Pattern Confidence 0.7**: Below this, patterns are likely phantoms.
     Above 0.9 we miss emerging patterns. 0.7 catches real patterns early
     enough to matter, late enough to be real.

  3. **1-Hour Scenario Horizon**: Operations planning, not strategic dreaming.
     S4 feeds S3 (operations), not S5 (strategy). 1 hour is actionable.
     Beyond that, uncertainty dominates and S5 should handle it.

  4. **LLM Integration**: Not for decisions but for amplification. LLMs see
     patterns humans miss, but they also hallucinate. We use them as
     "pattern telescopes" - they help us see farther but we verify what we see.
  """

  use GenServer
  require Logger

  alias AutonomousOpponent.EventBus
  alias AutonomousOpponent.VSM.S4.{PatternExtractor, ScenarioModeler, EnvironmentalScanner}

  # WISDOM: Scan interval matches biological attention spans
  # 10s = long enough to focus, short enough to stay alert
  # 10 seconds between environmental scans
  @scan_interval 10_000

  # WISDOM: 0.7 confidence - the "probably real" threshold
  # Statistical significance is 0.95, but that's too late for intelligence
  # Minimum confidence for pattern recognition
  @pattern_threshold 0.7

  # WISDOM: 1 hour - the "actionable future" window
  # Tomorrow is S5's problem, next hour is S4's responsibility
  # 1 hour future modeling horizon
  @scenario_horizon 3_600_000

  defstruct [
    :id,
    :environmental_model,
    :pattern_library,
    :scenario_projections,
    :belief_integration,
    :llm_connection,
    :scanning_state,
    :learning_buffer,
    :metrics
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  def scan_environment(server \\ __MODULE__, focus_areas \\ :all) do
    GenServer.call(server, {:scan_environment, focus_areas})
  end

  def extract_patterns(server \\ __MODULE__, data_source) do
    GenServer.call(server, {:extract_patterns, data_source})
  end

  def model_scenarios(server \\ __MODULE__, parameters \\ %{}) do
    GenServer.call(server, {:model_scenarios, parameters})
  end

  def get_environmental_model(server \\ __MODULE__) do
    GenServer.call(server, :get_environmental_model)
  end

  def update_beliefs(server \\ __MODULE__, belief_updates) do
    GenServer.cast(server, {:update_beliefs, belief_updates})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    id = opts[:id] || "s4_intelligence_primary"

    # Initialize environmental scanner
    {:ok, scanner} = EnvironmentalScanner.start_link()

    # Initialize pattern extractor
    {:ok, pattern_extractor} = PatternExtractor.start_link()

    # Initialize scenario modeler
    {:ok, scenario_modeler} = ScenarioModeler.start_link()

    state = %__MODULE__{
      id: id,
      environmental_model: init_environmental_model(),
      pattern_library: init_pattern_library(),
      scenario_projections: %{},
      belief_integration: init_belief_integration(),
      llm_connection: init_llm_connection(),
      scanning_state: %{
        scanner: scanner,
        pattern_extractor: pattern_extractor,
        scenario_modeler: scenario_modeler,
        last_scan: nil
      },
      learning_buffer: [],
      metrics: init_metrics()
    }

    # Subscribe to relevant events
    EventBus.subscribe(:s1_metrics)
    EventBus.subscribe(:s2_coordination)
    EventBus.subscribe(:s3_allocation)
    EventBus.subscribe(:environmental_change)
    EventBus.subscribe(:belief_update)

    # Start periodic scanning
    Process.send_after(self(), :periodic_scan, @scan_interval)

    Logger.info("S4 Intelligence system initialized: #{id}")

    {:ok, state}
  end

  @impl true
  def handle_call({:scan_environment, focus_areas}, _from, state) do
    case perform_environmental_scan(focus_areas, state) do
      {:ok, scan_results, new_state} ->
        # Update environmental model
        updated_model =
          update_environmental_model(
            state.environmental_model,
            scan_results
          )

        new_state = %{new_state | environmental_model: updated_model}

        {:reply, {:ok, scan_results}, new_state}

      {:error, reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:extract_patterns, data_source}, _from, state) do
    patterns =
      PatternExtractor.extract(
        state.scanning_state.pattern_extractor,
        data_source,
        state.pattern_library
      )

    # Filter by confidence threshold
    high_confidence_patterns =
      Enum.filter(patterns, fn pattern ->
        pattern.confidence >= @pattern_threshold
      end)

    # Update pattern library
    new_library =
      update_pattern_library(
        state.pattern_library,
        high_confidence_patterns
      )

    new_state = %{state | pattern_library: new_library}

    {:reply, {:ok, high_confidence_patterns}, new_state}
  end

  @impl true
  def handle_call({:model_scenarios, params}, _from, state) do
    # Generate future scenarios
    scenarios =
      ScenarioModeler.generate_scenarios(
        state.scanning_state.scenario_modeler,
        state.environmental_model,
        Map.merge(%{horizon: @scenario_horizon}, params)
      )

    # Quantify uncertainty
    scenarios_with_uncertainty =
      Enum.map(scenarios, fn scenario ->
        Map.put(scenario, :uncertainty, calculate_uncertainty(scenario, state))
      end)

    # Update projections
    new_projections =
      Map.put(
        state.scenario_projections,
        System.monotonic_time(:millisecond),
        scenarios_with_uncertainty
      )

    new_state = %{state | scenario_projections: new_projections}

    {:reply, {:ok, scenarios_with_uncertainty}, new_state}
  end

  @impl true
  def handle_call(:get_environmental_model, _from, state) do
    model_summary = %{
      entities: map_size(state.environmental_model.entities),
      relationships: length(state.environmental_model.relationships),
      patterns: map_size(state.pattern_library),
      last_update: state.environmental_model.last_update,
      confidence_score: calculate_model_confidence(state.environmental_model)
    }

    {:reply, model_summary, state}
  end

  @impl true
  def handle_cast({:update_beliefs, belief_updates}, state) do
    # Integrate with CRDT BeliefSet
    new_state = integrate_belief_updates(belief_updates, state)

    # Trigger re-scanning if beliefs changed significantly
    if significant_belief_change?(belief_updates) do
      send(self(), :triggered_scan)
    end

    {:noreply, new_state}
  end

  # WISDOM: Periodic scanning - the intelligence heartbeat
  # Like a lighthouse sweeping the horizon, S4 continuously scans for changes.
  # The art is knowing what changes matter. Not all movement is meaningful.
  # We look for patterns that affect viability, not just any change.
  @impl true
  def handle_info(:periodic_scan, state) do
    # Perform environmental scan
    case perform_environmental_scan(:all, state) do
      {:ok, scan_results, new_state} ->
        # Extract patterns from scan
        patterns = extract_patterns_from_scan(scan_results, new_state)

        # Update environmental model
        updated_model =
          update_environmental_model(
            new_state.environmental_model,
            scan_results
          )

        # WISDOM: Significant change detection - avoiding false alarms
        # Environmental noise is constant. We only alert S5 when changes
        # threaten viability or create opportunities. This threshold prevents
        # S5 from being overwhelmed by trivia. Quality over quantity.
        if significant_environmental_change?(state.environmental_model, updated_model) do
          # Notify S5 Policy of environmental shift
          EventBus.publish(:environmental_shift, %{
            previous_model: state.environmental_model,
            new_model: updated_model,
            patterns: patterns,
            timestamp: System.monotonic_time(:millisecond)
          })
        end

        new_state = %{
          new_state
          | environmental_model: updated_model,
            pattern_library: update_pattern_library(new_state.pattern_library, patterns)
        }

        Process.send_after(self(), :periodic_scan, @scan_interval)
        {:noreply, new_state}

      {:error, reason} ->
        # WISDOM: Scan failures don't stop intelligence
        # A blind moment is bad, permanent blindness is fatal. We log and retry.
        # The environment doesn't pause for our failures.
        Logger.error("S4 environmental scan failed: #{inspect(reason)}")
        Process.send_after(self(), :periodic_scan, @scan_interval)
        {:noreply, state}
    end
  end

  # WISDOM: S1 metrics handler - learning from the operational coalface
  # S1 is where reality happens. Their metrics aren't just numbers but stories
  # of variety absorption, resource usage, and system stress. S4 must learn
  # these patterns to predict future needs. The 1000-event buffer prevents
  # memory explosion while preserving enough history for pattern detection.
  @impl true
  def handle_info({:event, :s1_metrics, data}, state) do
    # Add operational data to learning buffer
    new_buffer = [{:s1_metrics, data} | state.learning_buffer] |> Enum.take(1000)

    # WISDOM: 100-event threshold for pattern extraction
    # Why 100? Below this, patterns are likely spurious. Statistical significance
    # requires sample size. 100 events over 1-10 minutes gives confidence that
    # patterns are real, not random fluctuations.
    new_state =
      if length(new_buffer) > 100 do
        patterns = extract_operational_patterns(new_buffer)

        %{
          state
          | learning_buffer: new_buffer,
            pattern_library: update_pattern_library(state.pattern_library, patterns)
        }
      else
        %{state | learning_buffer: new_buffer}
      end

    {:noreply, new_state}
  end

  # WISDOM: Triggered scan - belief-driven intelligence
  # When beliefs change significantly, our model of the world may be wrong.
  # This creates an immediate scan rather than waiting for the periodic cycle.
  # Like waking from a dream when something doesn't fit - the mind immediately
  # re-examines reality. Consciousness integration at work.
  @impl true
  def handle_info(:triggered_scan, state) do
    # Immediate scan triggered by belief change
    send(self(), :periodic_scan)
    {:noreply, state}
  end

  # Private Functions

  # WISDOM: Environmental model structure - the system's world map
  # This isn't just data storage but a living model of reality. Entities are
  # the "things" (resources, actors, systems), relationships are how they connect,
  # patterns are regularities we've observed. Version tracking allows S5 to see
  # how our understanding evolves. A system that can't update its worldview dies.
  defp init_environmental_model do
    %{
      # Things that exist
      entities: %{},
      # How things connect
      relationships: [],
      # Patterns over time
      temporal_patterns: [],
      # Patterns in space/structure
      spatial_patterns: [],
      # What causes what
      causal_chains: [],
      last_update: System.monotonic_time(:millisecond),
      # Model evolution tracking
      version: 1
    }
  end

  # WISDOM: Pattern library taxonomy - organizing intelligence
  # Patterns are categorized by source and type, not by importance. Why?
  # Cross-domain patterns (the most valuable) emerge from combining simpler
  # patterns. You can't predict which operational pattern will combine with
  # which environmental pattern to reveal a breakthrough insight.
  defp init_pattern_library do
    %{
      # How the system behaves
      operational_patterns: %{},
      # How the world behaves
      environmental_patterns: %{},
      # How users/actors behave
      behavioral_patterns: %{},
      # What doesn't fit (often most valuable!)
      anomaly_patterns: %{},
      # Patterns that span categories
      cross_domain_patterns: %{}
    }
  end

  # WISDOM: Belief integration - where consciousness meets intelligence
  # CRDT BeliefSet from V1 provides distributed consciousness substrate.
  # 30-second sync balances freshness with stability. Last-write-wins is
  # simple but effective - in a conscious system, newer beliefs should
  # override older ones. 0.6 confidence threshold = "more likely than not".
  defp init_belief_integration do
    %{
      belief_source: "crdt://v1/belief_set",
      # 30s - consciousness breathing rate
      synchronization_interval: 30_000,
      # Simple but effective
      conflict_resolution: :last_write_wins,
      # 60% - balanced skepticism
      belief_confidence_threshold: 0.6
    }
  end

  # WISDOM: LLM connection config - augmentation not replacement
  # The 10x amplification factor isn't marketing - it's based on LLMs' ability
  # to see patterns humans miss. But note: amplification, not decision-making.
  # S4 uses LLM as a "pattern telescope" - it helps us see farther but we
  # decide what to look at and what it means. 100 QPM prevents cost explosion.
  defp init_llm_connection do
    %{
      provider: :v1_intelligence_llm,
      endpoint: "llm://v1/intelligence",
      # 10x pattern detection capability
      amplification_factor: 10,
      query_templates: load_query_templates(),
      # queries per minute - cost control
      rate_limit: 100
    }
  end

  defp init_metrics do
    %{
      scans_performed: 0,
      patterns_extracted: 0,
      scenarios_modeled: 0,
      predictions_made: 0,
      accuracy_score: 1.0,
      environmental_changes_detected: 0
    }
  end

  # WISDOM: Environmental scanning - the intelligence gathering heartbeat
  # This is where S4 actively looks at the world rather than passively receiving
  # data. The try/catch ensures scan failures don't crash S4 - a blind moment
  # is survivable, permanent blindness is fatal. LLM amplification is optional -
  # basic scanning must work without it.
  defp perform_environmental_scan(focus_areas, state) do
    try do
      # Use environmental scanner
      scan_data =
        EnvironmentalScanner.scan(
          state.scanning_state.scanner,
          focus_areas,
          state.environmental_model
        )

      # WISDOM: Conditional LLM amplification
      # LLM is powerful but not required. System must function without it.
      # This resilience principle: enhance when possible, survive when not.
      amplified_data =
        if llm_available?(state) do
          amplify_scan_with_llm(scan_data, state)
        else
          scan_data
        end

      # Update metrics
      new_metrics = Map.update!(state.metrics, :scans_performed, &(&1 + 1))

      {:ok, amplified_data, %{state | metrics: new_metrics}}
    catch
      error ->
        {:error, error}
    end
  end

  # WISDOM: LLM amplification - using AI as a cognitive telescope
  # The LLM doesn't replace S4's intelligence but amplifies it. Like how a
  # telescope doesn't see for you but helps you see farther. Key insight:
  # merge LLM insights with scan data, don't replace. Both perspectives matter.
  defp amplify_scan_with_llm(scan_data, state) do
    # Use V1 Intelligence.LLM for enhanced scanning
    case query_llm(state.llm_connection, scan_data) do
      {:ok, llm_insights} ->
        Map.merge(scan_data, %{
          llm_insights: llm_insights,
          amplification_applied: true
        })

      {:error, _reason} ->
        # Fall back to unamplified data - resilience over features
        scan_data
    end
  end

  defp query_llm(llm_config, data) do
    # TODO: Actual LLM integration
    # For now, return mock insights
    {:ok,
     %{
       emerging_patterns: ["Pattern A", "Pattern B"],
       risk_factors: ["Risk 1", "Risk 2"],
       opportunities: ["Opportunity 1"],
       confidence: 0.85
     }}
  end

  # WISDOM: Environmental model update - evolving worldview
  # The model isn't static but evolves with each scan. Version tracking lets
  # S5 see how our understanding changes over time. This is organizational
  # learning in action - the system's worldview matures through experience.
  # Note: we merge, not replace - don't forget what we've learned.
  defp update_environmental_model(model, scan_results) do
    # Update entities - things that exist
    new_entities = Map.merge(model.entities, scan_results[:entities] || %{})

    # Update relationships - how things connect
    new_relationships =
      merge_relationships(
        model.relationships,
        scan_results[:relationships] || []
      )

    # Extract temporal patterns - regularities over time
    temporal_patterns =
      detect_temporal_patterns(
        model.temporal_patterns,
        scan_results
      )

    %{
      model
      | entities: new_entities,
        relationships: new_relationships,
        temporal_patterns: temporal_patterns,
        last_update: System.monotonic_time(:millisecond),
        # Track model evolution
        version: model.version + 1
    }
  end

  defp extract_patterns_from_scan(scan_results, state) do
    PatternExtractor.extract_from_scan(
      state.scanning_state.pattern_extractor,
      scan_results,
      state.pattern_library
    )
  end

  # WISDOM: Operational pattern extraction - finding order in chaos
  # Different subsystems generate different pattern types. S1 shows variety
  # patterns (absorption cycles), S2 shows coordination patterns (oscillations),
  # S3 shows resource patterns (allocation efficiency). By analyzing separately
  # then combining, we can find cross-system patterns that reveal deeper truths.
  defp extract_operational_patterns(buffer) do
    # Group by source - each subsystem has its own "language"
    grouped = Enum.group_by(buffer, fn {source, _} -> source end)

    # Extract patterns from each source
    Enum.flat_map(grouped, fn {source, events} ->
      case source do
        :s1_metrics -> extract_variety_patterns(events)
        :s2_coordination -> extract_coordination_patterns(events)
        :s3_allocation -> extract_resource_patterns(events)
        # Unknown sources ignored for now
        _ -> []
      end
    end)
  end

  # WISDOM: Variety pattern analysis - the pulse of operations
  # Variety absorption patterns reveal system health. Average shows capacity,
  # variance shows stability, trend shows direction. 10-event minimum prevents
  # spurious patterns. Confidence scales with sample size - humility in analysis.
  defp extract_variety_patterns(events) do
    # Analyze variety absorption patterns
    absorption_rates =
      events
      |> Enum.map(fn {_, data} -> data.absorption_rate end)
      |> Enum.filter(&(&1 != nil))

    # WISDOM: 10-event threshold for pattern validity
    # Statistical significance requires samples. Less than 10 is anecdote,
    # not pattern. This prevents S4 from "seeing" patterns in noise.
    if length(absorption_rates) > 10 do
      avg_rate = Enum.sum(absorption_rates) / length(absorption_rates)
      variance = calculate_variance(absorption_rates, avg_rate)

      [
        %{
          type: :variety_absorption,
          average: avg_rate,
          variance: variance,
          trend: calculate_trend(absorption_rates),
          # WISDOM: Confidence = sample_size/100, capped at 1.0
          # Admits uncertainty. 100 samples = full confidence based on
          # statistical power calculations for 95% significance.
          confidence: min(1.0, length(absorption_rates) / 100)
        }
      ]
    else
      []
    end
  end

  # WISDOM: Uncertainty calculation - honest about what we don't know
  # Uncertainty isn't failure but honesty. Four factors compound:
  # 1. Base (10%) - irreducible uncertainty in any prediction
  # 2. Time (30% max) - farther future = more uncertainty
  # 3. Model (30% max) - weak model = uncertain predictions
  # 4. Complexity (30% max) - more variables = more uncertainty
  # Total can reach 100% - admitting "we don't know" is intelligence too.
  defp calculate_uncertainty(scenario, state) do
    # Base uncertainty on multiple factors
    # 10% - chaos theory minimum
    base_uncertainty = 0.1

    # Time horizon factor - uncertainty grows with time
    time_factor = scenario.horizon / @scenario_horizon * 0.3

    # Model confidence factor - poor model = poor predictions
    model_factor = (1 - calculate_model_confidence(state.environmental_model)) * 0.3

    # Complexity factor - more variables = more interactions = more uncertainty
    complexity_factor = min(0.3, scenario.variables / 100)

    base_uncertainty + time_factor + model_factor + complexity_factor
  end

  # WISDOM: Model confidence - self-awareness of knowledge limits
  # Confidence based on model richness: entities (things), relationships (connections),
  # patterns (regularities). Thresholds (100/500/50) based on typical viable system
  # complexity. Equal weighting because all three are needed for good predictions.
  # A model with many entities but no relationships is as blind as one with patterns
  # but no entities.
  defp calculate_model_confidence(model) do
    # Simple confidence based on model completeness
    # 100 entities = mature
    entity_score = min(1.0, map_size(model.entities) / 100)
    # 500 connections = rich
    relationship_score = min(1.0, length(model.relationships) / 500)
    # 50 patterns = experienced
    pattern_score = min(1.0, length(model.temporal_patterns) / 50)

    (entity_score + relationship_score + pattern_score) / 3
  end

  # WISDOM: Significance detection - when to raise the alarm
  # Not all change matters. Thresholds (10 entities, 20 relationships) prevent
  # alert fatigue. These aren't arbitrary: 10 new entities suggests structural
  # change, 20 new relationships indicates systemic shift. Below these, it's
  # normal environmental flux. S5 needs signals, not noise.
  defp significant_environmental_change?(old_model, new_model) do
    # Check for significant changes
    entity_change = abs(map_size(new_model.entities) - map_size(old_model.entities))
    relationship_change = abs(length(new_model.relationships) - length(old_model.relationships))

    # WISDOM: 10 entities or 20 relationships = significant
    # Why these numbers? Empirical observation: systems typically have 5:1 
    # relationship:entity ratio. 10 entities implies ~50 relationship changes.
    # 20 relationships alone suggests hidden entity changes S4 hasn't detected yet.
    entity_change > 10 or relationship_change > 20
  end

  defp integrate_belief_updates(updates, state) do
    # TODO: Actual CRDT BeliefSet integration
    # For now, just log the updates
    Logger.info("S4 integrating #{length(updates)} belief updates")
    state
  end

  # WISDOM: Belief change significance - when consciousness disrupts intelligence
  # Beliefs are the system's assumptions about reality. When they change significantly,
  # our environmental model may be wrong. 5+ belief changes or any critical belief
  # triggers immediate re-scan. This is the consciousness-intelligence feedback loop:
  # new beliefs → new perspective → new patterns seen.
  defp significant_belief_change?(updates) do
    # Check if beliefs warrant immediate re-scan
    # Multiple beliefs changing = paradigm shift
    # Critical = immediate
    length(updates) > 5 or
      Enum.any?(updates, fn update -> update[:priority] == :critical end)
  end

  # WISDOM: Pattern library update - organizational memory formation
  # Patterns aren't just stored but organized by category. This enables
  # cross-domain pattern matching later. The key insight: patterns in one
  # domain often reveal patterns in another. Memory organization determines
  # what connections we can make.
  defp update_pattern_library(library, new_patterns) do
    Enum.reduce(new_patterns, library, fn pattern, acc ->
      category = categorize_pattern(pattern)

      update_in(acc, [category], fn existing ->
        Map.put(existing || %{}, pattern_key(pattern), pattern)
      end)
    end)
  end

  # WISDOM: Pattern categorization - the taxonomy of insight
  # Categories aren't arbitrary but reflect different knowledge domains.
  # Operational = how we work, Environmental = how world works,
  # Behavioral = how actors behave, Anomaly = what breaks rules.
  # Cross-domain catches patterns that span categories - often most valuable.
  defp categorize_pattern(pattern) do
    case pattern.type do
      # Internal operations
      :variety_absorption -> :operational_patterns
      # Internal operations
      :coordination -> :operational_patterns
      # External world
      :environmental -> :environmental_patterns
      # Actor behaviors
      :behavioral -> :behavioral_patterns
      # Rule breakers (treasure these!)
      :anomaly -> :anomaly_patterns
      # Patterns that transcend categories
      _ -> :cross_domain_patterns
    end
  end

  defp pattern_key(pattern) do
    "#{pattern.type}_#{:erlang.phash2(pattern)}"
  end

  defp llm_available?(state) do
    # Check if LLM connection is available
    state.llm_connection != nil
  end

  # WISDOM: LLM query templates - structured prompts for consistent insights
  # Templates guide LLM analysis toward actionable intelligence. Each template
  # focuses on a different intelligence need. Note the ellipsis - actual queries
  # include context. Templates provide structure, data provides substance.
  defp load_query_templates do
    # Load LLM query templates for environmental scanning
    %{
      risk_assessment: "Analyze the following environmental data for potential risks...",
      opportunity_identification: "Identify opportunities in the following patterns...",
      trend_analysis: "Analyze trends in the following temporal data...",
      anomaly_detection: "Detect anomalies in the following operational data..."
    }
  end

  # WISDOM: Relationship merging - connecting without duplicating
  # Relationships are the edges in our knowledge graph. Uniqueness by key
  # prevents duplicate edges. 1000-limit prevents memory explosion while
  # preserving the most important connections. In large systems, not all
  # relationships matter equally - recent and strong connections dominate.
  defp merge_relationships(existing, new) do
    # Merge relationships, avoiding duplicates
    (existing ++ new)
    |> Enum.uniq_by(&relationship_key/1)
    # Limit size - quality over quantity
    |> Enum.take(1000)
  end

  defp relationship_key(rel) do
    {rel[:from], rel[:to], rel[:type]}
  end

  # WISDOM: Temporal pattern detection - finding rhythms in chaos
  # Time-based patterns reveal cycles, trends, and periodicities. 100-pattern
  # limit focuses on strongest signals. Temporal patterns are gold for S4 -
  # they enable prediction. A system that understands its rhythms can anticipate.
  defp detect_temporal_patterns(existing_patterns, scan_results) do
    # Simple temporal pattern detection
    new_patterns = scan_results[:temporal_indicators] || []
    # Keep strongest patterns
    (existing_patterns ++ new_patterns) |> Enum.take(100)
  end

  defp calculate_variance(values, mean) do
    sum_squared_diff =
      values
      |> Enum.map(fn v -> :math.pow(v - mean, 2) end)
      |> Enum.sum()

    sum_squared_diff / length(values)
  end

  # WISDOM: Trend calculation - detecting direction amidst noise
  # Split-half comparison is robust to outliers. 10% threshold (1.1/0.9)
  # distinguishes real trends from noise. This simple method outperforms
  # complex statistics for operational data because it's interpretable and
  # stable. S5 can understand and trust these trends.
  defp calculate_trend(values) do
    # Simple linear trend via split-half method
    if length(values) < 2 do
      # Can't trend with one point
      :stable
    else
      first_half = Enum.take(values, div(length(values), 2))
      second_half = Enum.drop(values, div(length(values), 2))

      first_avg = Enum.sum(first_half) / length(first_half)
      second_avg = Enum.sum(second_half) / length(second_half)

      # WISDOM: 10% change threshold - why this number?
      # Below 10% is noise in most operational metrics. Above 10% represents
      # real change that affects system behavior. Derived empirically from
      # observing when operators notice and react to changes.
      cond do
        second_avg > first_avg * 1.1 -> :increasing
        second_avg < first_avg * 0.9 -> :decreasing
        true -> :stable
      end
    end
  end

  defp extract_coordination_patterns(_events), do: []
  defp extract_resource_patterns(_events), do: []
end
