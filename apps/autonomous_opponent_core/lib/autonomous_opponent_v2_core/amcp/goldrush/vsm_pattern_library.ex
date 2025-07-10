defmodule AutonomousOpponentV2Core.AMCP.Goldrush.VSMPatternLibrary do
  @moduledoc """
  Comprehensive VSM failure pattern library based on Beer's cybernetic principles.
  
  This library contains operational patterns for detecting known VSM failure modes,
  integration failures, technical implementation issues, and distributed system challenges.
  
  Patterns are categorized by:
  - Severity: critical, high, medium, low
  - Domain: cybernetic, integration, technical, distributed
  - Detection: thresholds, indicators, early warnings
  - Response: algedonic signals, recovery strategies
  """
  
  
  # ============================================================================
  # CYBERNETIC FAILURE PATTERNS (Beer's VSM Theory)
  # ============================================================================
  
  @cybernetic_patterns %{
    # Critical: System viability at risk
    variety_overflow: %{
      type: :variety_overflow,
      domain: :cybernetic,
      severity: :critical,
      description: "S1 operational variety exceeds absorption capacity",
      detection: %{
        threshold: "V(environment) > V(system) * 1.5",
        indicators: [
          "s1_variety_buffer > 1000",
          "processing_latency > 1s",
          "message_queue_length > 10_000"
        ],
        early_warning: "variety_ratio > 1.3"
      },
      variety_engineering: %{
        immediate: :aggressive_attenuation,
        amplification_factor: 0.5,
        emergency_bypass: true
      },
      algedonic_response: %{
        pain_level: 0.9,
        urgency: 1.0,
        bypass_hierarchy: true,
        target: :s5_emergency
      }
    },
    
    control_loop_oscillation: %{
      type: :control_loop_oscillation,
      domain: :cybernetic,
      severity: :critical,
      description: "S3 control adjustments create unstable feedback loops",
      detection: %{
        threshold: "oscillation_frequency > 0.5 Hz AND amplitude > 30% of setpoint",
        indicators: [
          "control_changes > 10 per minute",
          "opposing_commands within 5s",
          "s2_anti_oscillation_triggered"
        ],
        early_warning: "control_variance > 0.2"
      },
      variety_engineering: %{
        damping_required: true,
        temporal_smoothing: "30s window",
        s2_coordination: :mandatory
      },
      algedonic_response: %{
        pain_level: 0.8,
        urgency: 0.9,
        bypass_hierarchy: true,
        target: [:s3, :s5]
      }
    },
    
    metasystemic_cascade: %{
      type: :metasystemic_cascade,
      domain: :cybernetic,
      severity: :critical,
      description: "Failure propagates upward through VSM hierarchy",
      detection: %{
        threshold: "failure_rate > 70% at any level",
        indicators: [
          "s1_failure → s2_failure within 60s",
          "multiple_subsystem_restarts",
          "supervisor max_restarts exceeded"
        ],
        early_warning: "subsystem_health < 0.5"
      },
      variety_engineering: %{
        circuit_breakers: :all_levels,
        isolation_required: true,
        fallback_mode: :degraded_operation
      },
      algedonic_response: %{
        pain_level: 1.0,
        urgency: 1.0,
        bypass_hierarchy: true,
        target: :all_channel_broadcast
      }
    },
    
    # High severity: Operational degradation
    coordination_breakdown: %{
      type: :coordination_breakdown,
      domain: :cybernetic,
      severity: :high,
      description: "S2 fails to synchronize S1 operations",
      detection: %{
        threshold: "synchronization_error > 50%",
        indicators: [
          "s1_conflict_rate > 30%",
          "s2_queue_overflow",
          "coordination_timeout_rate > 0.2"
        ],
        early_warning: "s2_processing_lag > 500ms"
      },
      variety_engineering: %{
        temporal_buffering: true,
        conflict_resolution: :last_write_wins,
        s1_throttling: :adaptive
      },
      algedonic_response: %{
        pain_level: 0.7,
        urgency: 0.8,
        target: [:s2, :s3]
      }
    },
    
    intelligence_blindness: %{
      type: :intelligence_blindness,
      domain: :cybernetic,
      severity: :high,
      description: "S4 fails to detect environmental changes",
      detection: %{
        threshold: "environmental_scan_latency > 5x normal",
        indicators: [
          "pattern_detection_lag > 30s",
          "missed_events > 10%",
          "s4_queue_depth > 1000"
        ],
        early_warning: "scan_frequency < 0.1 Hz"
      },
      variety_engineering: %{
        sensory_amplification: 2.0,
        pattern_cache_size: 10_000,
        parallel_scanning: true
      },
      algedonic_response: %{
        pain_level: 0.6,
        urgency: 0.6,
        target: :s4_priority
      }
    },
    
    policy_drift: %{
      type: :policy_drift,
      domain: :cybernetic,
      severity: :high,
      description: "S5 policy constraints misaligned with reality",
      detection: %{
        threshold: "policy_compliance < 60%",
        indicators: [
          "policy_override_rate > 0.4",
          "s5_revision_frequency > 10/hour",
          "constraint_violations > 100/minute"
        ],
        early_warning: "policy_effectiveness < 0.7"
      },
      variety_engineering: %{
        policy_learning: :enabled,
        constraint_relaxation: :adaptive,
        feedback_integration: true
      },
      algedonic_response: %{
        pain_level: 0.7,
        urgency: 0.5,
        target: :s5_governance
      }
    }
  }
  
  # ============================================================================
  # V1 COMPONENT INTEGRATION PATTERNS
  # ============================================================================
  
  @integration_patterns %{
    eventbus_message_overflow: %{
      type: :eventbus_message_overflow,
      domain: :integration,
      severity: :high,
      description: "EventBus publishes faster than VSM can process",
      detection: %{
        threshold: "buffer_size > 800",
        indicators: [
          "eventbus_publish_rate > 1000/s",
          "s1_buffer_utilization > 0.8",
          "process_mailbox_size > 10_000"
        ],
        early_warning: "publish_to_process_ratio > 2:1"
      },
      v1_component: :event_bus,
      vsm_impact: %{
        s1: :variety_buffer_overflow,
        s2: :coordination_breakdown,
        s3: :resource_allocation_failure
      },
      mitigation: %{
        backpressure: true,
        selective_subscription: true,
        event_aggregation: true
      }
    },
    
    circuit_breaker_pain_loop: %{
      type: :circuit_breaker_pain_loop,
      domain: :integration,
      severity: :high,
      description: "CircuitBreaker pain signals create feedback loops",
      detection: %{
        threshold: "pain_triggered_opens > 3 in 60s",
        indicators: [
          "circuit_open → pain → more_load → circuit_open",
          "pain_intensity > 0.8",
          "emergency_scream_triggered"
        ],
        early_warning: "pain_correlation > 0.7"
      },
      v1_component: :circuit_breaker,
      vsm_impact: %{
        s5: :policy_confusion,
        s1: :variety_explosion,
        algedonic: :signal_storm
      },
      mitigation: %{
        pain_debouncing: "5s window",
        correlation_breaking: true,
        adaptive_thresholds: true
      }
    },
    
    rate_limiter_variety_starvation: %{
      type: :rate_limiter_variety_starvation,
      domain: :integration,
      severity: :medium,
      description: "RateLimiter over-attenuates variety",
      detection: %{
        threshold: "rejection_rate > 20%",
        indicators: [
          "s1_request_rate < minimum_viable_variety",
          "subsystem_limits < 10 req/s",
          "variety_pressure < 0.3"
        ],
        early_warning: "available_tokens < 0.2 * max_tokens"
      },
      v1_component: :rate_limiter,
      vsm_impact: %{
        s1: :operational_starvation,
        s2: :coordination_throttled,
        s4: :intelligence_limited
      },
      mitigation: %{
        vsm_aware_limits: true,
        subsystem_specific_rates: true,
        dynamic_adjustment: true
      }
    }
  }
  
  # ============================================================================
  # TECHNICAL ELIXIR/OTP PATTERNS
  # ============================================================================
  
  @technical_patterns %{
    genserver_mailbox_overflow: %{
      type: :genserver_mailbox_overflow,
      domain: :technical,
      severity: :high,
      description: "GenServer process mailbox accumulation",
      detection: %{
        threshold: "message_queue_len > 10_000",
        indicators: [
          "process_memory > 100MB",
          "message_processing_lag > 1s",
          "genserver_call_timeout"
        ],
        early_warning: "message_queue_len > 1_000"
      },
      technical_details: %{
        affected_processes: [:s1_operations, :pattern_detector],
        memory_impact: :high,
        gc_pressure: :severe
      },
      mitigation: %{
        selective_receive: true,
        process_pool: true,
        message_shedding: true
      }
    },
    
    ets_table_overflow: %{
      type: :ets_table_overflow,
      domain: :technical,
      severity: :medium,
      description: "ETS tables exceed memory limits",
      detection: %{
        threshold: "table_size > 1_000_000",
        indicators: [
          "ets_memory > 1GB",
          "table_lookup_time > 10ms",
          "memory_allocation_failures"
        ],
        early_warning: "table_size > 500_000"
      },
      technical_details: %{
        affected_tables: [:temporal_events_timeline, :temporal_pattern_cache],
        memory_type: :ets,
        impact: :query_performance
      },
      mitigation: %{
        table_rotation: true,
        ttl_enforcement: true,
        size_based_eviction: true
      }
    },
    
    supervisor_cascade_failure: %{
      type: :supervisor_cascade_failure,
      domain: :technical,
      severity: :critical,
      description: "Supervisor restart limit exceeded",
      detection: %{
        threshold: "restarts > max_restarts in max_seconds",
        indicators: [
          "supervisor_shutdown",
          "application_termination",
          "multiple_subsystem_failures"
        ],
        early_warning: "restart_count > max_restarts * 0.7"
      },
      technical_details: %{
        supervisor_strategy: :rest_for_one,
        max_restarts: 10,
        max_seconds: 60
      },
      mitigation: %{
        restart_strategy_adjustment: true,
        exponential_backoff: true,
        circuit_breaker_integration: true
      }
    }
  }
  
  # ============================================================================
  # DISTRIBUTED SYSTEM PATTERNS
  # ============================================================================
  
  @distributed_patterns %{
    crdt_divergence: %{
      type: :crdt_divergence,
      domain: :distributed,
      severity: :high,
      description: "CRDT state divergence during partitions",
      detection: %{
        threshold: "sync_failures > 3 OR vector_clock_drift > 60s",
        indicators: [
          "merge_conflict_rate > 0.1",
          "peer_connection_failures",
          "inconsistent_read_results"
        ],
        early_warning: "sync_latency > 5s"
      },
      distributed_impact: %{
        consistency: :eventual,
        availability: :maintained,
        partition_tolerance: :active
      },
      mitigation: %{
        forced_sync: true,
        merkle_tree_reconciliation: true,
        read_repair: true
      }
    },
    
    distributed_algedonic_storm: %{
      type: :distributed_algedonic_storm,
      domain: :distributed,
      severity: :high,
      description: "Pain signals cascade across nodes",
      detection: %{
        threshold: "pain_signal_rate > 100/s",
        indicators: [
          "cross_node_pain_propagation",
          "algedonic_queue_overflow",
          "emergency_broadcast_storms"
        ],
        early_warning: "pain_signal_rate > 50/s"
      },
      distributed_impact: %{
        network_saturation: true,
        decision_paralysis: true,
        cascade_risk: :extreme
      },
      mitigation: %{
        pain_aggregation: true,
        storm_detection: true,
        circuit_breaker: true
      }
    },
    
    clock_skew_ordering: %{
      type: :clock_skew_ordering,
      domain: :distributed,
      severity: :medium,
      description: "HLC ordering violations from clock drift",
      detection: %{
        threshold: "clock_skew > 30s",
        indicators: [
          "hlc_physical_drift > 30s",
          "causal_ordering_violations",
          "event_timestamp_inversions"
        ],
        early_warning: "clock_skew > 10s"
      },
      distributed_impact: %{
        event_ordering: :compromised,
        causality: :violated,
        pattern_detection: :unreliable
      },
      mitigation: %{
        ntp_enforcement: true,
        hlc_recalibration: true,
        drift_compensation: true
      }
    }
  }
  
  # ============================================================================
  # PUBLIC API
  # ============================================================================
  
  @doc """
  Get all patterns organized by domain and severity.
  """
  def all_patterns do
    %{
      cybernetic: @cybernetic_patterns,
      integration: @integration_patterns,
      technical: @technical_patterns,
      distributed: @distributed_patterns
    }
  end
  
  @doc """
  Get patterns by severity level.
  """
  def patterns_by_severity(severity) when severity in [:critical, :high, :medium, :low] do
    all_patterns()
    |> Enum.flat_map(fn {_domain, patterns} ->
      patterns
      |> Enum.filter(fn {_name, pattern} -> pattern.severity == severity end)
      |> Enum.map(fn {name, pattern} -> {name, pattern} end)
    end)
    |> Enum.into(%{})
  end
  
  @doc """
  Get patterns by domain.
  """
  def patterns_by_domain(domain) when domain in [:cybernetic, :integration, :technical, :distributed] do
    Map.get(all_patterns(), domain, %{})
  end
  
  @doc """
  Convert pattern to PatternMatcher format.
  """
  def to_pattern_matcher_format(_pattern_name, pattern) do
    # PatternMatcher expects just the pattern conditions for compilation
    pattern_data = build_conditions(pattern)
    # Extract only the conditions part for PatternMatcher
    pattern_data.conditions
  end
  
  @doc """
  Get early warning patterns.
  """
  def early_warning_patterns do
    all_patterns()
    |> Enum.flat_map(fn {_domain, patterns} ->
      patterns
      |> Enum.map(fn {name, pattern} ->
        {name, pattern.detection.early_warning}
      end)
    end)
    |> Enum.into(%{})
  end

  @doc """
  Get a specific pattern by domain and name, supporting aliases.
  """
  def get_pattern(domain, name) when domain in [:cybernetic, :integration, :technical, :distributed] do
    # First check for aliases
    resolved_name = resolve_pattern_alias(name)
    
    # Then look up the pattern
    patterns = Map.get(all_patterns(), domain, %{})
    Map.get(patterns, resolved_name)
  end

  @doc """
  Pattern aliases for issue #86 compliance.
  Maps alternative names to canonical pattern names.
  """
  def pattern_aliases do
    %{
      system_overload: :variety_overflow,
      resource_starvation: :rate_limiter_variety_starvation
    }
  end
  
  # ============================================================================
  # PRIVATE FUNCTIONS
  # ============================================================================

  defp resolve_pattern_alias(name) do
    Map.get(pattern_aliases(), name, name)
  end
  
  defp build_conditions(pattern) do
    # Build conditions that PatternMatcher can understand
    # Return consistent structure for all patterns
    conditions = case pattern.type do
      :variety_overflow ->
        %{
          and: [
            %{variety_ratio: %{gte: 1.5}},
            %{s1_variety_buffer: %{gt: 1000}},
            %{processing_latency: %{gt: 1000}},
            %{message_queue_length: %{gt: 10_000}}
          ]
        }
      
      :control_loop_oscillation ->
        %{
          and: [
            %{type: :s3_control},
            %{frequency: %{gte: 0.5}},
            %{amplitude: %{gte: 0.3}}
          ]
        }
        
      :metasystemic_cascade ->
        %{
          and: [
            %{type: :subsystem_failure},
            %{failure_rate: %{gte: 0.7}}
          ]
        }
        
      :genserver_mailbox_overflow ->
        %{
          and: [
            %{message_queue_len: %{gt: 10_000}},
            %{process_memory: %{gt: 100_000_000}}
          ]
        }
        
      :ets_table_overflow ->
        %{
          and: [
            %{table_size: %{gt: 1_000_000}}
          ]
        }
        
      :supervisor_cascade_failure ->
        %{
          and: [
            %{restarts: %{gt: 10}}
          ]
        }
        
      _ ->
        # Default pattern with consistent structure
        %{
          and: [
            %{type: pattern.type}
          ]
        }
    end
    
    # Return standardized format with type and conditions
    %{
      type: pattern.type,
      conditions: conditions
    }
  end
end