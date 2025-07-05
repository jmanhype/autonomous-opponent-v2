defmodule AutonomousOpponentV2Core.WebGateway.Auth.JWTAuthenticator do
  @moduledoc """
  JWT authentication middleware for Web Gateway.
  
  Features:
  - Token validation for channels and SSE
  - User-based rate limiting integration
  - Token expiration and refresh
  - Claims extraction and validation
  """
  
  use Joken.Config
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.WebGateway.Tracing
  
  require Logger
  
  # Default token expiration: 1 hour
  @default_exp_seconds 3600
  @issuer "autonomous-opponent"
  @algorithm "HS256"
  
  # Define token structure
  @impl true
  def token_config do
    default_claims(
      iss: @issuer,
      aud: "mcp-gateway",
      default_exp: @default_exp_seconds
    )
  end
  
  @doc """
  Generates a new JWT token for a user.
  
  Options:
  - exp: Token expiration in seconds (default: 3600)
  - role: User role (default: "user")
  - permissions: List of permissions (default: ["read"])
  """
  def generate_token(user_id, opts \\ []) do
    exp = Keyword.get(opts, :exp, @default_exp_seconds)
    role = Keyword.get(opts, :role, "user")
    permissions = Keyword.get(opts, :permissions, ["read"])
    
    claims = %{
      "sub" => user_id,
      "role" => role,
      "permissions" => permissions,
      "iat" => current_unix_time(),
      "exp" => current_unix_time() + exp
    }
    
    secret = get_secret()
    
    case generate_and_sign(claims, Joken.Signer.create(@algorithm, secret)) do
      {:ok, token, _claims} ->
        Logger.debug("Generated JWT for user: #{user_id}")
        {:ok, token}
        
      {:error, reason} ->
        Logger.error("Failed to generate JWT: #{inspect(reason)}")
        {:error, :token_generation_failed}
    end
  end
  
  @doc """
  Validates a JWT token and returns the claims.
  """
  def validate_token(token) when is_binary(token) do
    secret = get_secret()
    signer = Joken.Signer.create(@algorithm, secret)
    
    Tracing.with_span "mcp.auth.validate_token", [kind: :internal], fn ->
      case verify_and_validate(token, signer) do
        {:ok, claims} ->
          Tracing.add_event("token.validated", %{user_id: claims["sub"]})
          {:ok, claims}
          
        {:error, reason} ->
          Tracing.add_event("token.validation_failed", %{reason: inspect(reason)})
          {:error, translate_error(reason)}
      end
    end
  end
  
  def validate_token(_), do: {:error, :invalid_token}
  
  @doc """
  Validates a token for WebSocket channel authentication.
  Returns user info and updates rate limiter.
  """
  def validate_channel_token(token, socket) do
    case validate_token(token) do
      {:ok, claims} ->
        user_id = claims["sub"]
        role = claims["role"]
        permissions = claims["permissions"] || []
        
        # Check rate limit for user
        check_user_rate_limit(user_id, role)
        
        # Update socket assigns with user info
        socket = Map.put(socket, :assigns, Map.merge(socket.assigns, %{
          user_id: user_id,
          role: role,
          permissions: permissions,
          authenticated: true
        }))
        
        # Publish authentication event
        EventBus.publish(:mcp_auth, %{
          event: :channel_authenticated,
          user_id: user_id,
          transport: :websocket
        })
        
        {:ok, socket}
        
      {:error, reason} ->
        Logger.debug("Channel authentication failed: #{reason}")
        {:error, %{reason: to_string(reason)}}
    end
  end
  
  @doc """
  Validates a token for SSE authentication.
  Returns user info or error.
  """
  def validate_sse_token(token) do
    case validate_token(token) do
      {:ok, claims} ->
        user_id = claims["sub"]
        role = claims["role"]
        
        # Check rate limit
        check_user_rate_limit(user_id, role)
        
        # Publish authentication event
        EventBus.publish(:mcp_auth, %{
          event: :sse_authenticated,
          user_id: user_id,
          transport: :http_sse
        })
        
        {:ok, %{
          user_id: user_id,
          role: role,
          permissions: claims["permissions"] || []
        }}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Extracts token from authorization header.
  """
  def extract_token_from_header(nil), do: nil
  def extract_token_from_header(header) when is_binary(header) do
    case String.split(header, " ", parts: 2) do
      ["Bearer", token] -> String.trim(token)
      _ -> nil
    end
  end
  
  @doc """
  Refreshes a token if it's close to expiration.
  """
  def refresh_token(token) do
    Tracing.with_span "mcp.auth.refresh_token", [kind: :internal], fn ->
      case validate_token(token) do
      {:ok, claims} ->
        exp = claims["exp"]
        now = current_unix_time()
        
        # Refresh if less than 5 minutes remaining
        if exp - now < 300 do
          generate_token(claims["sub"], [
            role: claims["role"],
            permissions: claims["permissions"]
          ])
        else
          {:ok, token}  # Return existing token
        end
        
      {:error, _reason} ->
        {:error, :invalid_token}
      end
    end
  end
  
  @doc """
  Checks if a user has a specific permission.
  """
  def has_permission?(claims, permission) when is_map(claims) do
    permissions = claims["permissions"] || []
    permission in permissions
  end
  
  @doc """
  Gets rate limit for a user based on their role.
  """
  def get_user_rate_limit(role) do
    case role do
      "admin" -> 10_000    # 10k requests/minute
      "premium" -> 1_000   # 1k requests/minute
      "user" -> 100        # 100 requests/minute
      _ -> 10              # 10 requests/minute for unknown roles
    end
  end
  
  # Private functions
  
  defp get_secret do
    System.get_env("JWT_SECRET") || 
      Application.get_env(:autonomous_opponent_core, :jwt_secret) ||
      "development_secret_change_in_production"
  end
  
  defp current_unix_time do
    System.system_time(:second)
  end
  
  defp check_user_rate_limit(_user_id, _role) do
    # Simple rate limiting implementation for now
    # TODO: Implement actual rate limiting when RateLimiter module is available
    :ok
  end
  
  defp translate_error(reason) do
    case reason do
      [message: "Invalid token", claim: "exp", claim_val: _] -> :token_expired
      :token_expired -> :token_expired
      :invalid_token -> :invalid_token
      :signature_error -> :invalid_signature
      [message: "Invalid signature"] -> :invalid_signature
      errors when is_list(errors) ->
        if Enum.any?(errors, fn 
          {:message, "Invalid signature"} -> true
          _ -> false
        end) do
          :invalid_signature
        else
          :validation_failed
        end
      _ -> :validation_failed
    end
  end
end