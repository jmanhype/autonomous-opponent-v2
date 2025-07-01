defmodule AutonomousOpponentV2.EventBus.Registry do
  @moduledoc """
  A registry for managing event handlers with pattern matching support.
  """

  use GenServer
  require Logger

  defmodule State do
    @moduledoc false
    defstruct handlers: %{}, compiled_patterns: %{}, pattern_cache: %{}
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def subscribe(topic_pattern, handler)
      when is_binary(topic_pattern) and is_function(handler, 2) do
    GenServer.call(__MODULE__, {:subscribe, topic_pattern, handler})
  end

  def unsubscribe(topic_pattern, handler)
      when is_binary(topic_pattern) and is_function(handler, 2) do
    GenServer.call(__MODULE__, {:unsubscribe, topic_pattern, handler})
  end

  def get_handlers(event_topic) when is_binary(event_topic) do
    GenServer.call(__MODULE__, {:get_handlers, event_topic})
  end

  @impl true
  def init(_opts) do
    {:ok, %State{}}
  end

  @impl true
  def handle_call({:subscribe, topic_pattern, handler}, _from, state) do
    new_state = do_subscribe(topic_pattern, handler, state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:unsubscribe, topic_pattern, handler}, _from, state) do
    new_state = do_unsubscribe(topic_pattern, handler, state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get_handlers, event_topic}, _from, state) do
    {handlers, new_state} = do_get_handlers(event_topic, state)
    {:reply, handlers, new_state}
  end

  defp do_subscribe(topic_pattern, handler, state) do
    current_handlers = Map.get(state.handlers, topic_pattern, [])
    new_handlers = [handler | current_handlers]

    compiled_patterns =
      if Map.has_key?(state.compiled_patterns, topic_pattern) do
        state.compiled_patterns
      else
        Map.put(state.compiled_patterns, topic_pattern, compile_pattern(topic_pattern))
      end

    %{
      state
      | handlers: Map.put(state.handlers, topic_pattern, new_handlers),
        compiled_patterns: compiled_patterns,
        pattern_cache: %{}
    }
  end

  defp do_unsubscribe(topic_pattern, handler, state) do
    case Map.get(state.handlers, topic_pattern) do
      nil ->
        state
      handlers ->
        new_handlers = List.delete(handlers, handler)
        if Enum.empty?(new_handlers) do
          %{
            state
            | handlers: Map.delete(state.handlers, topic_pattern),
              compiled_patterns: Map.delete(state.compiled_patterns, topic_pattern),
              pattern_cache: %{}
          }
        else
          %{
            state
            | handlers: Map.put(state.handlers, topic_pattern, new_handlers),
              pattern_cache: %{}
          }
        end
    end
  end

  defp do_get_handlers(event_topic, state) do
    case Map.get(state.pattern_cache, event_topic) do
      nil ->
        matching_patterns = find_matching_patterns(event_topic, state.compiled_patterns)
        handlers = get_handlers_for_patterns(matching_patterns, state.handlers)
        new_cache = Map.put(state.pattern_cache, event_topic, matching_patterns)
        {%{state | pattern_cache: new_cache}, handlers}
      cached_patterns ->
        {state, get_handlers_for_patterns(cached_patterns, state.handlers)}
    end
  end

  defp find_matching_patterns(event_topic, compiled_patterns) do
    compiled_patterns
    |> Enum.filter(fn {_pattern, regex} -> Regex.match?(regex, event_topic) end)
    |> Enum.map(fn {pattern, _} -> pattern end)
  end

  defp get_handlers_for_patterns(patterns, handlers_map) do
    patterns
    |> Enum.flat_map(fn pattern -> Map.get(handlers_map, pattern, []) end)
    |> Enum.uniq()
  end

  defp compile_pattern(pattern) do
    regex_pattern =
      pattern
      |> String.replace(".", "\\.")
      |> String.replace("*", "[^.]+")
      |> String.replace("**", ".*")
      |> then(&("^" <> &1 <> "$"))

    {:ok, regex} = Regex.compile(regex_pattern)
    regex
  end
end
