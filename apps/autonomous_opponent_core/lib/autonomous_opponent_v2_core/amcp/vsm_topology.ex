# This module is conditionally compiled based on AMQP availability
if Code.ensure_loaded?(AMQP) do
  defmodule AutonomousOpponentV2Core.AMCP.VSMTopology do
    @moduledoc """
    Manages AMQP topology specifically for VSM (Viable System Model) communication.
    Creates exchanges, queues, and bindings for S1-S5 subsystems and algedonic channels.
    
    **Wisdom Preservation:** VSM requires structured communication channels that
    respect autonomy while enabling coordination. Topic exchanges enable filtered
    message routing based on subsystem concerns.
    """
    use GenServer
    require Logger
    
    alias AMQP.{Exchange, Queue, Basic}
    alias AutonomousOpponentV2Core.AMCP.ConnectionPool
    
    @vsm_exchange "vsm.events"
    @algedonic_exchange "vsm.algedonic"
    @command_exchange "vsm.commands"
    
    @subsystems [:s1, :s2, :s3, :s3_star, :s4, :s5]
    
    defmodule State do
      @moduledoc false
      defstruct [
        topology_declared: false,
        subsystem_queues: %{},
        algedonic_queue: nil,
        command_queues: %{}
      ]
    end
    
    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
    
    @impl true
    def init(_opts) do
      state = %State{}
      
      # Declare topology after a short delay to ensure ConnectionPool is ready
      Process.send_after(self(), :declare_topology, 2_000)
      
      {:ok, state}
    end
    
    @impl true
    def handle_info(:declare_topology, state) do
      case declare_vsm_topology() do
        {:ok, topology_info} ->
          Logger.info("VSM topology declared successfully")
          {:noreply, %{state | 
            topology_declared: true,
            subsystem_queues: topology_info.subsystem_queues,
            algedonic_queue: topology_info.algedonic_queue,
            command_queues: topology_info.command_queues
          }}
          
        {:error, reason} ->
          Logger.error("Failed to declare VSM topology: #{inspect(reason)}")
          # Retry after backoff
          Process.send_after(self(), :declare_topology, 5_000)
          {:noreply, state}
      end
    end
    
    @impl true
    def handle_call(:get_topology_info, _from, state) do
      info = %{
        declared: state.topology_declared,
        exchanges: [@vsm_exchange, @algedonic_exchange, @command_exchange],
        subsystem_queues: state.subsystem_queues,
        algedonic_queue: state.algedonic_queue,
        command_queues: state.command_queues
      }
      {:reply, info, state}
    end
    
    @impl true
    def handle_call({:publish_vsm_event, subsystem, event_type, payload}, _from, state) do
      result = publish_vsm_event(subsystem, event_type, payload)
      {:reply, result, state}
    end
    
    @impl true
    def handle_call({:publish_algedonic, severity, payload}, _from, state) do
      result = publish_algedonic_signal(severity, payload)
      {:reply, result, state}
    end
    
    # Private functions
    
    defp declare_vsm_topology do
      case ConnectionPool.get_channel() do
        {:ok, channel} ->
          try do
            # Declare main VSM topic exchange
            :ok = Exchange.declare(channel, @vsm_exchange, :topic, durable: true)
            Logger.debug("Declared VSM exchange: #{@vsm_exchange}")
            
            # Declare algedonic fanout exchange for pain/pleasure signals
            :ok = Exchange.declare(channel, @algedonic_exchange, :fanout, durable: true)
            Logger.debug("Declared algedonic exchange: #{@algedonic_exchange}")
            
            # Declare command topic exchange for directed commands
            :ok = Exchange.declare(channel, @command_exchange, :topic, durable: true)
            Logger.debug("Declared command exchange: #{@command_exchange}")
            
            # Create queues for each subsystem
            subsystem_queues = Enum.reduce(@subsystems, %{}, fn subsystem, acc ->
              queue_name = create_subsystem_queues(channel, subsystem)
              Map.put(acc, subsystem, queue_name)
            end)
            
            # Create algedonic queue (all subsystems receive algedonic signals)
            algedonic_queue = create_algedonic_queue(channel)
            
            # Create command queues
            command_queues = create_command_queues(channel)
            
            {:ok, %{
              subsystem_queues: subsystem_queues,
              algedonic_queue: algedonic_queue,
              command_queues: command_queues
            }}
          rescue
            error ->
              Logger.error("Error declaring VSM topology: #{inspect(error)}")
              {:error, error}
          end
          
        {:error, reason} ->
          {:error, reason}
      end
    end
    
    defp create_subsystem_queues(channel, subsystem) do
      queue_name = "vsm.#{subsystem}.events"
      dlq_name = "vsm.#{subsystem}.events.dlq"
      
      # Create dead letter queue
      {:ok, _} = Queue.declare(channel, dlq_name, durable: true)
      
      # Create main queue with DLQ settings
      {:ok, _} = Queue.declare(channel, queue_name,
        durable: true,
        arguments: [
          {"x-dead-letter-exchange", :longstr, ""},
          {"x-dead-letter-routing-key", :longstr, dlq_name},
          {"x-message-ttl", :long, 3_600_000},  # 1 hour TTL
          {"x-max-length", :long, 10_000}       # Max 10k messages
        ]
      )
      
      # Bind queue to VSM exchange with routing patterns
      # Each subsystem listens to its own events and broadcast events
      :ok = Queue.bind(channel, queue_name, @vsm_exchange, routing_key: "#{subsystem}.*")
      :ok = Queue.bind(channel, queue_name, @vsm_exchange, routing_key: "broadcast.*")
      
      # S3 and above also listen to coordination events
      if subsystem in [:s3, :s3_star, :s4, :s5] do
        :ok = Queue.bind(channel, queue_name, @vsm_exchange, routing_key: "coordination.*")
      end
      
      Logger.debug("Created queue #{queue_name} for subsystem #{subsystem}")
      
      queue_name
    end
    
    defp create_algedonic_queue(channel) do
      queue_name = "vsm.algedonic.signals"
      
      {:ok, _} = Queue.declare(channel, queue_name,
        durable: true,
        arguments: [
          {"x-max-priority", :byte, 10}  # Priority queue for algedonic signals
        ]
      )
      
      # All subsystems receive algedonic signals
      :ok = Queue.bind(channel, queue_name, @algedonic_exchange)
      
      Logger.debug("Created algedonic queue: #{queue_name}")
      
      queue_name
    end
    
    defp create_command_queues(channel) do
      Enum.reduce(@subsystems, %{}, fn subsystem, acc ->
        queue_name = "vsm.#{subsystem}.commands"
        
        {:ok, _} = Queue.declare(channel, queue_name,
          durable: true,
          arguments: [
            {"x-max-priority", :byte, 5}  # Commands have priority levels
          ]
        )
        
        # Bind to command exchange with subsystem-specific routing
        :ok = Queue.bind(channel, queue_name, @command_exchange, routing_key: "#{subsystem}.*")
        
        Logger.debug("Created command queue #{queue_name}")
        
        Map.put(acc, subsystem, queue_name)
      end)
    end
    
    defp publish_vsm_event(subsystem, event_type, payload) do
      case ConnectionPool.get_channel() do
        {:ok, channel} ->
          routing_key = "#{subsystem}.#{event_type}"
          message = Jason.encode!(%{
            subsystem: subsystem,
            event_type: event_type,
            payload: payload,
            timestamp: DateTime.utc_now()
          })
          
          Basic.publish(channel, @vsm_exchange, routing_key, message,
            persistent: true,
            content_type: "application/json"
          )
          
          Logger.debug("Published VSM event to #{routing_key}")
          :ok
          
        {:error, reason} ->
          {:error, reason}
      end
    end
    
    defp publish_algedonic_signal(severity, payload) do
      case ConnectionPool.get_channel() do
        {:ok, channel} ->
          priority = case severity do
            :critical -> 10
            :high -> 8
            :medium -> 5
            :low -> 2
            _ -> 1
          end
          
          message = Jason.encode!(%{
            severity: severity,
            payload: payload,
            timestamp: DateTime.utc_now()
          })
          
          Basic.publish(channel, @algedonic_exchange, "", message,
            persistent: true,
            priority: priority,
            content_type: "application/json"
          )
          
          Logger.info("Published algedonic signal with severity: #{severity}")
          :ok
          
        {:error, reason} ->
          {:error, reason}
      end
    end
    
    # Public API
    
    @doc """
    Gets information about the declared VSM topology.
    """
    def get_topology_info do
      GenServer.call(__MODULE__, :get_topology_info)
    end
    
    @doc """
    Publishes a VSM event to the appropriate subsystem queues.
    """
    def publish_event(subsystem, event_type, payload) do
      GenServer.call(__MODULE__, {:publish_vsm_event, subsystem, event_type, payload})
    end
    
    @doc """
    Publishes an algedonic signal to all subsystems.
    """
    def publish_algedonic(severity, payload) when severity in [:critical, :high, :medium, :low] do
      GenServer.call(__MODULE__, {:publish_algedonic, severity, payload})
    end
  end
