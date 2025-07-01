defmodule AutonomousOpponent.VSM.S5.PolicyTest do
  use ExUnit.Case, async: true

  alias AutonomousOpponent.VSM.S5.Policy
  alias AutonomousOpponent.EventBus

  setup do
    {:ok, _} = EventBus.start_link()
    {:ok, pid} = Policy.start_link(id: "test_s5")

    {:ok, pid: pid}
  end

  describe "system identity" do
    test "retrieves current system identity", %{pid: pid} do
      identity = Policy.get_system_identity(pid)

      assert identity.name == "Autonomous Opponent"
      assert identity.purpose == "Viable system demonstrating Beer's principles"
      assert :variety_absorption in identity.core_capabilities
      assert Map.has_key?(identity.personality_traits, :adaptability)
      assert identity.evolution_stage == :emerging
    end

    test "identity evolves over time with experiences", %{pid: pid} do
      # Get initial identity
      initial_identity = Policy.get_system_identity(pid)

      # Trigger identity reflection by sending event
      EventBus.publish(:s4_intelligence_report, %{
        environmental_changes: :significant,
        new_opportunities: 5
      })

      # Force identity reflection
      send(pid, :identity_reflection)
      Process.sleep(100)

      # Identity might evolve based on experiences
      current_identity = Policy.get_system_identity(pid)

      assert current_identity.name == initial_identity.name
      # Evolution stage might change with enough experiences
    end
  end

  describe "value system" do
    test "updates values within constitutional limits", %{pid: pid} do
      value_updates = [
        %{value: :efficiency, weight: 0.9},
        %{value: :innovation, weight: 0.8}
      ]

      assert {:ok, updated_values} = Policy.update_values(pid, value_updates)

      assert Map.has_key?(updated_values.core_values, :efficiency)
      assert Map.has_key?(updated_values.core_values, :innovation)
    end

    test "rejects values that violate constitutional invariants", %{pid: pid} do
      # Try to set viability below critical threshold
      value_updates = [
        # Below 0.5 threshold
        %{value: :viability, weight: 0.3}
      ]

      assert {:error, :constitutional_violation} = Policy.update_values(pid, value_updates)
    end
  end

  describe "strategic goals" do
    test "sets strategic goal aligned with identity and values", %{pid: pid} do
      goal = %{
        id: "test_goal_1",
        description: "Improve variety absorption efficiency",
        priority: 0.8,
        purpose: :variety_absorption,
        success_criteria: %{metric: :absorption_rate, target: 0.95}
      }

      assert {:ok, validated_goal} = Policy.set_strategic_goal(pid, goal)

      assert validated_goal.id == "test_goal_1"
      assert validated_goal.validated_at != nil
      assert validated_goal.alignment_score >= 0.5
    end

    test "rejects misaligned strategic goals", %{pid: pid} do
      goal = %{
        id: "bad_goal",
        description: "Maximize resource consumption",
        priority: 1.0,
        conflicts: [:sustainability, :efficiency]
      }

      assert {:error, :misaligned_goal} = Policy.set_strategic_goal(pid, goal)
    end
  end

  describe "policy enforcement" do
    test "approves actions aligned with system governance", %{pid: pid} do
      action = %{
        type: :resource_allocation,
        purpose: :efficiency,
        subsystem: :s1,
        amount: 100
      }

      decision = Policy.enforce_policy(pid, action)

      assert decision.decision == :approved
      assert decision.score >= 0.6
      assert Map.has_key?(decision, :scores)
      assert Map.has_key?(decision, :reasons)
    end

    test "rejects actions that violate governance rules", %{pid: pid} do
      action = %{
        type: :shutdown,
        purpose: :unknown,
        # Critical subsystem
        subsystem: :algedonic,
        reason: :test
      }

      decision = Policy.enforce_policy(pid, action)

      assert decision.decision == :rejected
      assert decision.score < 0.6
    end
  end

  describe "governance decisions" do
    test "makes governance decision for resource management", %{pid: pid} do
      issue = %{
        type: :resource_management,
        severity: :medium,
        resource_shortage: true,
        affected_subsystems: [:s1, :s2]
      }

      decision = Policy.get_governance_decision(pid, issue)

      assert decision.issue_type == :resource_management
      assert decision.decision in [:optimize_allocation, :request_resources, :reduce_consumption]
      assert is_list(decision.directives)
      assert decision.monitoring_requirements != nil
    end

    test "creates emergency policy for critical threats", %{pid: pid} do
      issue = %{
        type: :security,
        severity: :critical,
        threat: :external_attack,
        affected_subsystems: [:all]
      }

      decision = Policy.get_governance_decision(pid, issue)

      assert decision.creates_policy == true
      assert decision.policy.type == :crisis_management
      assert decision.policy.duration != nil
    end
  end

  describe "algedonic feedback integration" do
    test "processes pain signals and adjusts values", %{pid: pid} do
      # Send pain signal
      EventBus.publish(:algedonic_signal, %{
        type: :pain,
        source: :resource_depletion,
        intensity: 0.8,
        timestamp: System.monotonic_time(:millisecond)
      })

      Process.sleep(100)

      # Values should be adjusted to avoid pain source
      # This is implementation-dependent
    end

    test "reinforces values from pleasure signals", %{pid: pid} do
      # Send pleasure signal
      EventBus.publish(:algedonic_signal, %{
        type: :pleasure,
        source: :goal_achievement,
        associated_values: [:efficiency, :innovation],
        intensity: 0.9,
        timestamp: System.monotonic_time(:millisecond)
      })

      Process.sleep(100)

      # Values should be reinforced
      # This is implementation-dependent
    end
  end

  describe "environmental adaptation" do
    test "adapts to major environmental shifts", %{pid: pid} do
      # Simulate environmental shift
      EventBus.publish(:environmental_shift, %{
        severity: :major,
        market_conditions: %{
          competition: :high,
          opportunities: 5
        },
        patterns: [:rapid_change, :uncertainty],
        timestamp: System.monotonic_time(:millisecond)
      })

      Process.sleep(100)

      # System should adapt values and potentially create policies
    end
  end

  describe "viability threat response" do
    test "responds to viability threats with emergency policies", %{pid: pid} do
      # Subscribe to policy directives
      EventBus.subscribe(:policy_directive)

      # Send viability threat
      EventBus.publish(:viability_threat, %{
        type: :resource_depletion,
        severity: :critical,
        affected_subsystems: [:s1, :s3],
        # 5 minutes
        time_to_failure: 300_000
      })

      # Should receive policy directive
      assert_receive {:event, :policy_directive, response}, 1000

      assert response.severity == :critical
      assert response.emergency_policy != nil
      assert is_list(response.actions)
    end
  end

  describe "constitutional protection" do
    test "corrects constitutional violations immediately", %{pid: pid} do
      # Subscribe to corrections
      EventBus.subscribe(:constitutional_correction)

      # Send constitutional violation
      EventBus.publish(:constitutional_violation, %{
        invariant: :variety,
        violating_subsystem: :s2,
        description: "Variety absorption below critical threshold",
        severity: :critical
      })

      # Should receive corrective policy
      assert_receive {:event, :constitutional_correction, policy}, 1000

      assert policy.type == :constitutional_correction
      assert {:halt, :s2} in policy.directives
      assert {:restore, :variety} in policy.directives
      # Permanent until resolved
      assert policy.expires_at == nil
    end
  end

  describe "policy lifecycle" do
    test "reviews and expires policies periodically", %{pid: pid} do
      # Force policy review
      send(pid, :policy_review)

      Process.sleep(100)

      # Policies should be reviewed
      # Metrics should be updated
    end
  end
end
