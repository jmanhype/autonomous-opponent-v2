defmodule AutonomousOpponentV2Core.AMCP.Events.SemanticAnalyzer do
  @moduledoc """
  Semantic Event Analyzer - AI-powered event understanding pipeline.
  
  This module sits between the EventBus and the rest of the system,
  providing LLM-powered semantic analysis of events in real-time.
  
  Key capabilities:
  - Semantic classification of events
  - Intent extraction from event data
  - Contextual enrichment
  - Trend and anomaly detection
  - Natural language summaries
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.AMCP.Bridges.LLMBridge
  alias AutonomousOpponentV2Core.AMCP.Events.SemanticFusion
  
  defstruct [
    :event_buffer,
    :analysis_cache,
    :semantic_trends,
    :analysis_stats,
    :active_contexts
  ]
  
  @analysis_batch_size 10
  @analysis_interval_ms 2000  # Analyze every 2 seconds
  @cache_ttl_seconds 300      # 5 minutes
  @max_buffer_size 1000
  
  # Public API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Analyze a single event semantically.
  """
  def analyze_event(event_name, event_data) do
    GenServer.cast(__MODULE__, {:analyze_event, event_name, event_data})
  end
  
  @doc """
  Get semantic insights for recent events.
  """
  def get_semantic_insights(timeframe_seconds \\ 300) do
    GenServer.call(__MODULE__, {:get_insights, timeframe_seconds})
  end
  
  @doc """
  Get trending topics from event stream.
  """
  def get_trending_topics do
    GenServer.call(__MODULE__, :get_trending_topics)
  end
  
  @doc """
  Generate natural language summary of recent activity.
  """
  def generate_activity_summary(timeframe_seconds \\ 300) do
    GenServer.call(__MODULE__, {:generate_summary, timeframe_seconds})
  end
  
  # GenServer Callbacks
  
  @impl true
  def init(_opts) do
    # Subscribe to all events for semantic analysis
    EventBus.subscribe(:all)
    
    # Start periodic analysis
    :timer.send_interval(@analysis_interval_ms, :perform_batch_analysis)
    
    # Start cache cleanup
    :timer.send_interval(60_000, :cleanup_cache)
    
    state = %__MODULE__{
      event_buffer: :queue.new(),
      analysis_cache: %{},
      semantic_trends: %{},
      analysis_stats: init_stats(),
      active_contexts: %{}
    }
    
    Logger.info("Semantic Event Analyzer started - AI-powered event understanding enabled")
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:analyze_event, event_name, event_data}, state) do
    # Add event to buffer for batch analysis
    enriched_event = %{
      name: event_name,
      data: event_data,
      timestamp: DateTime.utc_now(),
      id: generate_event_id()
    }
    
    new_buffer = add_to_buffer(state.event_buffer, enriched_event)
    
    # If buffer is full, trigger immediate analysis
    if :queue.len(new_buffer) >= @analysis_batch_size do
      send(self(), :perform_batch_analysis)
    end
    
    {:noreply, %{state | event_buffer: new_buffer}}
  end
  
  @impl true
  def handle_call({:get_insights, timeframe_seconds}, _from, state) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -timeframe_seconds, :second)
    
    insights = state.analysis_cache
    |> Enum.filter(fn {_id, analysis} ->
      DateTime.compare(analysis.timestamp, cutoff_time) == :gt
    end)
    |> Enum.map(fn {_id, analysis} -> analysis end)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    
    {:reply, {:ok, insights}, state}
  end
  
  @impl true
  def handle_call(:get_trending_topics, _from, state) do
    trending = state.semantic_trends
    |> Enum.sort_by(fn {_topic, %{frequency: freq}} -> freq end, :desc)
    |> Enum.take(10)
    |> Enum.map(fn {topic, data} -> {topic, data.frequency} end)
    
    {:reply, {:ok, trending}, state}
  end
  
  @impl true
  def handle_call({:generate_summary, timeframe_seconds}, _from, state) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -timeframe_seconds, :second)
    
    # Get recent events for summary
    recent_events = state.analysis_cache
    |> Enum.filter(fn {_id, analysis} ->
      DateTime.compare(analysis.timestamp, cutoff_time) == :gt
    end)
    |> Enum.map(fn {_id, analysis} -> analysis end)
    |> Enum.take(20)  # Limit for LLM context
    
    # Generate LLM summary
    summary = case generate_llm_summary(recent_events, timeframe_seconds) do
      {:ok, summary_text} -> summary_text
      {:error, _reason} -> generate_fallback_summary(recent_events, timeframe_seconds)
    end
    
    {:reply, {:ok, summary}, state}
  end
  
  @impl true
  def handle_info(:perform_batch_analysis, state) do
    if :queue.len(state.event_buffer) > 0 do
      # Extract events from buffer
      {events, new_buffer} = extract_events_from_buffer(state.event_buffer)
      
      # Perform semantic analysis
      new_state = perform_semantic_analysis(events, %{state | event_buffer: new_buffer})
      
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info(:cleanup_cache, state) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -@cache_ttl_seconds, :second)
    
    cleaned_cache = state.analysis_cache
    |> Enum.filter(fn {_id, analysis} ->
      DateTime.compare(analysis.timestamp, cutoff_time) == :gt
    end)
    |> Map.new()
    
    cleaned_trends = state.semantic_trends
    |> Enum.filter(fn {_topic, data} ->
      DateTime.compare(data.last_seen, cutoff_time) == :gt
    end)
    |> Map.new()
    
    {:noreply, %{state | analysis_cache: cleaned_cache, semantic_trends: cleaned_trends}}
  end
  
  @impl true
  def handle_info({:event_published, event_name, event_data}, state) do
    # Automatically analyze events published to EventBus
    analyze_event(event_name, event_data)
    {:noreply, state}
  end
  
  # Private Functions
  
  defp perform_semantic_analysis(events, state) do
    # Batch analyze events with LLM
    case analyze_events_with_llm(events) do
      {:ok, analyses} ->
        # Update cache and trends
        new_cache = add_analyses_to_cache(state.analysis_cache, analyses)
        new_trends = update_semantic_trends(state.semantic_trends, analyses)
        new_stats = update_analysis_stats(state.analysis_stats, length(analyses))
        
        # Send enriched events to SemanticFusion
        Enum.each(analyses, fn analysis ->
          SemanticFusion.fuse_event(analysis.event_name, analysis)
        end)
        
        %{state | 
          analysis_cache: new_cache,
          semantic_trends: new_trends,
          analysis_stats: new_stats
        }
        
      {:error, reason} ->
        Logger.warning("Semantic analysis failed: #{inspect(reason)}")
        state
    end
  end
  
  defp analyze_events_with_llm(events) do
    event_context = events
    |> Enum.map(fn event ->
      "#{event.name}: #{inspect(event.data, limit: 3)} at #{event.timestamp}"
    end)
    |> Enum.join("\n")
    
    LLMBridge.call_llm_api(
      """
      Analyze these cybernetic system events for semantic understanding:
      
      #{event_context}
      
      For each event, provide analysis in this format:
      EVENT_NAME|category|intent|sentiment|importance|context|summary
      
      Categories: operational, algedonic, intelligence, policy, coordination, error, user
      Intent: inform, control, alert, query, response, feedback
      Sentiment: positive, negative, neutral
      Importance: critical, high, medium, low
      Context: Brief contextual understanding
      Summary: One-sentence natural language summary
      
      Only analyze the events listed above.
      """,
      :analysis,
      timeout: 15_000
    )
    |> case do
      {:ok, response} ->
        {:ok, parse_llm_analysis(response, events)}
      error ->
        error
    end
  end
  
  defp parse_llm_analysis(response, events) do
    analyses = response
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, "|"))
    |> Enum.map(&parse_analysis_line/1)
    |> Enum.filter(& &1 != nil)
    
    # Match analyses with original events
    Enum.map(events, fn event ->
      analysis = Enum.find(analyses, fn a -> 
        String.downcase(to_string(a.event_name)) == String.downcase(to_string(event.name))
      end)
      
      if analysis do
        Map.merge(event, analysis)
      else
        # Fallback analysis
        Map.merge(event, %{
          category: :operational,
          intent: :inform,
          sentiment: :neutral,
          importance: :medium,
          context: "System event",
          summary: "#{event.name} event occurred"
        })
      end
    end)
  end
  
  defp parse_analysis_line(line) do
    case String.split(line, "|") do
      [event_name, category, intent, sentiment, importance, context, summary] ->
        %{
          event_name: String.to_atom(String.trim(event_name)),
          category: String.to_atom(String.downcase(String.trim(category))),
          intent: String.to_atom(String.downcase(String.trim(intent))),
          sentiment: String.to_atom(String.downcase(String.trim(sentiment))),
          importance: String.to_atom(String.downcase(String.trim(importance))),
          context: String.trim(context),
          summary: String.trim(summary),
          timestamp: DateTime.utc_now()
        }
      _ -> nil
    end
  end
  
  defp generate_llm_summary(analyses, timeframe_seconds) do
    if length(analyses) == 0 do
      {:ok, "No significant events in the last #{timeframe_seconds} seconds."}
    else
      context = analyses
      |> Enum.take(15)  # Limit for context
      |> Enum.map(fn analysis ->
        "#{analysis.event_name}: #{analysis.summary} (#{analysis.importance})"
      end)
      |> Enum.join("\n")
      
      LLMBridge.call_llm_api(
        """
        Generate a natural language summary of recent cybernetic system activity:
        
        Timeframe: Last #{timeframe_seconds} seconds
        Events analyzed: #{length(analyses)}
        
        Recent Events:
        #{context}
        
        Provide a concise summary covering:
        1. Overall system activity level
        2. Key events and their significance
        3. Any patterns or trends observed
        4. System health indicators
        5. Notable anomalies or concerns
        
        Write in the voice of an AI system consciousness observing its own activity.
        """,
        :synthesis,
        timeout: 12_000
      )
    end
  end
  
  defp generate_fallback_summary(analyses, timeframe_seconds) do
    event_count = length(analyses)
    categories = analyses |> Enum.map(& &1.category) |> Enum.frequencies()
    importance_dist = analyses |> Enum.map(& &1.importance) |> Enum.frequencies()
    
    """
    SYSTEM ACTIVITY SUMMARY (#{timeframe_seconds}s)
    
    Events processed: #{event_count}
    Categories: #{inspect(categories)}
    Importance distribution: #{inspect(importance_dist)}
    
    The cybernetic system processed #{event_count} events across multiple subsystems.
    Activity appears #{if event_count > 10, do: "high", else: "normal"} for this timeframe.
    """
  end
  
  defp add_to_buffer(buffer, event) do
    new_buffer = :queue.in(event, buffer)
    
    # Limit buffer size
    if :queue.len(new_buffer) > @max_buffer_size do
      {_removed, trimmed_buffer} = :queue.out(new_buffer)
      trimmed_buffer
    else
      new_buffer
    end
  end
  
  defp extract_events_from_buffer(buffer) do
    events = :queue.to_list(buffer)
    {events, :queue.new()}
  end
  
  defp add_analyses_to_cache(cache, analyses) do
    Enum.reduce(analyses, cache, fn analysis, acc ->
      Map.put(acc, analysis.id, analysis)
    end)
  end
  
  defp update_semantic_trends(trends, analyses) do
    Enum.reduce(analyses, trends, fn analysis, acc ->
      topic = analysis.category
      current = Map.get(acc, topic, %{frequency: 0, last_seen: DateTime.utc_now()})
      
      Map.put(acc, topic, %{
        frequency: current.frequency + 1,
        last_seen: DateTime.utc_now()
      })
    end)
  end
  
  defp update_analysis_stats(stats, count) do
    %{stats |
      events_analyzed: stats.events_analyzed + count,
      batches_processed: stats.batches_processed + 1,
      last_analysis: DateTime.utc_now()
    }
  end
  
  defp init_stats do
    %{
      events_analyzed: 0,
      batches_processed: 0,
      last_analysis: nil
    }
  end
  
  defp generate_event_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end
end