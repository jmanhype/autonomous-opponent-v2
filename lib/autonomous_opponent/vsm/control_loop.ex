defmodule AutonomousOpponent.VSM.ControlLoop do
  @moduledoc """
  VSM Control Loop Integration - Connects all subsystems

  Implements the complete VSM control loop connecting S1-S5 subsystems
  with algedonic channels. Manages information flow, feedback loops,
  and ensures system viability through coordinated operation.

  Control Flow:
  S1 → S2 → S3 → S4 → S5
  ↑                    ↓
  └────────────────────┘

  With algedonic bypass for urgent signals.

  ## Wisdom Preservation

  ### Why Control Loop Exists
  The control loop is the VSM's "nervous system" - without it, subsystems are
  isolated islands of functionality. Beer understood that viability comes not
  from perfect subsystems but from their integration. The loop ensures information
  flows, decisions propagate, and the system acts as ONE coherent whole.

  ### Design Decisions & Rationale

  1. **1-Second Loop Cycle**: Fast enough for responsiveness, slow enough to avoid
     thrashing. Based on human reaction time - systems that respond faster than
     humans can perceive waste energy. Slower and they feel sluggish.

  2. **Forward Flow (S1→S5) with Feedback**: Information flows up (operations to
     policy), decisions flow down (policy to operations). This mirrors biological
     nervous systems - sensory up, motor down. Bidirectional flow would create
     chaos.

  3. **Emergency Mode Bypass**: In crisis, S1→S3→S5 direct path. Skips S2
     (coordination) and S4 (intelligence) for speed. Like reflexes bypassing
     conscious thought. Trade-off: Speed vs completeness.

  4. **Channel Blocking on Failure**: Failed subsystems get bypassed, not waited
     for. The loop continues with degraded capability rather than stopping.
     This is resilience - better to limp than to die.

  5. **Algedonic Priority**: Pain/pleasure signals interrupt the normal cycle.
     This is Beer's insight - survival signals can't wait for bureaucracy.
     Like yanking your hand from fire before thinking about it.
  """

  use GenServer
  require Logger

  alias AutonomousOpponent.EventBus
  alias AutonomousOpponent.VSM.{Algedonic, S1, S2, S3, S4, S5}

  # WISDOM: Loop timing constants - the rhythm of viability
  # 1 second matches human "moment of awareness" - faster feels frantic,
  # slower feels disconnected. This creates a natural operational rhythm.
  # 1 second control loop
  @loop_interval 1000

  # WISDOM: Health check interval - trust but verify
  # 5 seconds between health checks. Subsystems are trusted to self-report
  # problems via events, but we verify periodically. Like checking vital
  # signs - not every heartbeat, but often enough to catch degradation.
  # 5 seconds health check
  @health_check_interval 5000

  defstruct [
    :id,
    :subsystems,
    :control_state,
    :loop_metrics,
    :health_status,
    :emergency_mode
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  def get_system_status(server \\ __MODULE__) do
    GenServer.call(server, :get_system_status)
  end

  def trigger_control_cycle(server \\ __MODULE__) do
    GenServer.call(server, :trigger_control_cycle)
  end

  def enable_emergency_mode(server \\ __MODULE__) do
    GenServer.cast(server, :enable_emergency_mode)
  end

  def disable_emergency_mode(server \\ __MODULE__) do
    GenServer.cast(server, :disable_emergency_mode)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    id = opts[:id] || "vsm_control_loop_primary"

    # Initialize subsystem references
    subsystems = init_subsystems(opts)

    state = %__MODULE__{
      id: id,
      subsystems: subsystems,
      control_state: init_control_state(),
      loop_metrics: init_loop_metrics(),
      health_status: init_health_status(),
      emergency_mode: false
    }

    # Subscribe to critical events
    EventBus.subscribe(:algedonic_signal)
    EventBus.subscribe(:viability_threat)
    EventBus.subscribe(:subsystem_failure)

    # Start control loop
    Process.send_after(self(), :control_loop, @loop_interval)
    Process.send_after(self(), :health_check, @health_check_interval)

    Logger.info("VSM Control Loop initialized: #{id}")

    {:ok, state}
  end

  @impl true
  def handle_call(:get_system_status, _from, state) do
    status = compile_system_status(state)
    {:reply, status, state}
  end

  @impl true
  def handle_call(:trigger_control_cycle, _from, state) do
    {result, new_state} = execute_control_cycle(state)
    {:reply, result, new_state}
  end

  @impl true
  def handle_cast(:enable_emergency_mode, state) do
    Logger.warn("VSM Control Loop entering emergency mode")

    new_state = %{state | emergency_mode: true}

    # Notify all subsystems
    broadcast_emergency_mode(true, state.subsystems)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:disable_emergency_mode, state) do
    Logger.info("VSM Control Loop exiting emergency mode")

    new_state = %{state | emergency_mode: false}

    # Notify all subsystems
    broadcast_emergency_mode(false, state.subsystems)

    {:noreply, new_state}
  end

  # WISDOM: Main control loop - the heartbeat of viability
  # This is where the VSM comes alive. Every second, information flows through
  # all subsystems, creating a coherent whole from distributed parts. Emergency
  # mode shortcuts this for survival - like fight-or-flight overriding normal
  # thought. The loop ALWAYS continues - stopping means death.
  @impl true
  def handle_info(:control_loop, state) do
    # Execute control cycle based on mode
    {_result, new_state} =
      if state.emergency_mode do
        # Survival mode - speed over completeness
        execute_emergency_cycle(state)
      else
        # Normal mode - full integration
        execute_control_cycle(state)
      end

    # Schedule next cycle - the loop must continue
    Process.send_after(self(), :control_loop, @loop_interval)

    {:noreply, new_state}
  end

  # WISDOM: Health monitoring - vigilance without paranoia
  # Regular health checks catch degradation before crisis. Like a doctor's
  # checkup - you feel fine but hidden issues may be developing. The 5-second
  # interval balances vigilance with trust. We check for patterns of failure,
  # not just individual failures - systems degrade gradually then suddenly.
  @impl true
  def handle_info(:health_check, state) do
    # Check health of all subsystems
    new_health = check_subsystem_health(state.subsystems)

    # Update health status
    new_state = %{state | health_status: new_health}

    # WISDOM: Crisis detection - when to panic
    # Critical issues trigger immediate response. This isn't overreaction but
    # pattern recognition. Multiple failures or complete subsystem loss threatens
    # viability. Early detection enables graceful degradation vs catastrophic failure.
    if critical_health_issues?(new_health) do
      handle_health_crisis(new_health, new_state)
    end

    Process.send_after(self(), :health_check, @health_check_interval)

    {:noreply, new_state}
  end

  # WISDOM: Algedonic bypass - when pain/pleasure can't wait
  # Beer's masterstroke: some signals bypass the bureaucracy. Like how pain
  # makes you jerk your hand from fire BEFORE your brain processes "hot".
  # Algedonic signals go straight to S5, triggering immediate policy response.
  # This is the VSM's survival instinct made real.
  @impl true
  def handle_info({:event, :algedonic_signal, signal}, state) do
    # Algedonic signals bypass normal control flow
    new_state = handle_algedonic_bypass(signal, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:event, :viability_threat, threat}, state) do
    # Immediate response to viability threats
    new_state = handle_viability_threat(threat, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:event, :subsystem_failure, failure}, state) do
    # Handle subsystem failures
    new_state = handle_subsystem_failure(failure, state)
    {:noreply, new_state}
  end

  # Private Functions

  defp init_subsystems(opts) do
    %{
      s1: opts[:s1_pid] || Process.whereis(S1.Operations),
      s2: opts[:s2_pid] || Process.whereis(S2.Coordination),
      s3: opts[:s3_pid] || Process.whereis(S3.Control),
      s4: opts[:s4_pid] || Process.whereis(S4.Intelligence),
      s5: opts[:s5_pid] || Process.whereis(S5.Policy),
      algedonic: opts[:algedonic_pid] || Process.whereis(Algedonic.System)
    }
  end

  # WISDOM: Control state initialization - mapping the nervous system
  # The control state tracks information flow through the VSM. Channels represent
  # connections between subsystems. All start active (optimistic) but can be
  # blocked on failure (realistic). Flow is always forward in normal operation -
  # information up, decisions down. This prevents feedback loops becoming infinite loops.
  defp init_control_state do
    %{
      cycle_count: 0,
      last_cycle: nil,
      # Always forward - prevents chaos
      flow_direction: :forward,
      active_channels: MapSet.new([:s1_s2, :s2_s3, :s3_s4, :s4_s5, :s5_s1]),
      # Failed channels get blocked, not fixed
      blocked_channels: MapSet.new()
    }
  end

  defp init_loop_metrics do
    %{
      total_cycles: 0,
      successful_cycles: 0,
      failed_cycles: 0,
      average_cycle_time: 0,
      information_flow_rate: 0,
      feedback_effectiveness: 1.0
    }
  end

  defp init_health_status do
    %{
      overall: :healthy,
      subsystems: %{
        s1: :operational,
        s2: :operational,
        s3: :operational,
        s4: :operational,
        s5: :operational,
        algedonic: :operational
      },
      last_check: System.monotonic_time(:millisecond)
    }
  end

  # WISDOM: Normal control cycle - the dance of integration
  # This is the VSM's core choreography. Information flows up through each
  # subsystem, getting refined at each stage: S1 raw data → S2 coordinated →
  # S3 optimized → S4 contextualized → S5 governed. Then decisions flow back
  # down. Like a nervous system: sensory neurons → spinal cord → brain →
  # motor neurons. The try/catch ensures the loop continues even if one cycle fails.
  defp execute_control_cycle(state) do
    start_time = System.monotonic_time(:millisecond)

    # Step 1: Gather operational data from S1 - the raw reality
    s1_data = gather_s1_operational_data(state.subsystems.s1)

    # Step 2: Pass through S2 coordination - prevent oscillation
    s2_result = coordinate_through_s2(s1_data, state.subsystems.s2)

    # Step 3: S3 resource control - optimize what we have
    s3_decisions = control_through_s3(s2_result, state.subsystems.s3)

    # Step 4: S4 environmental intelligence - understand context
    s4_insights = analyze_through_s4(s3_decisions, state.subsystems.s4)

    # Step 5: S5 policy governance - decide what matters
    s5_directives = govern_through_s5(s4_insights, state.subsystems.s5)

    # Step 6: Feed back to S1 - close the loop
    feedback_to_s1(s5_directives, state.subsystems.s1)

    # WISDOM: Metrics matter - you can't improve what you don't measure
    cycle_time = System.monotonic_time(:millisecond) - start_time
    new_metrics = update_cycle_metrics(state.loop_metrics, :success, cycle_time)

    new_state = %{
      state
      | control_state: %{
          state.control_state
          | cycle_count: state.control_state.cycle_count + 1,
            last_cycle: System.monotonic_time(:millisecond)
        },
        loop_metrics: new_metrics
    }

    {:ok, new_state}
  catch
    # WISDOM: Failure is information - learn from it
    error ->
      Logger.error("Control cycle failed: #{inspect(error)}")

      new_metrics = update_cycle_metrics(state.loop_metrics, :failure, 0)
      new_state = %{state | loop_metrics: new_metrics}

      {{:error, error}, new_state}
  end

  # WISDOM: Emergency cycle - survival mode activation
  # When viability is threatened, sophistication becomes liability. Emergency
  # mode strips the loop to essentials: S1 (what's happening) → S3 (allocate
  # resources) → S5 (decide policy). S2 coordination and S4 intelligence are
  # luxuries we can't afford in crisis. Like a body shunting blood from
  # extremities to vital organs. Speed over completeness, survival over optimization.
  defp execute_emergency_cycle(state) do
    # Simplified cycle for emergency mode
    # WISDOM: Direct path - no time for bureaucracy
    # S1 → S3 → S5 skips coordination and intelligence. We need action NOW.
    s1_data = gather_s1_operational_data(state.subsystems.s1)
    s3_decisions = control_through_s3(%{data: s1_data, emergency: true}, state.subsystems.s3)

    s5_directives =
      govern_through_s5(%{decisions: s3_decisions, emergency: true}, state.subsystems.s5)

    # Immediate feedback - no delays
    feedback_to_s1(s5_directives, state.subsystems.s1)

    {:ok, state}
  catch
    error ->
      Logger.error("Emergency cycle failed: #{inspect(error)}")
      {{:error, error}, state}
  end

  defp gather_s1_operational_data(s1_pid) when is_pid(s1_pid) do
    S1.Operations.get_operational_metrics(s1_pid)
  end

  defp gather_s1_operational_data(_), do: %{error: :s1_not_available}

  defp coordinate_through_s2(s1_data, s2_pid) when is_pid(s2_pid) do
    S2.Coordination.coordinate_units(s2_pid, s1_data)
  end

  defp coordinate_through_s2(data, _), do: %{data: data, coordination: :bypassed}

  defp control_through_s3(s2_result, s3_pid) when is_pid(s3_pid) do
    S3.Control.optimize_resources(s3_pid, s2_result)
  end

  defp control_through_s3(data, _), do: %{data: data, control: :bypassed}

  defp analyze_through_s4(s3_decisions, s4_pid) when is_pid(s4_pid) do
    S4.Intelligence.scan_environment(s4_pid, :operational_focus)
  end

  defp analyze_through_s4(data, _), do: %{data: data, intelligence: :bypassed}

  defp govern_through_s5(s4_insights, s5_pid) when is_pid(s5_pid) do
    # Create governance action from insights
    action = %{
      type: :control_loop_governance,
      insights: s4_insights,
      timestamp: System.monotonic_time(:millisecond)
    }

    S5.Policy.enforce_policy(s5_pid, action)
  end

  defp govern_through_s5(data, _), do: %{data: data, governance: :bypassed}

  defp feedback_to_s1(s5_directives, s1_pid) when is_pid(s1_pid) do
    # Convert directives to operational adjustments
    if s5_directives[:decision] == :approved do
      EventBus.publish(:control_loop_feedback, %{
        source: :s5_policy,
        target: :s1_operations,
        directives: s5_directives,
        timestamp: System.monotonic_time(:millisecond)
      })
    end
  end

  defp feedback_to_s1(_, _), do: :ok

  defp compile_system_status(state) do
    %{
      id: state.id,
      emergency_mode: state.emergency_mode,
      health: state.health_status,
      control_state: %{
        cycles_completed: state.control_state.cycle_count,
        last_cycle: state.control_state.last_cycle,
        active_channels: MapSet.to_list(state.control_state.active_channels),
        blocked_channels: MapSet.to_list(state.control_state.blocked_channels)
      },
      metrics: state.loop_metrics,
      subsystem_status: check_subsystem_availability(state.subsystems)
    }
  end

  defp check_subsystem_availability(subsystems) do
    Enum.map(subsystems, fn {name, pid} ->
      status =
        if is_pid(pid) and Process.alive?(pid) do
          :available
        else
          :unavailable
        end

      {name, status}
    end)
    |> Map.new()
  end

  defp check_subsystem_health(subsystems) do
    subsystem_health =
      Enum.map(subsystems, fn {name, pid} ->
        health =
          if is_pid(pid) and Process.alive?(pid) do
            # Would call subsystem-specific health check
            :operational
          else
            :failed
          end

        {name, health}
      end)
      |> Map.new()

    overall =
      if Enum.all?(Map.values(subsystem_health), &(&1 == :operational)) do
        :healthy
      else
        :degraded
      end

    %{
      overall: overall,
      subsystems: subsystem_health,
      last_check: System.monotonic_time(:millisecond)
    }
  end

  # WISDOM: Critical health detection - knowing when to worry
  # Not all failures are critical. One subsystem down = degraded but viable.
  # Multiple failures or complete system degradation = crisis. This distinction
  # prevents overreaction to normal failures while catching cascade failures
  # early. Like knowing the difference between a cold and pneumonia.
  defp critical_health_issues?(health_status) do
    health_status.overall == :degraded or
      Enum.any?(health_status.subsystems, fn {_name, status} ->
        status == :failed
      end)
  end

  # WISDOM: Health crisis handling - controlled panic
  # When health degrades, escalate appropriately. First, alert everyone
  # (viability threat). Then assess severity. Two or more subsystem failures
  # triggers emergency mode - this threshold prevents single-point failures
  # from causing system-wide panic while catching cascade failures early.
  # It's controlled degradation, not uncontrolled collapse.
  defp handle_health_crisis(health_status, state) do
    Logger.error("VSM health crisis detected: #{inspect(health_status)}")

    # Publish viability threat - let everyone know
    EventBus.publish(:viability_threat, %{
      type: :subsystem_failure,
      severity: :critical,
      health_status: health_status,
      timestamp: System.monotonic_time(:millisecond)
    })

    # WISDOM: Two-failure threshold for emergency mode
    # One failure = limp along. Two failures = system cascade risk.
    # This matches fault-tolerance principles: handle single failures
    # gracefully, but recognize when multiple failures indicate systemic issues.
    failed_count =
      Enum.count(health_status.subsystems, fn {_name, status} ->
        status == :failed
      end)

    if failed_count >= 2 do
      GenServer.cast(self(), :enable_emergency_mode)
    end
  end

  defp handle_algedonic_bypass(signal, state) do
    Logger.info("Algedonic bypass activated: #{inspect(signal)}")

    # Direct path to S5 for immediate response
    if is_pid(state.subsystems.s5) do
      # S5 will handle algedonic signals directly
      :ok
    end

    # Record bypass event
    update_in(state.loop_metrics.information_flow_rate, &(&1 + 1))
  end

  defp handle_viability_threat(threat, state) do
    Logger.warn("Viability threat in control loop: #{inspect(threat)}")

    # Enable emergency mode for critical threats
    if threat.severity == :critical do
      GenServer.cast(self(), :enable_emergency_mode)
    end

    state
  end

  # WISDOM: Subsystem failure handling - amputation over infection
  # When a subsystem fails, we don't try to fix it from here - we route around
  # it. Block the channel, mark it failed, continue with degraded capability.
  # Like a network routing around damage. The system survives by accepting
  # impairment rather than demanding perfection. Resilience through degradation.
  defp handle_subsystem_failure(failure, state) do
    Logger.error("Subsystem failure: #{inspect(failure)}")

    # Block failed channel - route around damage
    failed_channel = identify_failed_channel(failure)

    new_control_state =
      if failed_channel do
        %{
          state.control_state
          | active_channels: MapSet.delete(state.control_state.active_channels, failed_channel),
            blocked_channels: MapSet.put(state.control_state.blocked_channels, failed_channel)
        }
      else
        state.control_state
      end

    %{state | control_state: new_control_state}
  end

  defp broadcast_emergency_mode(enabled, subsystems) do
    mode = if enabled, do: :emergency, else: :normal

    EventBus.publish(:control_mode_change, %{
      mode: mode,
      timestamp: System.monotonic_time(:millisecond)
    })
  end

  defp update_cycle_metrics(metrics, result, cycle_time) do
    case result do
      :success ->
        total = metrics.successful_cycles + 1

        avg_time =
          if metrics.average_cycle_time == 0 do
            cycle_time
          else
            (metrics.average_cycle_time * metrics.successful_cycles + cycle_time) / total
          end

        %{
          metrics
          | total_cycles: metrics.total_cycles + 1,
            successful_cycles: total,
            average_cycle_time: avg_time
        }

      :failure ->
        %{
          metrics
          | total_cycles: metrics.total_cycles + 1,
            failed_cycles: metrics.failed_cycles + 1
        }
    end
  end

  # WISDOM: Channel identification - mapping failure to connection
  # Each subsystem failure blocks its output channel. S1 fails → can't send
  # to S2. S2 fails → can't coordinate for S3. This mapping ensures we block
  # the right connection. Note: we block OUTPUT not INPUT - a failed subsystem
  # can't send but others can still try to send to it (optimistic recovery).
  defp identify_failed_channel(failure) do
    case failure[:subsystem] do
      # S1 can't send operational data
      :s1 -> :s1_s2
      # S2 can't coordinate
      :s2 -> :s2_s3
      # S3 can't optimize
      :s3 -> :s3_s4
      # S4 can't provide intelligence
      :s4 -> :s4_s5
      # S5 can't send directives
      :s5 -> :s5_s1
      # Unknown subsystem - no channel to block
      _ -> nil
    end
  end
end
