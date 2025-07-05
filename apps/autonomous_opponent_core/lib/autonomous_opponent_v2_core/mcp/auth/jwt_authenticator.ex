defmodule AutonomousOpponentV2Core.MCP.Auth.JWTAuthenticator do
  @moduledoc """
  JWT authentication middleware for MCP Gateway.
  
  Features:
  - Token validation for channels and SSE
  - User-based rate limiting integration
  - Token expiration and refresh
  - Claims extraction and validation
  """
  
  use Joken.Config
  
  alias AutonomousOpponentV2Core.{EventBus, RateLimiter}
  alias AutonomousOpponentV2Core.MCP.Tracing
  
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
    |> add_claim("sub", nil, &validate_subject/1)
    |> add_claim("role", nil, &validate_role/1)
    |> add_claim("permissions", nil, &validate_permissions/1)
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
      "iat" => current_time(),
      "exp" => current_time() + exp
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
    
    Tracing.with_span "mcp.auth.validate_token", [kind: :internal] do
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
        case check_user_rate_limit(user_id, role) do
          :ok ->
            # Update socket assigns with user info
            socket = 
              socket
              |> Phoenix.Socket.assign(:user_id, user_id)
              |> Phoenix.Socket.assign(:role, role)
              |> Phoenix.Socket.assign(:permissions, permissions)
              |> Phoenix.Socket.assign(:authenticated, true)
            
            # Publish authentication event
            EventBus.publish(:mcp_auth, %{
              event: :channel_authenticated,
              user_id: user_id,
              transport: :websocket
            })
            
            {:ok, socket}
            
          {:error, :rate_limited} ->
            Logger.warning("Rate limit exceeded for user: #{user_id}")
            {:error, %{reason: "rate_limit_exceeded"}}
        end
        
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
        case check_user_rate_limit(user_id, role) do
          :ok ->
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
            
          {:error, :rate_limited} ->
            {:error, :rate_limited}
        end
        
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
    case validate_token(token) do
      {:ok, claims} ->
        exp = claims["exp"]
        now = current_time()
        
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
  
  defp validate_subject(sub) do
    case sub do
      nil -> {:error, "Subject is required"}
      "" -> {:error, "Subject cannot be empty"}
      _ -> :ok
    end
  end
  
  defp validate_role(role) do
    valid_roles = ["admin", "premium", "user", "guest"]
    
    if role in valid_roles do
      :ok
    else
      {:error, "Invalid role"}
    end
  end
  
  defp validate_permissions(permissions) when is_list(permissions) do
    valid_permissions = ["read", "write", "delete", "admin"]
    
    if Enum.all?(permissions, &(&1 in valid_permissions)) do
      :ok
    else
      {:error, "Invalid permissions"}
    end
  end
  defp validate_permissions(_), do: {:error, "Permissions must be a list"}
  
  defp get_secret do
    System.get_env("JWT_SECRET") || 
      Application.get_env(:autonomous_opponent_core, :jwt_secret) ||
      "development_secret_change_in_production"
  end
  
  defp current_time do
    System.system_time(:second)
  end
  
  defp check_user_rate_limit(user_id, role) do
    limit = get_user_rate_limit(role)
    bucket = "user:#{user_id}"
    
    case RateLimiter.check_rate(bucket, limit, 60_000) do  # per minute
      :ok -> :ok
      {:error, _} -> {:error, :rate_limited}
    end
  end
  
  defp translate_error(reason) do
    case reason do
      :token_expired -> :token_expired
      :invalid_token -> :invalid_token
      :signature_error -> :invalid_signature
      _ -> :validation_failed
    end
  end
end