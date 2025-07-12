defmodule AutonomousOpponentV2Core.PatternFixtures do
  @moduledoc """
  Test fixtures for pattern-related tests.
  Provides sample patterns for each type with various severities and edge cases.
  """

  alias AutonomousOpponentV2Core.VSM.Clock

  # Sample patterns for each type with various severities
  def error_cascade_pattern(attrs \\ %{}) do
    base_pattern = %{
      pattern_type: :error_cascade,
      pattern_name: "database_connection_failures",
      severity: :critical,
      confidence: 0.85,
      environmental_context: %{
        affected_subsystems: [:s1, :s2],
        variety_pressure: 0.9,
        temporal_characteristics: %{
          duration: 300_000,  # 5 minutes
          frequency: 15,      # 15 occurrences
          trend: :accelerating
        },
        system_stress_indicators: [:emergency_level_critical, :rate_threshold_exceeded]
      },
      vsm_impact: %{
        impact_level: :severe,
        variety_pressure: 0.9,
        cybernetic_implications: [:variety_overflow, :control_loop_breakdown, :recursive_failure],
        affected_control_loops: [:operational_loop, :coordination_loop, :control_loop]
      },
      timestamp: Clock.now() |> elem(1),
      source: :temporal_pattern_detector,
      s4_processing_priority: :immediate,
      emergency_level: :critical,
      actual_rate: 300,
      threshold: 100
    }
    
    Map.merge(base_pattern, attrs)
  end

  def algedonic_storm_pattern(attrs \\ %{}) do
    base_pattern = %{
      pattern_type: :algedonic_storm,
      pattern_name: "critical_system_pain",
      severity: :critical,
      confidence: 0.92,
      environmental_context: %{
        affected_subsystems: [:s1, :s3, :s5],
        variety_pressure: 0.95,
        temporal_characteristics: %{
          duration: 180_000,  # 3 minutes
          frequency: 50,
          trend: :critical_spike
        },
        system_stress_indicators: [:emergency_level_critical, :system_coordination_stress]
      },
      vsm_impact: %{
        impact_level: :severe,
        variety_pressure: 0.95,
        cybernetic_implications: [:pain_signal_amplification, :emergency_response_required],
        affected_control_loops: [:algedonic_loop, :emergency_response_loop]
      },
      timestamp: Clock.now() |> elem(1),
      source: :temporal_pattern_detector,
      s4_processing_priority: :immediate,
      emergency_level: :extreme,
      urgency: 0.95
    }
    
    Map.merge(base_pattern, attrs)
  end

  def coordination_breakdown_pattern(attrs \\ %{}) do
    base_pattern = %{
      pattern_type: :coordination_breakdown,
      pattern_name: "s2_anti_oscillation_failure",
      severity: :high,
      confidence: 0.78,
      environmental_context: %{
        affected_subsystems: [:s1, :s2],
        variety_pressure: 0.7,
        temporal_characteristics: %{
          duration: 600_000,  # 10 minutes
          frequency: 8,
          trend: :increasing
        },
        system_stress_indicators: [:system_coordination_stress]
      },
      vsm_impact: %{
        impact_level: :moderate,
        variety_pressure: 0.7,
        cybernetic_implications: [:anti_oscillation_failure, :s2_dysfunction],
        affected_control_loops: [:coordination_loop, :anti_oscillation_loop, :s1_control_loop, :s2_control_loop]
      },
      timestamp: Clock.now() |> elem(1),
      source: :temporal_pattern_detector,
      s4_processing_priority: :high,
      subsystems: [:s1, :s2]
    }
    
    Map.merge(base_pattern, attrs)
  end

  def variety_overload_pattern(attrs \\ %{}) do
    base_pattern = %{
      pattern_type: :variety_overload,
      pattern_name: "input_variety_exceeding_capacity",
      severity: :medium,
      confidence: 0.72,
      environmental_context: %{
        affected_subsystems: [:s1],
        variety_pressure: 0.8,
        temporal_characteristics: %{
          duration: 900_000,  # 15 minutes
          frequency: 5,
          trend: :stable
        },
        system_stress_indicators: [:rate_threshold_exceeded]
      },
      vsm_impact: %{
        impact_level: :mild,
        variety_pressure: 0.8,
        cybernetic_implications: [:capacity_exceeded, :attenuation_required],
        affected_control_loops: [:operational_loop, :capacity_management_loop, :s1_control_loop]
      },
      timestamp: Clock.now() |> elem(1),
      source: :temporal_pattern_detector,
      s4_processing_priority: :normal,
      actual_rate: 200,
      threshold: 150
    }
    
    Map.merge(base_pattern, attrs)
  end

  def consciousness_instability_pattern(attrs \\ %{}) do
    base_pattern = %{
      pattern_type: :consciousness_instability,
      pattern_name: "metacognitive_state_oscillation",
      severity: :high,
      confidence: 0.68,
      environmental_context: %{
        affected_subsystems: [:s3, :s4, :s5],
        variety_pressure: 0.65,
        temporal_characteristics: %{
          duration: 1_200_000,  # 20 minutes
          frequency: 12,
          trend: :increasing
        },
        system_stress_indicators: []
      },
      vsm_impact: %{
        impact_level: :moderate,
        variety_pressure: 0.65,
        cybernetic_implications: [:metacognitive_disruption, :state_regulation_failure],
        affected_control_loops: [:cognitive_loop, :metacognitive_loop, :s3_control_loop, :s4_control_loop, :s5_control_loop]
      },
      timestamp: Clock.now() |> elem(1),
      source: :temporal_pattern_detector,
      s4_processing_priority: :high
    }
    
    Map.merge(base_pattern, attrs)
  end

  def rate_burst_pattern(attrs \\ %{}) do
    base_pattern = %{
      pattern_type: :rate_burst,
      pattern_name: "message_rate_spike",
      severity: :medium,
      confidence: 0.82,
      environmental_context: %{
        affected_subsystems: [:s1],
        variety_pressure: 0.6,
        temporal_characteristics: %{
          duration: 60_000,  # 1 minute
          frequency: 100,
          trend: :stable
        },
        system_stress_indicators: [:rate_threshold_exceeded]
      },
      vsm_impact: %{
        impact_level: :mild,
        variety_pressure: 0.6,
        cybernetic_implications: [:capacity_exceeded, :attenuation_required],
        affected_control_loops: [:operational_loop, :capacity_management_loop, :s1_control_loop]
      },
      timestamp: Clock.now() |> elem(1),
      source: :temporal_pattern_detector,
      s4_processing_priority: :normal,
      actual_rate: 180,
      threshold: 100
    }
    
    Map.merge(base_pattern, attrs)
  end

  def environmental_shift_pattern(attrs \\ %{}) do
    base_pattern = %{
      pattern_type: :environmental_shift,
      pattern_name: "market_volatility_increase",
      severity: :high,
      confidence: 0.77,
      environmental_context: %{
        affected_subsystems: [:s4, :s5],
        variety_pressure: 0.75,
        temporal_characteristics: %{
          duration: 3_600_000,  # 1 hour
          frequency: 3,
          trend: :escalating
        },
        system_stress_indicators: []
      },
      vsm_impact: %{
        impact_level: :moderate,
        variety_pressure: 0.75,
        cybernetic_implications: [:environmental_variation],
        affected_control_loops: [:monitoring_loop, :s4_control_loop, :s5_control_loop]
      },
      timestamp: Clock.now() |> elem(1),
      source: :temporal_pattern_detector,
      s4_processing_priority: :high
    }
    
    Map.merge(base_pattern, attrs)
  end

  # Edge case patterns

  def low_confidence_pattern(attrs \\ %{}) do
    base_pattern = %{
      pattern_type: :unknown_pattern,
      pattern_name: "ambiguous_signal",
      severity: :low,
      confidence: 0.45,  # Below threshold
      environmental_context: %{
        affected_subsystems: [],
        variety_pressure: 0.2,
        temporal_characteristics: %{
          duration: 0,
          frequency: 1,
          trend: :stable
        },
        system_stress_indicators: []
      },
      vsm_impact: %{
        impact_level: :minimal,
        variety_pressure: 0.2,
        cybernetic_implications: [:environmental_variation],
        affected_control_loops: [:monitoring_loop]
      },
      timestamp: Clock.now() |> elem(1),
      source: :temporal_pattern_detector,
      s4_processing_priority: :low
    }
    
    Map.merge(base_pattern, attrs)
  end

  def missing_fields_pattern(attrs \\ %{}) do
    # Pattern with missing optional fields
    base_pattern = %{
      pattern_type: :error_cascade,
      pattern_name: "incomplete_pattern_data",
      # Missing: severity, confidence, emergency_level, urgency
      environmental_context: %{
        affected_subsystems: [:s1],
        variety_pressure: 0.5,
        temporal_characteristics: %{
          duration: 100_000,
          frequency: 5,
          trend: :stable
        },
        system_stress_indicators: []
      },
      timestamp: Clock.now() |> elem(1),
      source: :temporal_pattern_detector,
      s4_processing_priority: :normal
    }
    
    Map.merge(base_pattern, attrs)
  end

  def malformed_pattern(attrs \\ %{}) do
    # Pattern with invalid structure
    base_pattern = %{
      pattern_type: "invalid_string_type",  # Should be atom
      pattern_name: nil,  # Should be string
      severity: "invalid",  # Should be atom
      confidence: 1.5,  # Should be 0.0-1.0
      environmental_context: "not_a_map",  # Should be map
      timestamp: "not_a_timestamp",  # Should be HLC timestamp
      source: :temporal_pattern_detector
    }
    
    Map.merge(base_pattern, attrs)
  end

  # High-volume pattern sets for load testing

  def generate_pattern_batch(count, type \\ :mixed) do
    pattern_generators = case type do
      :error_cascade -> [&error_cascade_pattern/1]
      :algedonic_storm -> [&algedonic_storm_pattern/1]
      :coordination_breakdown -> [&coordination_breakdown_pattern/1]
      :variety_overload -> [&variety_overload_pattern/1]
      :rate_burst -> [&rate_burst_pattern/1]
      :mixed -> [
        &error_cascade_pattern/1,
        &algedonic_storm_pattern/1,
        &coordination_breakdown_pattern/1,
        &variety_overload_pattern/1,
        &consciousness_instability_pattern/1,
        &rate_burst_pattern/1,
        &environmental_shift_pattern/1
      ]
    end
    
    Enum.map(1..count, fn i ->
      generator = Enum.at(pattern_generators, rem(i, length(pattern_generators)))
      {:ok, timestamp} = Clock.now()
      
      generator.(%{
        pattern_name: "batch_pattern_#{i}",
        confidence: 0.7 + :rand.uniform() * 0.29,  # 0.7-0.99
        timestamp: %{
          physical: timestamp.physical + i * 100,
          logical: timestamp.logical + i,
          node_id: timestamp.node_id
        }
      })
    end)
  end

  # Pattern for temporal event testing
  def temporal_pattern_event(attrs \\ %{}) do
    base_event = %{
      type: :temporal_pattern_detected,
      pattern_data: error_cascade_pattern(),
      metadata: %{
        detection_timestamp: Clock.now() |> elem(1),
        detector_version: "1.0.0",
        detection_confidence: 0.87
      }
    }
    
    Map.merge(base_event, attrs)
  end

  # S4 environmental signal for testing
  def s4_environmental_signal(urgency \\ 0.8, attrs \\ %{}) do
    pattern = if urgency >= 0.9, do: algedonic_storm_pattern(), else: error_cascade_pattern()
    
    base_signal = %{
      type: :pattern_alert,
      pattern: pattern,
      urgency: urgency,
      recommended_s4_actions: [:increase_monitoring, :prepare_isolation, :alert_s3_control, :scenario_modeling],
      environmental_impact: :cascading_failure_risk
    }
    
    Map.merge(base_signal, attrs)
  end

  # Pattern indexing event
  def pattern_indexing_event(count \\ 100, attrs \\ %{}) do
    base_event = %{
      count: count,
      source: :pattern_detector,
      index_type: :hnsw,
      timestamp: Clock.now() |> elem(1),
      status: :success
    }
    
    Map.merge(base_event, attrs)
  end
end