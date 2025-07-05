defmodule AutonomousOpponentV2Core.AMCP.Goldrush.PluginManager do
  @moduledoc """
  Plugin management system for aMCP Goldrush Runtime.
  
  Provides pluggable architecture where developers can register:
  - Domain-specific event handlers
  - Metric transformers  
  - Behavior hooks tied to AMQP headers, payload shape, or stream labels
  - Custom context evaluators
  
  Supports hot-loading of plugins and graceful error handling.
  """
  
  use GenServer
  require Logger
  
  # alias AutonomousOpponentV2Core.EventBus
  
  defstruct [
    :plugins,
    :hooks,
    :transformers,
    :evaluators,
    :plugin_stats
  ]
  
  @type plugin_id :: atom() | String.t()
  @type hook_type :: :pre_process | :post_process | :on_error | :on_match
  @type plugin_spec :: %{
    id: plugin_id(),
    module: module(),
    config: map(),
    hooks: list(),
    priority: integer()
  }
  
  # Public API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Registers a plugin with the system.
  
  Plugin modules must implement the aMCP.Plugin behaviour.
  """
  def register_plugin(plugin_spec) do
    GenServer.call(__MODULE__, {:register_plugin, plugin_spec})
  end
  
  @doc """
  Unregisters a plugin.
  """
  def unregister_plugin(plugin_id) do
    GenServer.call(__MODULE__, {:unregister_plugin, plugin_id})
  end
  
  @doc """
  Lists all registered plugins.
  """
  def list_plugins do
    GenServer.call(__MODULE__, :list_plugins)
  end
  
  @doc """
  Executes pre-processing hooks for an event.
  """
  def execute_pre_hooks(event, context \\ %{}) do
    GenServer.call(__MODULE__, {:execute_hooks, :pre_process, event, context})
  end
  
  @doc """
  Executes post-processing hooks for an event.
  """
  def execute_post_hooks(event, context \\ %{}) do
    GenServer.call(__MODULE__, {:execute_hooks, :post_process, event, context})
  end
  
  @doc """
  Executes error handling hooks.
  """
  def execute_error_hooks(event, error, context \\ %{}) do
    GenServer.call(__MODULE__, {:execute_hooks, :on_error, event, %{error: error} |> Map.merge(context)})
  end
  
  @doc """
  Executes pattern match hooks.
  """
  def execute_match_hooks(event, pattern_id, match_context) do
    GenServer.call(__MODULE__, {:execute_hooks, :on_match, event, %{pattern_id: pattern_id, match_context: match_context}})
  end
  
  @doc """
  Applies metric transformers to an event.
  """
  def transform_metrics(event) do
    GenServer.call(__MODULE__, {:transform_metrics, event})
  end
  
  @doc """
  Evaluates context using registered evaluators.
  """
  def evaluate_context(event, context) do
    GenServer.call(__MODULE__, {:evaluate_context, event, context})
  end
  
  @doc """
  Gets plugin statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  # GenServer Callbacks
  
  @impl true
  def init(_opts) do
    state = %__MODULE__{
      plugins: %{},
      hooks: %{
        pre_process: [],
        post_process: [],
        on_error: [],
        on_match: []
      },
      transformers: [],
      evaluators: [],
      plugin_stats: %{}
    }
    
    # Load built-in plugins
    state = load_builtin_plugins(state)
    
    Logger.info("aMCP PluginManager started with #{map_size(state.plugins)} plugins")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:register_plugin, plugin_spec}, _from, state) do
    case validate_plugin_spec(plugin_spec) do
      :ok ->
        case register_plugin_internal(plugin_spec, state) do
          {:ok, new_state} ->
            Logger.info("Registered plugin: #{plugin_spec.id}")
            {:reply, :ok, new_state}
            
          {:error, reason} ->
            Logger.error("Failed to register plugin #{plugin_spec.id}: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:unregister_plugin, plugin_id}, _from, state) do
    case Map.get(state.plugins, plugin_id) do
      nil ->
        {:reply, {:error, :plugin_not_found}, state}
        
      plugin_spec ->
        new_state = unregister_plugin_internal(plugin_spec, state)
        Logger.info("Unregistered plugin: #{plugin_id}")
        {:reply, :ok, new_state}
    end
  end
  
  @impl true
  def handle_call(:list_plugins, _from, state) do
    plugins = state.plugins
    |> Enum.map(fn {id, spec} ->
      stats = Map.get(state.plugin_stats, id, %{})
      Map.merge(spec, %{stats: stats})
    end)
    
    {:reply, plugins, state}
  end
  
  @impl true
  def handle_call({:execute_hooks, hook_type, event, context}, _from, state) do
    hooks = Map.get(state.hooks, hook_type, [])
    {result, new_state} = execute_hooks_internal(hooks, event, context, state)
    {:reply, result, new_state}
  end
  
  @impl true
  def handle_call({:transform_metrics, event}, _from, state) do
    {transformed_event, new_state} = apply_transformers(state.transformers, event, state)
    {:reply, transformed_event, new_state}
  end
  
  @impl true
  def handle_call({:evaluate_context, event, context}, _from, state) do
    {evaluated_context, new_state} = apply_evaluators(state.evaluators, event, context, state)
    {:reply, evaluated_context, new_state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.plugin_stats, state}
  end
  
  # Private Functions
  
  defp validate_plugin_spec(%{id: id, module: module}) when is_atom(id) and is_atom(module) do
    case Code.ensure_loaded?(module) do
      true ->
        if function_exported?(module, :plugin_info, 0) do
          :ok
        else
          {:error, :missing_plugin_info}
        end
      false ->
        {:error, :module_not_found}
    end
  end
  
  defp validate_plugin_spec(_), do: {:error, :invalid_plugin_spec}
  
  defp register_plugin_internal(plugin_spec, state) do
    try do
      # Initialize the plugin
      case apply(plugin_spec.module, :init, [plugin_spec[:config] || %{}]) do
        {:ok, plugin_state} ->
          # Update plugin registry
          plugins = Map.put(state.plugins, plugin_spec.id, plugin_spec)
          
          # Register hooks
          hooks = register_plugin_hooks(plugin_spec, state.hooks)
          
          # Register transformers and evaluators
          {transformers, evaluators} = register_plugin_capabilities(plugin_spec, state.transformers, state.evaluators)
          
          # Initialize stats
          stats = Map.put(state.plugin_stats, plugin_spec.id, %{
            registered_at: DateTime.utc_now(),
            executions: 0,
            errors: 0,
            plugin_state: plugin_state
          })
          
          new_state = %{state |
            plugins: plugins,
            hooks: hooks,
            transformers: transformers,
            evaluators: evaluators,
            plugin_stats: stats
          }
          
          {:ok, new_state}
          
        {:error, reason} ->
          {:error, {:initialization_failed, reason}}
      end
    rescue
      error ->
        {:error, {:plugin_error, error}}
    end
  end
  
  defp unregister_plugin_internal(plugin_spec, state) do
    # Remove from plugins
    plugins = Map.delete(state.plugins, plugin_spec.id)
    
    # Remove hooks
    hooks = unregister_plugin_hooks(plugin_spec, state.hooks)
    
    # Remove transformers and evaluators
    {transformers, evaluators} = unregister_plugin_capabilities(plugin_spec, state.transformers, state.evaluators)
    
    # Remove stats
    stats = Map.delete(state.plugin_stats, plugin_spec.id)
    
    # Call plugin cleanup
    try do
      plugin_state = get_in(state.plugin_stats, [plugin_spec.id, :plugin_state])
      apply(plugin_spec.module, :terminate, [plugin_state])
    rescue
      error ->
        Logger.warning("Plugin cleanup failed for #{plugin_spec.id}: #{inspect(error)}")
    end
    
    %{state |
      plugins: plugins,
      hooks: hooks,
      transformers: transformers,
      evaluators: evaluators,
      plugin_stats: stats
    }
  end
  
  defp register_plugin_hooks(plugin_spec, current_hooks) do
    plugin_hooks = plugin_spec[:hooks] || []
    
    Enum.reduce(plugin_hooks, current_hooks, fn {hook_type, _hook_config}, acc_hooks ->
      current_list = Map.get(acc_hooks, hook_type, [])
      hook_entry = %{
        plugin_id: plugin_spec.id,
        module: plugin_spec.module,
        priority: plugin_spec[:priority] || 50
      }
      
      # Insert based on priority (higher priority first)
      new_list = insert_by_priority(current_list, hook_entry)
      Map.put(acc_hooks, hook_type, new_list)
    end)
  end
  
  defp unregister_plugin_hooks(plugin_spec, current_hooks) do
    Enum.reduce(current_hooks, %{}, fn {hook_type, hook_list}, acc ->
      filtered_list = Enum.reject(hook_list, fn hook ->
        hook.plugin_id == plugin_spec.id
      end)
      Map.put(acc, hook_type, filtered_list)
    end)
  end
  
  defp register_plugin_capabilities(plugin_spec, transformers, evaluators) do
    new_transformers = if function_exported?(plugin_spec.module, :transform_metrics, 1) do
      [%{plugin_id: plugin_spec.id, module: plugin_spec.module} | transformers]
    else
      transformers
    end
    
    new_evaluators = if function_exported?(plugin_spec.module, :evaluate_context, 2) do
      [%{plugin_id: plugin_spec.id, module: plugin_spec.module} | evaluators]
    else
      evaluators
    end
    
    {new_transformers, new_evaluators}
  end
  
  defp unregister_plugin_capabilities(plugin_spec, transformers, evaluators) do
    new_transformers = Enum.reject(transformers, &(&1.plugin_id == plugin_spec.id))
    new_evaluators = Enum.reject(evaluators, &(&1.plugin_id == plugin_spec.id))
    {new_transformers, new_evaluators}
  end
  
  defp insert_by_priority(list, new_item) do
    {before, after_items} = Enum.split_while(list, fn item ->
      item.priority >= new_item.priority
    end)
    before ++ [new_item] ++ after_items
  end
  
  defp execute_hooks_internal(hooks, event, context, state) do
    {final_event, final_context, new_stats} = Enum.reduce(hooks, {event, context, state.plugin_stats}, fn hook, {acc_event, acc_context, acc_stats} ->
      try do
        start_time = System.monotonic_time(:microsecond)
        
        # Execute hook
        result = apply(hook.module, :handle_hook, [hook_type_to_atom(hook), acc_event, acc_context])
        
        execution_time = System.monotonic_time(:microsecond) - start_time
        
        # Update stats
        plugin_stats = Map.get(acc_stats, hook.plugin_id, %{})
        updated_stats = %{plugin_stats |
          executions: Map.get(plugin_stats, :executions, 0) + 1,
          last_execution_time: execution_time
        }
        new_acc_stats = Map.put(acc_stats, hook.plugin_id, updated_stats)
        
        case result do
          {:ok, new_event} ->
            {new_event, acc_context, new_acc_stats}
          {:ok, new_event, new_context} ->
            {new_event, new_context, new_acc_stats}
          :ok ->
            {acc_event, acc_context, new_acc_stats}
          {:error, reason} ->
            Logger.warning("Hook failed for plugin #{hook.plugin_id}: #{inspect(reason)}")
            error_stats = %{updated_stats | errors: Map.get(updated_stats, :errors, 0) + 1}
            error_acc_stats = Map.put(new_acc_stats, hook.plugin_id, error_stats)
            {acc_event, acc_context, error_acc_stats}
        end
      rescue
        error ->
          Logger.error("Hook execution failed for plugin #{hook.plugin_id}: #{inspect(error)}")
          plugin_stats = Map.get(acc_stats, hook.plugin_id, %{})
          error_stats = %{plugin_stats | errors: Map.get(plugin_stats, :errors, 0) + 1}
          error_acc_stats = Map.put(acc_stats, hook.plugin_id, error_stats)
          {acc_event, acc_context, error_acc_stats}
      end
    end)
    
    new_state = %{state | plugin_stats: new_stats}
    {{:ok, final_event, final_context}, new_state}
  end
  
  defp apply_transformers(transformers, event, state) do
    {final_event, new_stats} = Enum.reduce(transformers, {event, state.plugin_stats}, fn transformer, {acc_event, acc_stats} ->
      try do
        result = apply(transformer.module, :transform_metrics, [acc_event])
        
        plugin_stats = Map.get(acc_stats, transformer.plugin_id, %{})
        updated_stats = %{plugin_stats | executions: Map.get(plugin_stats, :executions, 0) + 1}
        new_acc_stats = Map.put(acc_stats, transformer.plugin_id, updated_stats)
        
        {result, new_acc_stats}
      rescue
        error ->
          Logger.error("Transformer failed for plugin #{transformer.plugin_id}: #{inspect(error)}")
          {acc_event, acc_stats}
      end
    end)
    
    new_state = %{state | plugin_stats: new_stats}
    {final_event, new_state}
  end
  
  defp apply_evaluators(evaluators, event, context, state) do
    {final_context, new_stats} = Enum.reduce(evaluators, {context, state.plugin_stats}, fn evaluator, {acc_context, acc_stats} ->
      try do
        result = apply(evaluator.module, :evaluate_context, [event, acc_context])
        
        plugin_stats = Map.get(acc_stats, evaluator.plugin_id, %{})
        updated_stats = %{plugin_stats | executions: Map.get(plugin_stats, :executions, 0) + 1}
        new_acc_stats = Map.put(acc_stats, evaluator.plugin_id, updated_stats)
        
        {Map.merge(acc_context, result), new_acc_stats}
      rescue
        error ->
          Logger.error("Evaluator failed for plugin #{evaluator.plugin_id}: #{inspect(error)}")
          {acc_context, acc_stats}
      end
    end)
    
    new_state = %{state | plugin_stats: new_stats}
    {final_context, new_state}
  end
  
  defp hook_type_to_atom(:pre_process), do: :pre_process
  defp hook_type_to_atom(:post_process), do: :post_process
  defp hook_type_to_atom(:on_error), do: :on_error
  defp hook_type_to_atom(:on_match), do: :on_match
  
  defp load_builtin_plugins(state) do
    # Load VSM integration plugin
    vsm_plugin = %{
      id: :vsm_integration,
      module: AutonomousOpponentV2Core.AMCP.Plugins.VSMIntegration,
      hooks: [
        {:pre_process, %{}},
        {:on_match, %{}}
      ],
      priority: 100
    }
    
    # Load metrics enrichment plugin
    metrics_plugin = %{
      id: :metrics_enrichment,
      module: AutonomousOpponentV2Core.AMCP.Plugins.MetricsEnrichment,
      hooks: [{:pre_process, %{}}],
      priority: 80
    }
    
    # Register builtin plugins
    {:ok, state} = register_plugin_internal(vsm_plugin, state)
    {:ok, state} = register_plugin_internal(metrics_plugin, state)
    
    state
  end
end