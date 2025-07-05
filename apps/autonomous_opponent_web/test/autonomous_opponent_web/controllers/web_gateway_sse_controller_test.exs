defmodule AutonomousOpponentV2Web.WebGatewaySSEControllerTest do
  @moduledoc """
  Tests for the Web Gateway SSE controller endpoints.
  """
  
  use AutonomousOpponentV2Web.ConnCase
  
  alias AutonomousOpponentV2Core.WebGateway.Transport.HTTPSSE
  
  describe "GET /web-gateway/sse" do
    test "establishes SSE connection with proper headers", %{conn: conn} do
      # Start mock process to handle SSE registration
      test_pid = self()
      
      # Temporarily replace HTTPSSE process
      Process.register(test_pid, HTTPSSE)
      
      # Make request in a task
      task = Task.async(fn ->
        get(conn, "/web-gateway/sse")
      end)
      
      # Should receive registration request
      assert_receive {:"$gen_call", from, {:register, pid, client_id, params}}
      
      # Respond with success
      GenServer.reply(from, {:ok, "test_conn_id"})
      
      # Let the connection establish
      :timer.sleep(50)
      
      # Clean up
      Process.unregister(HTTPSSE)
      Task.shutdown(task, :brutal_kill)
    end
    
    test "sends welcome event on connection", %{conn: conn} do
      # Mock HTTPSSE
      test_pid = self()
      spawn(fn ->
        Process.register(self(), HTTPSSE)
        
        receive do
          {:"$gen_call", from, {:register, _pid, _client_id, _params}} ->
            GenServer.reply(from, {:ok, "test_conn_id"})
        end
        
        # Keep process alive
        :timer.sleep(100)
        Process.unregister(HTTPSSE)
      end)
      
      :timer.sleep(10)
      
      # Connect
      conn = get(conn, "/web-gateway/sse")
      
      # Check headers
      assert get_resp_header(conn, "content-type") == ["text/event-stream"]
      assert get_resp_header(conn, "cache-control") == ["no-cache"]
      assert get_resp_header(conn, "connection") == ["keep-alive"]
      
      # Check for chunked response
      assert conn.status == 200
      assert conn.state == :chunked
    end
    
    test "accepts client_id parameter", %{conn: conn} do
      test_pid = self()
      client_id = "test_client_123"
      
      spawn(fn ->
        Process.register(self(), HTTPSSE)
        
        receive do
          {:"$gen_call", from, {:register, _pid, received_client_id, params}} ->
            send(test_pid, {:client_id_received, received_client_id})
            GenServer.reply(from, {:ok, "test_conn_id"})
        end
        
        :timer.sleep(100)
        Process.unregister(HTTPSSE)
      end)
      
      :timer.sleep(10)
      
      # Connect with client_id
      task = Task.async(fn ->
        get(conn, "/web-gateway/sse", %{client_id: client_id})
      end)
      
      # Should use provided client_id
      assert_receive {:client_id_received, ^client_id}
      
      Task.shutdown(task, :brutal_kill)
    end
    
    test "generates client_id if not provided", %{conn: conn} do
      test_pid = self()
      
      spawn(fn ->
        Process.register(self(), HTTPSSE)
        
        receive do
          {:"$gen_call", from, {:register, _pid, client_id, _params}} ->
            send(test_pid, {:generated_client_id, client_id})
            GenServer.reply(from, {:ok, "test_conn_id"})
        end
        
        :timer.sleep(100)
        Process.unregister(HTTPSSE)
      end)
      
      :timer.sleep(10)
      
      # Connect without client_id
      task = Task.async(fn ->
        get(conn, "/web-gateway/sse")
      end)
      
      # Should generate UUID
      assert_receive {:generated_client_id, generated_id}
      assert String.match?(generated_id, ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
      
      Task.shutdown(task, :brutal_kill)
    end
  end
end