#!/usr/bin/env elixir

# Demo script for EPMD-based CRDT Node Discovery (Issue #89)
# This demonstrates automatic peer discovery using Erlang's EPMD

defmodule EPMDDiscoveryDemo do
  @moduledoc """
  Interactive demo of EPMD-based CRDT peer discovery.
  
  Usage:
    # Terminal 1 - Start first node
    NODE_NAME=crdt1 mix run scripts/demo_epmd_discovery.exs
    
    # Terminal 2 - Start second node  
    NODE_NAME=crdt2 mix run scripts/demo_epmd_discovery.exs
    
    # Terminal 3 - Start third node
    NODE_NAME=crdt3 mix run scripts/demo_epmd_discovery.exs
    
  The nodes will automatically discover each other within 10 seconds!
  """
  
  require Logger
  
  def run do
    # Get node name from environment or generate one
    node_name = case System.get_env("NODE_NAME") do
      nil -> "crdt_demo_#{:rand.uniform(9999)}"
      name -> name
    end
    
    # Start distributed Erlang
    case Node.start(:"#{node_name}@127.0.0.1") do
      {:ok, _} -> 
        Logger.info("🚀 Started node: #{node()}")
      {:error, {:already_started, _}} ->
        Logger.info("📡 Node already running: #{node()}")
      error ->
        Logger.error("Failed to start node: #{inspect(error)}")
        System.halt(1)
    end
    
    # Set cookie for inter-node communication
    Node.set_cookie(:epmd_demo_cookie)
    
    # Start the application
    Application.ensure_all_started(:autonomous_opponent_core)
    
    # Give the system a moment to initialize
    Process.sleep(1000)
    
    # Start monitoring
    spawn(fn -> monitor_loop() end)
    
    # Interactive menu
    show_menu()
  end
  
  defp monitor_loop do
    Process.sleep(5000)
    
    IO.puts("\n📊 CURRENT STATUS:")
    IO.puts("═══════════════════════════════════════════")
    
    # Show EPMD discovery status
    case GenServer.whereis(AutonomousOpponentV2Core.AMCP.Memory.EPMDDiscovery) do
      nil ->
        IO.puts("❌ EPMD Discovery not running")
      pid when is_pid(pid) ->
        status = AutonomousOpponentV2Core.AMCP.Memory.EPMDDiscovery.status()
        IO.puts("✅ EPMD Discovery: #{if status.discovery_enabled, do: "ACTIVE", else: "DISABLED"}")
        IO.puts("🔍 Known nodes: #{inspect(status.known_nodes)}")
        IO.puts("⏰ Last discovery: #{format_time(status.last_discovery)}")
        IO.puts("📅 Next discovery: #{status.next_discovery}")
    end
    
    # Show CRDT Store status
    case GenServer.whereis(AutonomousOpponentV2Core.AMCP.Memory.CRDTStore) do
      nil ->
        IO.puts("❌ CRDT Store not running")
      pid when is_pid(pid) ->
        stats = AutonomousOpponentV2Core.AMCP.Memory.CRDTStore.get_stats()
        IO.puts("\n📦 CRDT Store:")
        IO.puts("   Node ID: #{stats.node_id}")
        IO.puts("   CRDT count: #{stats.crdt_count}")
        IO.puts("   Sync peers: #{stats.peer_count}")
        IO.puts("   Vector clock: #{inspect(stats.vector_clock)}")
    end
    
    # Show visible nodes
    IO.puts("\n🌐 Erlang cluster:")
    IO.puts("   Current node: #{node()}")
    IO.puts("   Visible nodes: #{inspect(Node.list())}")
    
    IO.puts("═══════════════════════════════════════════\n")
    
    monitor_loop()
  end
  
  defp show_menu do
    IO.puts("\n🎮 EPMD DISCOVERY DEMO MENU")
    IO.puts("═══════════════════════════════════════════")
    IO.puts("1. Trigger manual discovery")
    IO.puts("2. Create test CRDT")
    IO.puts("3. Show CRDT peers")
    IO.puts("4. Force sync with peers")
    IO.puts("5. Toggle discovery on/off")
    IO.puts("6. Show EPMD names (local)")
    IO.puts("q. Quit")
    IO.puts("═══════════════════════════════════════════")
    IO.write("Choose option: ")
    
    case IO.gets("") |> String.trim() do
      "1" ->
        trigger_discovery()
        show_menu()
        
      "2" ->
        create_test_crdt()
        show_menu()
        
      "3" ->
        show_peers()
        show_menu()
        
      "4" ->
        force_sync()
        show_menu()
        
      "5" ->
        toggle_discovery()
        show_menu()
        
      "6" ->
        show_epmd_names()
        show_menu()
        
      "q" ->
        IO.puts("👋 Goodbye!")
        System.halt(0)
        
      _ ->
        IO.puts("❓ Unknown option")
        show_menu()
    end
  end
  
  defp trigger_discovery do
    IO.puts("\n🔍 Triggering manual peer discovery...")
    AutonomousOpponentV2Core.AMCP.Memory.CRDTStore.discover_peers()
    IO.puts("✅ Discovery initiated - check status in a few seconds")
  end
  
  defp create_test_crdt do
    crdt_id = "test_crdt_#{System.unique_integer([:positive])}"
    IO.puts("\n📦 Creating CRDT: #{crdt_id}")
    
    case AutonomousOpponentV2Core.AMCP.Memory.CRDTStore.create_crdt(crdt_id, :g_set) do
      {:ok, _} ->
        IO.puts("✅ CRDT created successfully")
        
        # Add some test data
        AutonomousOpponentV2Core.AMCP.Memory.CRDTStore.update_crdt(
          crdt_id, 
          :add, 
          "test_value_#{:rand.uniform(100)}"
        )
        
      {:error, reason} ->
        IO.puts("❌ Failed to create CRDT: #{inspect(reason)}")
    end
  end
  
  defp show_peers do
    stats = AutonomousOpponentV2Core.AMCP.Memory.CRDTStore.get_stats()
    peers = AutonomousOpponentV2Core.AMCP.Memory.CRDTStore.get_cluster_members()
    
    IO.puts("\n👥 CRDT Sync Peers:")
    IO.puts("   Total peers: #{stats.peer_count}")
    
    if length(peers) > 0 do
      Enum.each(peers, fn peer ->
        IO.puts("   • #{peer}")
      end)
    else
      IO.puts("   (no peers connected)")
    end
  end
  
  defp force_sync do
    IO.puts("\n🔄 Forcing sync with all peers...")
    AutonomousOpponentV2Core.AMCP.Memory.CRDTStore.sync_with_peers()
    IO.puts("✅ Sync initiated")
  end
  
  defp toggle_discovery do
    status = AutonomousOpponentV2Core.AMCP.Memory.EPMDDiscovery.status()
    new_state = not status.discovery_enabled
    
    IO.puts("\n🔧 Toggling discovery: #{status.discovery_enabled} → #{new_state}")
    AutonomousOpponentV2Core.AMCP.Memory.EPMDDiscovery.set_enabled(new_state)
    IO.puts("✅ Discovery is now #{if new_state, do: "ENABLED", else: "DISABLED"}")
  end
  
  defp show_epmd_names do
    IO.puts("\n📡 EPMD registered names on localhost:")
    
    case :net_adm.names() do
      {:ok, names} ->
        if length(names) > 0 do
          Enum.each(names, fn {name, port} ->
            IO.puts("   • #{name} (port: #{port})")
          end)
        else
          IO.puts("   (no names registered)")
        end
        
      {:error, reason} ->
        IO.puts("   ❌ Error: #{inspect(reason)}")
    end
  end
  
  defp format_time(nil), do: "never"
  defp format_time(timestamp) when is_integer(timestamp) do
    seconds_ago = System.system_time(:second) - timestamp
    "#{seconds_ago}s ago"
  end
end

# Run the demo
EPMDDiscoveryDemo.run()