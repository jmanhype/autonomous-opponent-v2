defmodule AutonomousOpponentV2Core.MCPGateway.RouterTest do
  use ExUnit.Case, async: true
  
  alias AutonomousOpponentV2Core.MCPGateway.Router
  alias AutonomousOpponentV2Core.Core.CircuitBreaker
  
  setup do
    {:ok, router} = start_supervised({Router, name: :test_router, hash_ring_size: 128})
    %{router: router}
  end
  
  describe "register_route/4" do
    test "successfully registers a route", %{router: _router} do
      handler = TestHandler
      pattern = "/test/*"
      
      assert {:ok, route_id} = Router.register_route(:test_router, pattern, handler)
      assert is_binary(route_id)
    end
    
    test "creates circuit breaker for route", %{router: _router} do
      handler = TestHandler
      pattern = "/test/circuit"
      
      {:ok, route_id} = Router.register_route(:test_router, pattern, handler)
      
      # Circuit breaker should be started
      assert Process.whereis(:"circuit_breaker_route_#{route_id}") != nil
    end
  end
  
  describe "route/2" do
    test "routes to matching pattern", %{router: _router} do
      # Register a test route
      Router.register_route(:test_router, "/api/test", TestHandler)
      
      request = %{
        path: "/api/test",
        transport_type: :http_sse,
        user_id: "user123"
      }
      
      # Since we don't have backends configured, this will fail
      assert {:error, :no_backends_available} = Router.route(:test_router, request)
    end
    
    test "returns not found for non-matching route", %{router: _router} do
      request = %{
        path: "/unknown/path",
        transport_type: :websocket
      }
      
      assert {:error, :not_found} = Router.route(:test_router, request)
    end
    
    test "respects transport type filtering", %{router: _router} do
      # Register route for websocket only
      Router.register_route(:test_router, "/ws-only", TestHandler, 
        transport_types: [:websocket]
      )
      
      # Try with HTTP+SSE
      request = %{
        path: "/ws-only",
        transport_type: :http_sse
      }
      
      assert {:error, :not_found} = Router.route(:test_router, request)
    end
  end
  
  describe "update_backends/2" do
    test "updates backend list", %{router: _router} do
      backends = ["backend1:8080", "backend2:8080", "backend3:8080"]
      
      assert :ok = Router.update_backends(:test_router, backends)
      
      status = Router.status(:test_router)
      assert status.backends == 3
    end
    
    test "handles empty backend list", %{router: _router} do
      assert :ok = Router.update_backends(:test_router, [])
      
      status = Router.status(:test_router)
      assert status.backends == 0
    end
  end
  
  describe "status/1" do
    test "returns router status", %{router: _router} do
      status = Router.status(:test_router)
      
      assert %{
        total_routes: _,
        active_routes: _,
        backends: 0,
        hash_ring_load: 0.0,
        stats: stats,
        routes: routes
      } = status
      
      assert is_map(stats)
      assert is_list(routes)
    end
  end
  
  describe "consistent hashing" do
    test "same routing key routes to same backend", %{router: _router} do
      # Set up backends
      backends = ["backend1", "backend2", "backend3"]
      Router.update_backends(:test_router, backends)
      
      # Register a route
      Router.register_route(:test_router, "/api/*", TestHandler)
      
      # Multiple requests with same user should route to same backend
      request1 = %{
        path: "/api/test",
        transport_type: :http_sse,
        user_id: "consistent-user"
      }
      
      request2 = %{
        path: "/api/test",
        transport_type: :http_sse,
        user_id: "consistent-user"
      }
      
      # Both should fail with same error (no actual connection pool)
      result1 = Router.route(:test_router, request1)
      result2 = Router.route(:test_router, request2)
      
      assert result1 == result2
    end
  end
  
  describe "wildcard patterns" do
    test "matches wildcard patterns correctly", %{router: _router} do
      Router.register_route(:test_router, "/api/v1/*", TestHandler)
      
      # Should match
      for path <- ["/api/v1/users", "/api/v1/posts/123", "/api/v1/"] do
        request = %{path: path, transport_type: :http_sse}
        result = Router.route(:test_router, request)
        # Will fail due to no backends, but shouldn't be :not_found
        assert result != {:error, :not_found}
      end
      
      # Should not match
      for path <- ["/api/v2/users", "/api", "/other"] do
        request = %{path: path, transport_type: :http_sse}
        assert {:error, :not_found} = Router.route(:test_router, request)
      end
    end
  end
end

# Test handler module
defmodule TestHandler do
  def handle_request(_request, _connection, _backend) do
    {:ok, %{status: "test"}}
  end
end