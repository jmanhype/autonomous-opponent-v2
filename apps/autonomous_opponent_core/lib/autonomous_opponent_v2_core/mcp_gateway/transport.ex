defmodule AutonomousOpponentV2Core.MCPGateway.Transport do
  @moduledoc """
  Behaviour for MCP Gateway transport implementations.
  
  All transport modules must implement this behaviour to ensure
  consistent interface across different transport mechanisms.
  """
  
  @type connection_id :: String.t()
  @type message :: map() | String.t()
  @type opts :: keyword()
  @type error :: {:error, atom() | String.t()}
  
  @doc """
  Connect a client using this transport.
  Returns {:ok, connection_id} or error.
  """
  @callback connect(client_ref :: any(), opts :: opts()) :: 
    {:ok, connection_id()} | error()
  
  @doc """
  Send a message through this transport.
  """
  @callback send(connection_id(), message(), opts()) :: 
    :ok | error()
  
  @doc """
  Close a connection.
  """
  @callback close(connection_id()) :: 
    :ok | error()
end