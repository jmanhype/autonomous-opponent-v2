defmodule AutonomousOpponentV2Core.MCP.Message do
  @moduledoc """
  JSON-RPC 2.0 message handling for Model Context Protocol (MCP).
  
  Implements the official MCP message format based on JSON-RPC 2.0
  specification with MCP-specific extensions.
  
  Message types:
  - Request: Client -> Server with ID for response
  - Response: Server -> Client with matching ID
  - Notification: Server -> Client without ID
  - Error: Error response with code and message
  """
  
  require Logger
  
  @type message_id :: String.t() | number()
  @type method :: String.t()
  @type params :: map() | list() | nil
  
  @type request :: %{
    jsonrpc: String.t(),
    method: method(),
    params: params(),
    id: message_id()
  }
  
  @type response :: %{
    jsonrpc: String.t(),
    result: any(),
    id: message_id()
  }
  
  @type error_response :: %{
    jsonrpc: String.t(),
    error: %{
      code: integer(),
      message: String.t(),
      data: any()
    },
    id: message_id()
  }
  
  @type notification :: %{
    jsonrpc: String.t(),
    method: method(),
    params: params()
  }
  
  @jsonrpc_version "2.0"
  
  # Standard JSON-RPC error codes
  @parse_error -32700
  @invalid_request -32600
  @method_not_found -32601
  @invalid_params -32602
  @internal_error -32603
  
  # MCP-specific error codes
  @resource_not_found -32001
  @tool_execution_error -32002
  @prompt_generation_error -32003
  @transport_error -32004
  
  @doc """
  Parses raw JSON message into structured MCP message.
  """
  @spec parse(binary()) :: {:ok, request() | response() | notification()} | {:error, term()}
  def parse(raw_message) when is_binary(raw_message) do
    case Jason.decode(raw_message) do
      {:ok, message} when is_map(message) ->
        validate_message(message)
        
      {:ok, _} ->
        {:error, :invalid_message_format}
        
      {:error, reason} ->
        {:error, {:json_decode, reason}}
    end
  end
  
  @doc """
  Creates a JSON-RPC request message.
  """
  @spec create_request(method(), params(), message_id()) :: request()
  def create_request(method, params \\ nil, id) do
    %{
      jsonrpc: @jsonrpc_version,
      method: method,
      params: params,
      id: id
    }
  end
  
  @doc """
  Creates a JSON-RPC response message.
  """
  @spec create_response(message_id(), any()) :: response()
  def create_response(id, result) do
    %{
      jsonrpc: @jsonrpc_version,
      result: result,
      id: id
    }
  end
  
  @doc """
  Creates a JSON-RPC error response.
  """
  @spec create_error(message_id(), String.t() | atom(), String.t(), any()) :: error_response()
  def create_error(id, error_code, message, data \\ nil) do
    code = case error_code do
      :parse_error -> @parse_error
      :invalid_request -> @invalid_request
      :method_not_found -> @method_not_found
      :invalid_params -> @invalid_params
      :internal_error -> @internal_error
      :resource_not_found -> @resource_not_found
      :tool_execution_error -> @tool_execution_error
      :prompt_generation_error -> @prompt_generation_error
      :transport_error -> @transport_error
      code when is_integer(code) -> code
      _ -> @internal_error
    end
    
    error = %{
      code: code,
      message: message
    }
    
    error = if data, do: Map.put(error, :data, data), else: error
    
    %{
      jsonrpc: @jsonrpc_version,
      error: error,
      id: id
    }
  end
  
  @doc """
  Creates a JSON-RPC notification message.
  """
  @spec create_notification(method(), params()) :: notification()
  def create_notification(method, params \\ nil) do
    %{
      jsonrpc: @jsonrpc_version,
      method: method,
      params: params
    }
  end
  
  @doc """
  Serializes message to JSON string.
  """
  @spec serialize(request() | response() | error_response() | notification()) :: 
    {:ok, binary()} | {:error, term()}
  def serialize(message) do
    Jason.encode(message)
  end
  
  @doc """
  Determines the type of a message.
  """
  @spec message_type(map()) :: :request | :response | :error | :notification | :invalid
  def message_type(%{"jsonrpc" => @jsonrpc_version, "method" => _, "id" => _}), do: :request
  def message_type(%{"jsonrpc" => @jsonrpc_version, "result" => _, "id" => _}), do: :response
  def message_type(%{"jsonrpc" => @jsonrpc_version, "error" => _, "id" => _}), do: :error
  def message_type(%{"jsonrpc" => @jsonrpc_version, "method" => _}), do: :notification
  def message_type(_), do: :invalid
  
  @doc """
  Validates MCP-specific message constraints.
  """
  @spec validate_mcp_message(map()) :: {:ok, map()} | {:error, term()}
  def validate_mcp_message(message) do
    case message_type(message) do
      :request ->
        validate_mcp_request(message)
        
      :response ->
        validate_mcp_response(message)
        
      :notification ->
        validate_mcp_notification(message)
        
      :error ->
        {:ok, message}
        
      :invalid ->
        {:error, :invalid_message_type}
    end
  end
  
  # Private Functions
  
  defp validate_message(%{"jsonrpc" => @jsonrpc_version} = message) do
    case message_type(message) do
      :invalid ->
        {:error, :invalid_message_structure}
        
      _type ->
        validate_mcp_message(message)
    end
  end
  
  defp validate_message(%{"jsonrpc" => version}) do
    Logger.warning("Unsupported JSON-RPC version: #{version}")
    {:error, {:unsupported_version, version}}
  end
  
  defp validate_message(_message) do
    {:error, :missing_jsonrpc_version}
  end
  
  defp validate_mcp_request(%{"method" => method} = message) when is_binary(method) do
    case validate_mcp_method(method) do
      :ok ->
        {:ok, atomize_keys(message)}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp validate_mcp_request(_), do: {:error, :invalid_method}
  
  defp validate_mcp_response(message) do
    {:ok, atomize_keys(message)}
  end
  
  defp validate_mcp_notification(%{"method" => method} = message) when is_binary(method) do
    case validate_mcp_method(method) do
      :ok ->
        {:ok, atomize_keys(message)}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp validate_mcp_notification(_), do: {:error, :invalid_method}
  
  defp validate_mcp_method("initialize"), do: :ok
  defp validate_mcp_method("initialized"), do: :ok
  defp validate_mcp_method("ping"), do: :ok
  defp validate_mcp_method("resources/list"), do: :ok
  defp validate_mcp_method("resources/read"), do: :ok
  defp validate_mcp_method("resources/subscribe"), do: :ok
  defp validate_mcp_method("resources/unsubscribe"), do: :ok
  defp validate_mcp_method("tools/list"), do: :ok
  defp validate_mcp_method("tools/call"), do: :ok
  defp validate_mcp_method("prompts/list"), do: :ok
  defp validate_mcp_method("prompts/get"), do: :ok
  defp validate_mcp_method("sampling/createMessage"), do: :ok
  defp validate_mcp_method("completion/complete"), do: :ok
  defp validate_mcp_method("logging/setLevel"), do: :ok
  
  # VSM-specific notifications
  defp validate_mcp_method("vsm/state_changed"), do: :ok
  defp validate_mcp_method("vsm/algedonic_signal"), do: :ok
  defp validate_mcp_method("vsm/consciousness_update"), do: :ok
  defp validate_mcp_method("vsm/subsystem_event"), do: :ok
  
  # Resource notifications
  defp validate_mcp_method("notifications/resources/list_changed"), do: :ok
  defp validate_mcp_method("notifications/resources/updated"), do: :ok
  defp validate_mcp_method("notifications/tools/list_changed"), do: :ok
  defp validate_mcp_method("notifications/prompts/list_changed"), do: :ok
  
  defp validate_mcp_method(method) do
    Logger.warning("Unknown MCP method: #{method}")
    :ok  # Allow unknown methods for extensibility
  end
  
  defp atomize_keys(message) when is_map(message) do
    message
    |> Enum.map(fn
      {key, value} when is_binary(key) ->
        {String.to_atom(key), value}
      {key, value} ->
        {key, value}
    end)
    |> Map.new()
  end
  
  @doc """
  Creates an MCP-compliant error for common scenarios.
  """
  def resource_not_found_error(id, uri) do
    create_error(id, :resource_not_found, "Resource not found", %{uri: uri})
  end
  
  def tool_execution_error(id, tool_name, reason) do
    create_error(id, :tool_execution_error, "Tool execution failed", %{
      tool: tool_name,
      reason: reason
    })
  end
  
  def invalid_params_error(id, details) do
    create_error(id, :invalid_params, "Invalid parameters", details)
  end
  
  def transport_error(id, reason) do
    create_error(id, :transport_error, "Transport error", %{reason: reason})
  end
  
  @doc """
  Validates required parameters for MCP methods.
  """
  def validate_params("resources/read", %{"uri" => uri}) when is_binary(uri), do: :ok
  def validate_params("resources/read", _), do: {:error, "uri parameter required"}
  
  def validate_params("tools/call", %{"name" => name}) when is_binary(name), do: :ok
  def validate_params("tools/call", _), do: {:error, "name parameter required"}
  
  def validate_params("prompts/get", %{"name" => name}) when is_binary(name), do: :ok
  def validate_params("prompts/get", _), do: {:error, "name parameter required"}
  
  def validate_params(_method, _params), do: :ok
end