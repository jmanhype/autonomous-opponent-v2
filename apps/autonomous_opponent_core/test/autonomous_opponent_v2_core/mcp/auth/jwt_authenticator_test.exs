defmodule AutonomousOpponentV2Core.MCP.Auth.JWTAuthenticatorTest do
  use ExUnit.Case, async: true
  
  alias AutonomousOpponentV2Core.MCP.Auth.JWTAuthenticator
  
  @user_id "test_user_123"
  @test_secret "test_secret_for_jwt_testing_only"
  
  setup do
    # Set test secret
    original_env = Application.get_env(:autonomous_opponent_core, :jwt_secret)
    Application.put_env(:autonomous_opponent_core, :jwt_secret, @test_secret)
    
    on_exit(fn ->
      if original_env do
        Application.put_env(:autonomous_opponent_core, :jwt_secret, original_env)
      else
        Application.delete_env(:autonomous_opponent_core, :jwt_secret)
      end
    end)
    
    :ok
  end
  
  describe "generate_token/2" do
    test "generates valid JWT token" do
      assert {:ok, token} = JWTAuthenticator.generate_token(@user_id)
      assert is_binary(token)
      assert String.split(token, ".") |> length() == 3  # JWT has 3 parts
    end
    
    test "generates token with custom role and permissions" do
      opts = [role: "admin", permissions: ["read", "write", "admin"]]
      assert {:ok, token} = JWTAuthenticator.generate_token(@user_id, opts)
      
      # Validate the generated token
      assert {:ok, claims} = JWTAuthenticator.validate_token(token)
      assert claims["sub"] == @user_id
      assert claims["role"] == "admin"
      assert claims["permissions"] == ["read", "write", "admin"]
    end
    
    test "generates token with custom expiration" do
      opts = [exp: 7200]  # 2 hours
      assert {:ok, token} = JWTAuthenticator.generate_token(@user_id, opts)
      
      assert {:ok, claims} = JWTAuthenticator.validate_token(token)
      assert claims["exp"] - claims["iat"] == 7200
    end
  end
  
  describe "validate_token/1" do
    test "validates a valid token" do
      {:ok, token} = JWTAuthenticator.generate_token(@user_id)
      
      assert {:ok, claims} = JWTAuthenticator.validate_token(token)
      assert claims["sub"] == @user_id
      assert claims["iss"] == "autonomous-opponent"
      assert claims["aud"] == "mcp-gateway"
    end
    
    test "rejects invalid token format" do
      assert {:error, :invalid_token} = JWTAuthenticator.validate_token("not.a.token")
      assert {:error, :invalid_token} = JWTAuthenticator.validate_token("")
      assert {:error, :invalid_token} = JWTAuthenticator.validate_token(nil)
    end
    
    test "rejects expired token" do
      # Generate token that expires immediately
      {:ok, token} = JWTAuthenticator.generate_token(@user_id, exp: -1)
      
      assert {:error, :token_expired} = JWTAuthenticator.validate_token(token)
    end
    
    test "rejects token with invalid signature" do
      {:ok, token} = JWTAuthenticator.generate_token(@user_id)
      
      # Tamper with the token
      [header, payload, _sig] = String.split(token, ".")
      tampered_token = "#{header}.#{payload}.invalid_signature"
      
      assert {:error, :invalid_signature} = JWTAuthenticator.validate_token(tampered_token)
    end
  end
  
  describe "validate_channel_token/2" do
    test "validates token and assigns user info to socket" do
      {:ok, token} = JWTAuthenticator.generate_token(@user_id, role: "premium")
      
      # Mock socket
      socket = %Phoenix.Socket{assigns: %{}}
      
      assert {:ok, updated_socket} = JWTAuthenticator.validate_channel_token(token, socket)
      assert updated_socket.assigns.user_id == @user_id
      assert updated_socket.assigns.role == "premium"
      assert updated_socket.assigns.authenticated == true
    end
    
    test "rejects invalid token for channel" do
      socket = %Phoenix.Socket{assigns: %{}}
      
      assert {:error, %{reason: "invalid_token"}} = 
        JWTAuthenticator.validate_channel_token("invalid", socket)
    end
  end
  
  describe "validate_sse_token/1" do
    test "validates token and returns user info" do
      {:ok, token} = JWTAuthenticator.generate_token(@user_id, [
        role: "user",
        permissions: ["read"]
      ])
      
      assert {:ok, user_info} = JWTAuthenticator.validate_sse_token(token)
      assert user_info.user_id == @user_id
      assert user_info.role == "user"
      assert user_info.permissions == ["read"]
    end
    
    test "rejects invalid token for SSE" do
      assert {:error, :invalid_token} = JWTAuthenticator.validate_sse_token("invalid")
    end
  end
  
  describe "extract_token_from_header/1" do
    test "extracts token from Bearer header" do
      header = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test.signature"
      
      assert "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test.signature" ==
        JWTAuthenticator.extract_token_from_header(header)
    end
    
    test "returns nil for invalid header format" do
      assert nil == JWTAuthenticator.extract_token_from_header("Basic dXNlcjpwYXNz")
      assert nil == JWTAuthenticator.extract_token_from_header("InvalidHeader")
      assert nil == JWTAuthenticator.extract_token_from_header(nil)
    end
  end
  
  describe "refresh_token/1" do
    test "refreshes token close to expiration" do
      # Generate token with 4 minutes left (less than 5 minute threshold)
      {:ok, original_token} = JWTAuthenticator.generate_token(@user_id, exp: 240)
      
      assert {:ok, new_token} = JWTAuthenticator.refresh_token(original_token)
      assert new_token != original_token
      
      # Verify new token has full expiration
      {:ok, claims} = JWTAuthenticator.validate_token(new_token)
      assert claims["exp"] - claims["iat"] >= 3600  # Default 1 hour
    end
    
    test "returns same token if not close to expiration" do
      {:ok, token} = JWTAuthenticator.generate_token(@user_id)
      
      assert {:ok, ^token} = JWTAuthenticator.refresh_token(token)
    end
    
    test "returns error for invalid token" do
      assert {:error, :invalid_token} = JWTAuthenticator.refresh_token("invalid")
    end
  end
  
  describe "has_permission?/2" do
    test "checks if user has specific permission" do
      claims = %{"permissions" => ["read", "write"]}
      
      assert JWTAuthenticator.has_permission?(claims, "read")
      assert JWTAuthenticator.has_permission?(claims, "write")
      refute JWTAuthenticator.has_permission?(claims, "admin")
    end
    
    test "handles missing permissions gracefully" do
      claims = %{}
      
      refute JWTAuthenticator.has_permission?(claims, "read")
    end
  end
  
  describe "get_user_rate_limit/1" do
    test "returns correct rate limits by role" do
      assert 10_000 == JWTAuthenticator.get_user_rate_limit("admin")
      assert 1_000 == JWTAuthenticator.get_user_rate_limit("premium")
      assert 100 == JWTAuthenticator.get_user_rate_limit("user")
      assert 10 == JWTAuthenticator.get_user_rate_limit("unknown")
    end
  end
end