else
  # Stub implementation when AMQP is not available
  defmodule AutonomousOpponentV2Core.AMCP.VSMTopology do
    @moduledoc """
    Stub implementation of VSM Topology when AMQP is not available.
    Routes VSM events through EventBus instead.
    """
    use GenServer
    require Logger
    
    alias AutonomousOpponentV2Core.EventBus
    
    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
    
    @impl true
    def init(_opts) do
      Logger.warning("VSM Topology running in stub mode - using EventBus for message routing")
      {:ok, %{}}
    end
    
    @impl true
    def handle_call(:get_topology_info, _from, state) do
      info = %{
        declared: false,
        mode: :eventbus_only,
        error: :amqp_not_available
      }
      {:reply, info, state}
    end
    
    @impl true
    def handle_call({:publish_vsm_event, subsystem, event_type, payload}, _from, state) do
      # Route through EventBus instead
      EventBus.publish(:"vsm_#{subsystem}_#{event_type}", payload)
      {:reply, :ok, state}
    end
    
    @impl true
    def handle_call({:publish_algedonic, severity, payload}, _from, state) do
      # Route algedonic signals through EventBus
      EventBus.publish(:algedonic_signal, %{severity: severity, payload: payload})
      {:reply, :ok, state}
    end
    
    def get_topology_info do
      GenServer.call(__MODULE__, :get_topology_info)
    end
    
    def publish_event(subsystem, event_type, payload) do
      GenServer.call(__MODULE__, {:publish_vsm_event, subsystem, event_type, payload})
    end
    
    def publish_algedonic(severity, payload) do
      GenServer.call(__MODULE__, {:publish_algedonic, severity, payload})
    end
  end
end