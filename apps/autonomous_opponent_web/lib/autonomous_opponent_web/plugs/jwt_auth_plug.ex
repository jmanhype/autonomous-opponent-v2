defmodule AutonomousOpponentV2Web.Plugs.JWTAuthPlug do
  @moduledoc """
  Plug for JWT authentication in HTTP requests.
  
  Validates JWT tokens from Authorization header and assigns user info to conn.
  """
  
  import Plug.Conn
  alias AutonomousOpponentV2Core.MCP.Auth.JWTAuthenticator
  
  def init(opts), do: opts
  
  def call(conn, opts) do
    required = Keyword.get(opts, :required, true)
    
    with {:ok, token} <- extract_token(conn),
         {:ok, user_info} <- JWTAuthenticator.validate_sse_token(token) do
      conn
      |> assign(:current_user, user_info)
      |> assign(:authenticated, true)
    else
      {:error, :no_token} when not required ->
        # Optional auth, continue without user
        conn
        |> assign(:current_user, nil)
        |> assign(:authenticated, false)
        
      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{
          error: "unauthorized",
          reason: format_error(reason)
        }))
        |> halt()
    end
  end
  
  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      [header | _] ->
        case JWTAuthenticator.extract_token_from_header(header) do
          nil -> {:error, :invalid_header}
          token -> {:ok, token}
        end
        
      [] ->
        # Try query params as fallback (for SSE)
        case conn.params["token"] do
          nil -> {:error, :no_token}
          token -> {:ok, token}
        end
    end
  end
  
  defp format_error(reason) do
    case reason do
      :token_expired -> "Token has expired"
      :invalid_token -> "Invalid token format"
      :invalid_signature -> "Invalid token signature"
      :rate_limited -> "Rate limit exceeded"
      _ -> "Authentication failed"
    end
  end
end