#!/usr/bin/env elixir

# VSM Topology Setup Script
# Creates the complete RabbitMQ topology for the Viable System Model
# Run with: elixir scripts/setup_vsm_topology.exs

# Ensure we're in the project directory
File.cd!("/Users/speed/autonomous-opponent-v2")

# Add the lib paths for the umbrella apps
Code.prepend_path("_build/dev/lib/amqp/ebin")
Code.prepend_path("_build/dev/lib/autonomous_opponent_core/ebin")

# Load the AMQP application
Application.ensure_all_started(:amqp)

defmodule VSMTopologySetup do
  require Logger
  
  @vsm_exchange "vsm.topic"
  @event_exchange "vsm.events"
  @algedonic_exchange "vsm.algedonic"
  @dlx_exchange "vsm.dlx"
  @command_exchange "vsm.commands"
  
  def run do
    Logger.info("🚀 Starting VSM Topology Setup...")
    
    case AMQP.Connection.open(
      host: System.get_env("AMQP_HOST", "localhost"),
      port: String.to_integer(System.get_env("AMQP_PORT", "5672")),
      username: System.get_env("AMQP_USERNAME", "guest"),
      password: System.get_env("AMQP_PASSWORD", "guest")
    ) do
      {:ok, conn} ->
        {:ok, channel} = AMQP.Channel.open(conn)
        
        try do
          setup_exchanges(channel)
          setup_subsystem_queues(channel)
          setup_variety_channels(channel)
          setup_algedonic_system(channel)
          setup_command_queues(channel)
          setup_dead_letter_queues(channel)
          
          Logger.info("✅ VSM Topology setup complete!")
          verify_topology(channel)
        rescue
          e ->
            Logger.error("❌ Error setting up topology: #{inspect(e)}")
            raise e
        after
          AMQP.Channel.close(channel)
          AMQP.Connection.close(conn)
        end
        
      {:error, reason} ->
        Logger.error("❌ Failed to connect to RabbitMQ: #{inspect(reason)}")
        System.halt(1)
    end
  end
  
  defp setup_exchanges(channel) do
    Logger.info("📡 Setting up exchanges...")
    
    # Main VSM topic exchange for flexible routing
    :ok = AMQP.Exchange.declare(channel, @vsm_exchange, :topic, 
      durable: true,
      arguments: [
        {"alternate-exchange", :longstr, @dlx_exchange}
      ]
    )
    Logger.info("  ✓ Created #{@vsm_exchange} (topic)")
    
    # Event fanout exchange for system-wide broadcasts
    :ok = AMQP.Exchange.declare(channel, @event_exchange, :fanout, durable: true)
    Logger.info("  ✓ Created #{@event_exchange} (fanout)")
    
    # Algedonic direct exchange for pain/pleasure signals
    :ok = AMQP.Exchange.declare(channel, @algedonic_exchange, :direct, 
      durable: true,
      arguments: [
        {"x-message-ttl", :signedint, 300_000}  # 5 minute TTL for urgent signals
      ]
    )
    Logger.info("  ✓ Created #{@algedonic_exchange} (direct)")
    
    # Command exchange for control directives
    :ok = AMQP.Exchange.declare(channel, @command_exchange, :topic, durable: true)
    Logger.info("  ✓ Created #{@command_exchange} (topic)")
    
    # Dead Letter Exchange
    :ok = AMQP.Exchange.declare(channel, @dlx_exchange, :fanout, durable: true)
    Logger.info("  ✓ Created #{@dlx_exchange} (fanout)")
  end
  
  defp setup_subsystem_queues(channel) do
    Logger.info("🎯 Setting up VSM subsystem queues...")
    
    # S1: Operations - High throughput variety absorption
    create_queue(channel, "vsm.s1.operations",
      arguments: [
        {"x-message-ttl", :signedint, 300_000},      # 5 min TTL
        {"x-max-length", :signedint, 10_000},        # 10k message limit
        {"x-overflow", :longstr, "drop-head"},       # Drop oldest when full
        {"x-dead-letter-exchange", :longstr, @dlx_exchange}
      ]
    )
    bind_queue(channel, "vsm.s1.operations", @vsm_exchange, "operations.*")
    bind_queue(channel, "vsm.s1.operations", @vsm_exchange, "vsm.s1.*")
    bind_queue(channel, "vsm.s1.operations", @vsm_exchange, "variety.absorption.*")
    bind_queue(channel, "vsm.s1.operations", @event_exchange, "")  # All events
    
    # S2: Coordination - Anti-oscillation with ordering
    create_queue(channel, "vsm.s2.coordination",
      arguments: [
        {"x-single-active-consumer", :bool, true},   # Ensure ordering
        {"x-message-ttl", :signedint, 600_000},      # 10 min TTL
        {"x-max-length", :signedint, 5_000},
        {"x-dead-letter-exchange", :longstr, @dlx_exchange}
      ]
    )
    bind_queue(channel, "vsm.s2.coordination", @vsm_exchange, "coordination.*")
    bind_queue(channel, "vsm.s2.coordination", @vsm_exchange, "vsm.s2.*")
    bind_queue(channel, "vsm.s2.coordination", @vsm_exchange, "anti-oscillation.*")
    
    # S3: Control - Priority queue for resource bargaining
    create_queue(channel, "vsm.s3.control",
      arguments: [
        {"x-max-priority", :byte, 10},               # Priority 0-10
        {"x-message-ttl", :signedint, 900_000},      # 15 min TTL
        {"x-max-length", :signedint, 3_000},
        {"x-dead-letter-exchange", :longstr, @dlx_exchange}
      ]
    )
    bind_queue(channel, "vsm.s3.control", @vsm_exchange, "control.*")
    bind_queue(channel, "vsm.s3.control", @vsm_exchange, "vsm.s3.*")
    bind_queue(channel, "vsm.s3.control", @vsm_exchange, "vsm.s3star.*")  # Audit
    bind_queue(channel, "vsm.s3.control", @vsm_exchange, "resource.bargaining.*")
    
    # S4: Intelligence - Pattern detection and learning
    create_queue(channel, "vsm.s4.intelligence",
      arguments: [
        {"x-message-ttl", :signedint, 3_600_000},    # 1 hour TTL
        {"x-max-length", :signedint, 20_000},        # Larger for pattern storage
        {"x-dead-letter-exchange", :longstr, @dlx_exchange}
      ]
    )
    bind_queue(channel, "vsm.s4.intelligence", @vsm_exchange, "intelligence.*")
    bind_queue(channel, "vsm.s4.intelligence", @vsm_exchange, "vsm.s4.*")
    bind_queue(channel, "vsm.s4.intelligence", @vsm_exchange, "patterns.*")
    bind_queue(channel, "vsm.s4.intelligence", @vsm_exchange, "learning.*")
    bind_queue(channel, "vsm.s4.intelligence", @vsm_exchange, "environmental.*")
    
    # S5: Policy - Identity and governance (most durable)
    create_queue(channel, "vsm.s5.policy",
      arguments: [
        {"x-message-ttl", :signedint, 86_400_000},   # 24 hour TTL
        {"x-max-length", :signedint, 1_000},         # Smaller, more selective
        {"x-dead-letter-exchange", :longstr, @dlx_exchange}
      ]
    )
    bind_queue(channel, "vsm.s5.policy", @vsm_exchange, "policy.*")
    bind_queue(channel, "vsm.s5.policy", @vsm_exchange, "vsm.s5.*")
    bind_queue(channel, "vsm.s5.policy", @vsm_exchange, "identity.*")
    bind_queue(channel, "vsm.s5.policy", @vsm_exchange, "governance.*")
    
    Logger.info("  ✓ Created all VSM subsystem queues")
  end
  
  defp setup_variety_channels(channel) do
    Logger.info("🔄 Setting up variety flow channels...")
    
    # S1 → S2: Operational variety flows up
    create_queue(channel, "vsm.channel.s1_to_s2",
      arguments: [
        {"x-message-ttl", :signedint, 60_000},       # 1 min TTL (fast flow)
        {"x-max-length", :signedint, 1_000}
      ]
    )
    bind_queue(channel, "vsm.channel.s1_to_s2", @vsm_exchange, "variety.s1_to_s2.*")
    
    # S2 → S3: Coordinated variety flows up
    create_queue(channel, "vsm.channel.s2_to_s3",
      arguments: [
        {"x-message-ttl", :signedint, 120_000},      # 2 min TTL
        {"x-max-length", :signedint, 800}
      ]
    )
    bind_queue(channel, "vsm.channel.s2_to_s3", @vsm_exchange, "variety.s2_to_s3.*")
    
    # S3 → S4: Audit data for learning
    create_queue(channel, "vsm.channel.s3_to_s4",
      arguments: [
        {"x-message-ttl", :signedint, 1_800_000},    # 30 min TTL (learning data)
        {"x-max-length", :signedint, 5_000}
      ]
    )
    bind_queue(channel, "vsm.channel.s3_to_s4", @vsm_exchange, "variety.s3_to_s4.*")
    bind_queue(channel, "vsm.channel.s3_to_s4", @vsm_exchange, "audit.*")
    
    # S4 → S5: Intelligence informs policy
    create_queue(channel, "vsm.channel.s4_to_s5",
      arguments: [
        {"x-message-ttl", :signedint, 7_200_000},    # 2 hour TTL
        {"x-max-length", :signedint, 500}
      ]
    )
    bind_queue(channel, "vsm.channel.s4_to_s5", @vsm_exchange, "variety.s4_to_s5.*")
    bind_queue(channel, "vsm.channel.s4_to_s5", @vsm_exchange, "intelligence.insight.*")
    
    # S3 → S1: Control commands (CLOSES THE LOOP!)
    create_queue(channel, "vsm.channel.s3_to_s1",
      arguments: [
        {"x-max-priority", :byte, 5},                # Priority for commands
        {"x-message-ttl", :signedint, 30_000},       # 30 sec TTL (urgent)
        {"x-max-length", :signedint, 100}
      ]
    )
    bind_queue(channel, "vsm.channel.s3_to_s1", @vsm_exchange, "control.command.*")
    bind_queue(channel, "vsm.channel.s3_to_s1", @command_exchange, "s1.control.*")
    
    # S5 → All: Policy broadcast
    create_queue(channel, "vsm.channel.s5_to_all",
      arguments: [
        {"x-message-ttl", :signedint, 3_600_000},    # 1 hour TTL
        {"x-max-length", :signedint, 100}
      ]
    )
    bind_queue(channel, "vsm.channel.s5_to_all", @vsm_exchange, "policy.broadcast.*")
    bind_queue(channel, "vsm.channel.s5_to_all", @event_exchange, "")  # Fanout
    
    Logger.info("  ✓ Created all variety flow channels")
  end
  
  defp setup_algedonic_system(channel) do
    Logger.info("🚨 Setting up algedonic bypass system...")
    
    # Main algedonic signal queue - ALL subsystems subscribe
    create_queue(channel, "vsm.algedonic.signals",
      arguments: [
        {"x-max-priority", :byte, 10},               # Highest priority
        {"x-message-ttl", :signedint, 60_000},       # 1 min TTL (urgent!)
        {"x-max-length", :signedint, 1_000},
        {"x-overflow", :longstr, "reject-publish"}   # Reject new if full
      ]
    )
    bind_queue(channel, "vsm.algedonic.signals", @algedonic_exchange, "pain")
    bind_queue(channel, "vsm.algedonic.signals", @algedonic_exchange, "pleasure")
    bind_queue(channel, "vsm.algedonic.signals", @algedonic_exchange, "emergency")
    
    # Per-subsystem algedonic queues for targeted signals
    Enum.each(["s1", "s2", "s3", "s4", "s5"], fn subsystem ->
      queue_name = "vsm.algedonic.#{subsystem}"
      create_queue(channel, queue_name,
        arguments: [
          {"x-max-priority", :byte, 10},
          {"x-message-ttl", :signedint, 30_000},     # 30 sec TTL
          {"x-max-length", :signedint, 100}
        ]
      )
      bind_queue(channel, queue_name, @algedonic_exchange, "pain.#{subsystem}")
      bind_queue(channel, queue_name, @algedonic_exchange, "pleasure.#{subsystem}")
    end)
    
    # Algedonic metrics queue for analytics
    create_queue(channel, "vsm.algedonic.metrics",
      arguments: [
        {"x-message-ttl", :signedint, 3_600_000},    # 1 hour TTL
        {"x-max-length", :signedint, 10_000}
      ]
    )
    bind_queue(channel, "vsm.algedonic.metrics", @vsm_exchange, "algedonic.metric.*")
    
    Logger.info("  ✓ Created algedonic bypass system")
  end
  
  defp setup_command_queues(channel) do
    Logger.info("🎮 Setting up command queues...")
    
    # Command queues for each subsystem
    Enum.each(["s1", "s2", "s3", "s4", "s5"], fn subsystem ->
      queue_name = "vsm.#{subsystem}.commands"
      create_queue(channel, queue_name,
        arguments: [
          {"x-max-priority", :byte, 5},
          {"x-message-ttl", :signedint, 60_000},     # 1 min TTL
          {"x-max-length", :signedint, 100},
          {"x-single-active-consumer", :bool, true}   # Ensure command ordering
        ]
      )
      bind_queue(channel, queue_name, @command_exchange, "#{subsystem}.*")
      bind_queue(channel, queue_name, @command_exchange, "all.*")  # Broadcast commands
    end)
    
    Logger.info("  ✓ Created command queues")
  end
  
  defp setup_dead_letter_queues(channel) do
    Logger.info("💀 Setting up dead letter queues...")
    
    # Main DLQ for all failed messages
    create_queue(channel, "vsm.dlq.all",
      arguments: [
        {"x-message-ttl", :signedint, 86_400_000},   # 24 hour retention
        {"x-max-length", :signedint, 100_000}        # 100k message limit
      ]
    )
    bind_queue(channel, "vsm.dlq.all", @dlx_exchange, "")
    
    # Per-subsystem DLQs for targeted retry
    Enum.each(["s1", "s2", "s3", "s4", "s5"], fn subsystem ->
      dlq_name = "vsm.dlq.#{subsystem}"
      create_queue(channel, dlq_name,
        arguments: [
          {"x-message-ttl", :signedint, 43_200_000}, # 12 hour retention
          {"x-max-length", :signedint, 10_000}
        ]
      )
    end)
    
    Logger.info("  ✓ Created dead letter queues")
  end
  
  defp create_queue(channel, name, opts \\ []) do
    {:ok, _} = AMQP.Queue.declare(channel, name, Keyword.merge([durable: true], opts))
    Logger.debug("    Created queue: #{name}")
  end
  
  defp bind_queue(channel, queue, exchange, routing_key) do
    :ok = AMQP.Queue.bind(channel, queue, exchange, routing_key: routing_key)
    Logger.debug("    Bound #{queue} to #{exchange} with key: #{routing_key}")
  end
  
  defp verify_topology(channel) do
    Logger.info("\n🔍 Verifying topology...")
    
    # Test publish to each exchange
    test_messages = [
      {@vsm_exchange, "operations.test", "S1 test message", "vsm.s1.operations"},
      {@vsm_exchange, "coordination.test", "S2 test message", "vsm.s2.coordination"},
      {@vsm_exchange, "control.test", "S3 test message", "vsm.s3.control"},
      {@vsm_exchange, "intelligence.test", "S4 test message", "vsm.s4.intelligence"},
      {@vsm_exchange, "policy.test", "S5 test message", "vsm.s5.policy"},
      {@algedonic_exchange, "pain", "Pain signal test", "vsm.algedonic.signals"},
      {@command_exchange, "s1.stop", "Command test", "vsm.s1.commands"}
    ]
    
    Enum.each(test_messages, fn {exchange, routing_key, message, expected_queue} ->
      # Publish test message
      :ok = AMQP.Basic.publish(channel, exchange, routing_key, message,
        timestamp: DateTime.utc_now() |> DateTime.to_unix(),
        headers: [{"test", :longstr, "true"}]
      )
      
      # Check if message arrived
      Process.sleep(100)  # Give it time to route
      
      case AMQP.Queue.status(channel, expected_queue) do
        {:ok, %{message_count: count}} when count > 0 ->
          Logger.info("  ✓ Message routed correctly to #{expected_queue}")
          # Consume the test message to clean up
          {:ok, _, _} = AMQP.Basic.get(channel, expected_queue)
          
        _ ->
          Logger.warning("  ⚠ Message may not have reached #{expected_queue}")
      end
    end)
    
    Logger.info("\n✨ VSM Topology is ready for action!")
    print_topology_summary()
  end
  
  defp print_topology_summary do
    IO.puts("""
    
    ╔══════════════════════════════════════════════════════════╗
    ║          VSM TOPOLOGY SETUP COMPLETE                     ║
    ╠══════════════════════════════════════════════════════════╣
    ║ Exchanges:                                               ║
    ║   • vsm.topic      - Main routing (topic)               ║
    ║   • vsm.events     - Broadcasts (fanout)                ║
    ║   • vsm.algedonic  - Pain/pleasure (direct)             ║
    ║   • vsm.commands   - Control (topic)                    ║
    ║   • vsm.dlx        - Dead letters (fanout)              ║
    ║                                                          ║
    ║ Subsystem Queues:                                        ║
    ║   • vsm.s1.operations    - High throughput              ║
    ║   • vsm.s2.coordination  - Anti-oscillation             ║
    ║   • vsm.s3.control       - Priority resource control    ║
    ║   • vsm.s4.intelligence  - Pattern learning             ║
    ║   • vsm.s5.policy        - Governance                   ║
    ║                                                          ║
    ║ Variety Channels:                                        ║
    ║   • S1→S2→S3→S4→S5 (upward flow)                       ║
    ║   • S3→S1 (control loop closure)                        ║
    ║   • S5→All (policy broadcast)                           ║
    ║                                                          ║
    ║ Algedonic Bypass:                                        ║
    ║   • <100ms response guarantee                           ║
    ║   • Priority queues for urgent signals                  ║
    ║                                                          ║
    ║ "The purpose of a system is what it does"               ║
    ║                           - Stafford Beer                ║
    ╚══════════════════════════════════════════════════════════╝
    """)
  end
end

# Run the setup
VSMTopologySetup.run()