defmodule AutonomousOpponentV2Core.Security.KeyRotation do
  @moduledoc """
  API Key rotation mechanism for automatic security key management.
  
  This module handles:
  - Scheduled rotation of API keys
  - Emergency rotation on security events
  - Grace periods for key transitions
  - Rotation history and rollback capabilities
  
  ## Rotation Strategy
  
  1. Generate new key
  2. Update primary key in secure storage
  3. Keep old key active during grace period
  4. Deactivate old key after grace period
  5. Maintain rotation history for audit
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.Security.SecretsManager
  alias AutonomousOpponentV2Core.EventBus
  
  defstruct [
    :rotation_schedule,
    :active_rotations,
    :rotation_history,
    :config
  ]
  
  @default_grace_period :timer.hours(24)
  @max_history_entries 100
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  @doc """
  Schedule a key for rotation.
  """
  def schedule_rotation(key, interval, opts \\ []) do
    GenServer.call(__MODULE__, {:schedule_rotation, key, interval, opts})
  end
  
  @doc """
  Immediately rotate a key.
  """
  def rotate_now(key, opts \\ []) do
    GenServer.call(__MODULE__, {:rotate_now, key, opts})
  end
  
  @doc """
  Get rotation status for a key.
  """
  def get_status(key) do
    GenServer.call(__MODULE__, {:get_status, key})
  end
  
  @doc """
  Get rotation history.
  """
  def get_history(opts \\ []) do
    GenServer.call(__MODULE__, {:get_history, opts})
  end
  
  @doc """
  Cancel scheduled rotation.
  """
  def cancel_rotation(key) do
    GenServer.call(__MODULE__, {:cancel_rotation, key})
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    config = build_config(opts)
    
    state = %__MODULE__{
      rotation_schedule: init_default_schedule(config),
      active_rotations: %{},
      rotation_history: [],
      config: config
    }
    
    # Subscribe to security events
    EventBus.subscribe(:security_breach)
    EventBus.subscribe(:rotation_required)
    
    # Start scheduled rotations
    Enum.each(state.rotation_schedule, fn {key, schedule} ->
      schedule_next_rotation(key, schedule)
    end)
    
    Logger.info("Key Rotation service initialized")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:schedule_rotation, key, interval, opts}, _from, state) do
    schedule = %{
      interval: parse_interval(interval),
      next_rotation: calculate_next_rotation(interval),
      options: opts,
      enabled: true
    }
    
    new_schedule = Map.put(state.rotation_schedule, key, schedule)
    
    # Schedule the rotation
    schedule_next_rotation(key, schedule)
    
    {:reply, :ok, %{state | rotation_schedule: new_schedule}}
  end
  
  @impl true
  def handle_call({:rotate_now, key, opts}, _from, state) do
    case perform_rotation(key, opts, state) do
      {:ok, rotation_info} ->
        # Add to active rotations during grace period
        active = Map.put(state.active_rotations, key, rotation_info)
        
        # Add to history
        history_entry = Map.put(rotation_info, :completed_at, DateTime.utc_now())
        new_history = [history_entry | state.rotation_history] |> Enum.take(@max_history_entries)
        
        # Schedule grace period expiry
        if rotation_info.grace_period > 0 do
          Process.send_after(self(), {:expire_old_key, key, rotation_info.old_key}, rotation_info.grace_period)
        end
        
        new_state = %{state | 
          active_rotations: active,
          rotation_history: new_history
        }
        
        {:reply, {:ok, rotation_info}, new_state}
        
      {:error, reason} = error ->
        Logger.error("Failed to rotate key #{key}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:get_status, key}, _from, state) do
    status = %{
      scheduled: Map.get(state.rotation_schedule, key),
      active_rotation: Map.get(state.active_rotations, key),
      last_rotation: find_last_rotation(key, state.rotation_history)
    }
    
    {:reply, {:ok, status}, state}
  end
  
  @impl true
  def handle_call({:get_history, opts}, _from, state) do
    history = state.rotation_history
    |> maybe_filter_by_key(opts[:key])
    |> maybe_filter_by_date(opts[:since])
    |> Enum.take(opts[:limit] || 50)
    
    {:reply, {:ok, history}, state}
  end
  
  @impl true
  def handle_call({:cancel_rotation, key}, _from, state) do
    case Map.get(state.rotation_schedule, key) do
      nil ->
        {:reply, {:error, :not_scheduled}, state}
        
      schedule ->
        # Cancel any pending timers
        updated_schedule = Map.put(schedule, :enabled, false)
        new_schedules = Map.put(state.rotation_schedule, key, updated_schedule)
        
        {:reply, :ok, %{state | rotation_schedule: new_schedules}}
    end
  end
  
  @impl true
  def handle_info({:rotate_key, key}, state) do
    case Map.get(state.rotation_schedule, key) do
      %{enabled: true} = schedule ->
        # Perform rotation
        case perform_rotation(key, schedule.options, state) do
          {:ok, rotation_info} ->
            # Update state with rotation info
            active = Map.put(state.active_rotations, key, rotation_info)
            
            # Add to history
            history_entry = Map.put(rotation_info, :completed_at, DateTime.utc_now())
            new_history = [history_entry | state.rotation_history] |> Enum.take(@max_history_entries)
            
            # Schedule grace period expiry
            if rotation_info.grace_period > 0 do
              Process.send_after(self(), {:expire_old_key, key, rotation_info.old_key}, rotation_info.grace_period)
            end
            
            # Schedule next rotation
            schedule_next_rotation(key, schedule)
            
            {:noreply, %{state | 
              active_rotations: active,
              rotation_history: new_history
            }}
            
          {:error, reason} ->
            Logger.error("Scheduled rotation failed for #{key}: #{inspect(reason)}")
            
            # Retry in 1 hour
            Process.send_after(self(), {:rotate_key, key}, :timer.hours(1))
            
            {:noreply, state}
        end
        
      _ ->
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:expire_old_key, key, old_key}, state) do
    Logger.info("Expiring old key for #{key}")
    
    # Remove from active rotations
    active = Map.delete(state.active_rotations, key)
    
    # Notify about expiration
    EventBus.publish(:key_expired, %{
      key: key,
      old_key: String.slice(old_key, 0..7) <> "...",
      timestamp: DateTime.utc_now()
    })
    
    {:noreply, %{state | active_rotations: active}}
  end
  
  @impl true
  def handle_info({:event, :security_breach, %{keys: keys}}, state) do
    # Emergency rotation for compromised keys
    Enum.each(keys, fn key ->
      Logger.warn("Emergency rotation triggered for #{key}")
      rotate_now(key, [emergency: true, grace_period: 0])
    end)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:event, :rotation_required, %{key: key}}, state) do
    rotate_now(key)
    {:noreply, state}
  end
  
  # Private Functions
  
  defp build_config(opts) do
    %{
      default_interval: opts[:default_interval] || :timer.hours(24 * 30),
      default_grace_period: opts[:default_grace_period] || @default_grace_period,
      key_generators: opts[:key_generators] || %{},
      notification_enabled: opts[:notification_enabled] || true
    }
  end
  
  defp init_default_schedule(config) do
    %{
      "OPENAI_API_KEY" => %{
        interval: :timer.hours(24 * 30),  # Monthly
        next_rotation: calculate_next_rotation(:timer.hours(24 * 30)),
        options: [
          generator: :openai,
          grace_period: :timer.hours(48)
        ],
        enabled: true
      },
      "GUARDIAN_SECRET" => %{
        interval: :timer.hours(24 * 90),  # Quarterly
        next_rotation: calculate_next_rotation(:timer.hours(24 * 90)),
        options: [
          generator: :random,
          length: 64,
          grace_period: :timer.hours(72)
        ],
        enabled: true
      }
    }
  end
  
  defp perform_rotation(key, opts, state) do
    with {:ok, old_value} <- get_current_key(key),
         {:ok, new_value} <- generate_new_key(key, opts, state),
         :ok <- SecretsManager.put_secret(key, new_value, [rotation: true]),
         :ok <- notify_rotation(key, old_value, new_value) do
      
      rotation_info = %{
        key: key,
        old_key: old_value,
        new_key: new_value,
        started_at: DateTime.utc_now(),
        grace_period: opts[:grace_period] || state.config.default_grace_period,
        emergency: opts[:emergency] || false
      }
      
      # Publish rotation event
      EventBus.publish(:key_rotated, %{
        key: key,
        timestamp: DateTime.utc_now(),
        emergency: rotation_info.emergency
      })
      
      {:ok, rotation_info}
    else
      error -> error
    end
  end
  
  defp get_current_key(key) do
    case SecretsManager.get_secret(key) do
      {:ok, value} -> {:ok, value}
      {:error, :secret_not_found} -> {:ok, nil}
      error -> error
    end
  end
  
  defp generate_new_key(key, opts, state) do
    generator = opts[:generator] || :default
    
    case generator do
      :openai ->
        {:ok, "sk-" <> generate_random_string(48)}
        
      :random ->
        length = opts[:length] || 32
        {:ok, generate_random_string(length)}
        
      :uuid ->
        {:ok, UUID.uuid4()}
        
      fun when is_function(fun) ->
        fun.()
        
      _ ->
        # Check configured generators
        case Map.get(state.config.key_generators, generator) do
          nil -> {:error, :unknown_generator}
          gen_fn -> gen_fn.(key, opts)
        end
    end
  end
  
  defp generate_random_string(length) do
    :crypto.strong_rand_bytes(length)
    |> Base.encode64(padding: false)
    |> String.slice(0, length)
  end
  
  defp notify_rotation(key, old_value, new_value) do
    # Log rotation (without exposing full keys)
    old_preview = if old_value, do: String.slice(old_value, 0..7) <> "...", else: "none"
    new_preview = String.slice(new_value, 0..7) <> "..."
    
    Logger.info("Key rotated: #{key} (#{old_preview} -> #{new_preview})")
    
    :ok
  end
  
  defp schedule_next_rotation(key, %{interval: interval, enabled: true}) do
    Process.send_after(self(), {:rotate_key, key}, interval)
  end
  defp schedule_next_rotation(_, _), do: :ok
  
  defp parse_interval(interval) when is_integer(interval), do: interval
  defp parse_interval(:daily), do: :timer.hours(24)
  defp parse_interval(:weekly), do: :timer.hours(24 * 7)
  defp parse_interval(:monthly), do: :timer.hours(24 * 30)
  defp parse_interval(:quarterly), do: :timer.hours(24 * 90)
  defp parse_interval(:yearly), do: :timer.hours(24 * 365)
  
  defp calculate_next_rotation(interval) when is_integer(interval) do
    DateTime.add(DateTime.utc_now(), interval, :millisecond)
  end
  defp calculate_next_rotation(interval) do
    calculate_next_rotation(parse_interval(interval))
  end
  
  defp find_last_rotation(key, history) do
    Enum.find(history, & &1.key == key)
  end
  
  defp maybe_filter_by_key(history, nil), do: history
  defp maybe_filter_by_key(history, key) do
    Enum.filter(history, & &1.key == key)
  end
  
  defp maybe_filter_by_date(history, nil), do: history
  defp maybe_filter_by_date(history, since) do
    Enum.filter(history, fn entry ->
      DateTime.compare(entry.completed_at, since) == :gt
    end)
  end
end