defmodule AutonomousOpponent.VSM.S2.DampingController do
  @moduledoc """
  Damping controller for S2 anti-oscillation.
  
  Implements Beer's damping algorithms to reduce oscillatory behavior
  in the VSM system. Provides adaptive damping based on oscillation
  characteristics.
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponent.EventBus
  
  defstruct [
    :active_dampings,
    :damping_history,
    :effectiveness_metrics
  ]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  def apply_damping(server \\ __MODULE__, units, params) do
    GenServer.call(server, {:apply_damping, units, params})
  end
  
  def is_active?(server \\ __MODULE__) do
    GenServer.call(server, :is_active?)
  end
  
  def get_effectiveness(server \\ __MODULE__) do
    GenServer.call(server, :get_effectiveness)
  end
  
  @impl true
  def init(_opts) do
    state = %__MODULE__{
      active_dampings: %{},
      damping_history: [],
      effectiveness_metrics: %{
        total_applications: 0,
        successful_dampings: 0,
        average_reduction: 0.0
      }
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:apply_damping, units, params}, _from, state) do
    damping_id = generate_damping_id()
    
    # Create damping configuration
    damping = %{
      id: damping_id,
      units: units,
      params: params,
      started_at: System.monotonic_time(:millisecond),
      expires_at: System.monotonic_time(:millisecond) + (params[:duration] || 10_000)
    }
    
    # Apply damping to units
    Enum.each(units, fn unit_id ->
      apply_damping_to_unit(unit_id, params)
    end)
    
    # Schedule expiration
    Process.send_after(self(), {:expire_damping, damping_id}, params[:duration] || 10_000)
    
    # Update state
    new_dampings = Map.put(state.active_dampings, damping_id, damping)
    new_state = %{state | 
      active_dampings: new_dampings,
      damping_history: [damping | state.damping_history] |> Enum.take(100)
    }
    |> update_effectiveness_metrics()
    
    Logger.info("S2 DampingController: Applied damping #{damping_id} to #{length(units)} units")
    
    {:reply, {:ok, damping_id}, new_state}
  end
  
  @impl true
  def handle_call(:is_active?, _from, state) do
    is_active = map_size(state.active_dampings) > 0
    {:reply, is_active, state}
  end
  
  @impl true
  def handle_call(:get_effectiveness, _from, state) do
    {:reply, state.effectiveness_metrics, state}
  end
  
  @impl true
  def handle_info({:expire_damping, damping_id}, state) do
    case Map.get(state.active_dampings, damping_id) do
      nil ->
        {:noreply, state}
      
      damping ->
        # Remove damping from active
        new_dampings = Map.delete(state.active_dampings, damping_id)
        
        # Notify units that damping has expired
        Enum.each(damping.units, fn unit_id ->
          EventBus.publish(:damping_expired, %{
            unit_id: unit_id,
            damping_id: damping_id
          })
        end)
        
        {:noreply, %{state | active_dampings: new_dampings}}
    end
  end
  
  defp apply_damping_to_unit(unit_id, params) do
    # Publish damping command to unit
    EventBus.publish(:apply_damping, %{
      unit_id: unit_id,
      damping_factor: params[:damping_factor] || 0.7,
      frequency_filter: params[:frequency] || :all,
      phase_adjustment: params[:phase_shift] || 0,
      timestamp: System.monotonic_time(:millisecond)
    })
  end
  
  defp update_effectiveness_metrics(state) do
    # Update metrics based on damping application
    update_in(state.effectiveness_metrics.total_applications, &(&1 + 1))
  end
  
  defp generate_damping_id do
    "damping_#{:erlang.unique_integer([:positive])}"
  end
end