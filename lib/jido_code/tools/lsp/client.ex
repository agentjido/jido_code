defmodule JidoCode.Tools.LSP.Client do
  @moduledoc """
  GenServer that manages the connection to Expert, the official Elixir LSP.

  This module handles:
  - Spawning and connecting to Expert via stdio
  - JSON-RPC message framing (Content-Length headers)
  - LSP initialize/initialized handshake
  - Request/response correlation via request IDs
  - Notification handling (for diagnostics)
  - Graceful shutdown
  - Process lifecycle management (restart on crash)

  ## Usage

      # Start the client (usually via supervision tree)
      {:ok, pid} = Client.start_link(project_root: "/path/to/project")

      # Send LSP requests
      {:ok, response} = Client.request(pid, "textDocument/hover", %{
        "textDocument" => %{"uri" => "file:///path/to/file.ex"},
        "position" => %{"line" => 10, "character" => 5}
      })

      # Subscribe to notifications
      Client.subscribe(pid, self())

  ## Configuration

  The client looks for the Expert executable in:
  1. `EXPERT_PATH` environment variable
  2. `expert` in system PATH

  ## Reference

  https://github.com/elixir-lang/expert
  """

  use GenServer

  require Logger

  # ============================================================================
  # Types
  # ============================================================================

  @type request_id :: integer()
  @type lsp_method :: String.t()
  @type lsp_params :: map()
  @type lsp_result :: map() | list() | nil
  @type pending_request :: {pid(), reference(), lsp_method()}

  @type state :: %{
          port: port() | nil,
          project_root: String.t(),
          request_id: request_id(),
          pending_requests: %{request_id() => pending_request()},
          buffer: binary(),
          initialized: boolean(),
          capabilities: map(),
          subscribers: [pid()],
          expert_path: String.t() | nil,
          diagnostics: %{String.t() => [map()]}
        }

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the LSP client GenServer.

  ## Options

    * `:project_root` - Required. The root directory of the project.
    * `:expert_path` - Optional. Path to the Expert executable.
    * `:name` - Optional. GenServer name for registration.
    * `:auto_start` - Optional. Whether to start Expert immediately. Default: true.

  ## Examples

      {:ok, pid} = Client.start_link(project_root: "/path/to/project")
      {:ok, pid} = Client.start_link(project_root: "/path", name: MyApp.LSP)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Sends an LSP request and waits for the response.

  ## Parameters

    * `server` - The client pid or registered name.
    * `method` - The LSP method (e.g., "textDocument/hover").
    * `params` - The request parameters.
    * `timeout` - Optional timeout in milliseconds. Default: 30000.

  ## Returns

    * `{:ok, result}` - The LSP result.
    * `{:error, reason}` - An error occurred.

  ## Examples

      {:ok, hover} = Client.request(pid, "textDocument/hover", %{
        "textDocument" => %{"uri" => "file:///path/to/file.ex"},
        "position" => %{"line" => 10, "character" => 5}
      })
  """
  @spec request(GenServer.server(), lsp_method(), lsp_params(), timeout()) ::
          {:ok, lsp_result()} | {:error, term()}
  def request(server, method, params, timeout \\ 30_000) do
    GenServer.call(server, {:request, method, params}, timeout)
  catch
    :exit, {:timeout, _} ->
      {:error, :timeout}

    :exit, reason ->
      {:error, {:exit, reason}}
  end

  @doc """
  Sends an LSP notification (no response expected).

  ## Parameters

    * `server` - The client pid or registered name.
    * `method` - The LSP notification method.
    * `params` - The notification parameters.

  ## Examples

      :ok = Client.notify(pid, "textDocument/didOpen", %{
        "textDocument" => %{
          "uri" => "file:///path/to/file.ex",
          "languageId" => "elixir",
          "version" => 1,
          "text" => "defmodule MyApp do\\nend"
        }
      })
  """
  @spec notify(GenServer.server(), lsp_method(), lsp_params()) :: :ok
  def notify(server, method, params) do
    GenServer.cast(server, {:notify, method, params})
  end

  @doc """
  Subscribes to LSP notifications.

  The subscriber will receive messages in the form:
  `{:lsp_notification, method, params}`

  ## Examples

      :ok = Client.subscribe(pid, self())
  """
  @spec subscribe(GenServer.server(), pid()) :: :ok
  def subscribe(server, subscriber_pid) do
    GenServer.cast(server, {:subscribe, subscriber_pid})
  end

  @doc """
  Unsubscribes from LSP notifications.
  """
  @spec unsubscribe(GenServer.server(), pid()) :: :ok
  def unsubscribe(server, subscriber_pid) do
    GenServer.cast(server, {:unsubscribe, subscriber_pid})
  end

  @doc """
  Returns the current state of the client.

  Useful for debugging and checking if the client is initialized.
  """
  @spec status(GenServer.server()) :: map()
  def status(server) do
    GenServer.call(server, :status)
  end

  @doc """
  Gracefully shuts down the LSP server.
  """
  @spec shutdown(GenServer.server()) :: :ok
  def shutdown(server) do
    GenServer.call(server, :shutdown)
  end

  @doc """
  Retrieves cached diagnostics from the LSP server.

  Diagnostics are received via `textDocument/publishDiagnostics` notifications
  and cached in the client state. This function returns the cached diagnostics
  for a specific file or all files.

  ## Parameters

    * `server` - The client pid or registered name.
    * `path` - Optional. File path to get diagnostics for. If `nil`, returns
      diagnostics for all files.

  ## Returns

    * `{:ok, diagnostics}` - A map of file URIs to their diagnostics lists.
    * `{:error, :not_initialized}` - The client is not yet initialized.

  ## Examples

      # Get all diagnostics
      {:ok, diagnostics} = Client.get_diagnostics(pid, nil)
      # => %{"file:///path/to/file.ex" => [...], ...}

      # Get diagnostics for a specific file
      {:ok, diagnostics} = Client.get_diagnostics(pid, "lib/my_app.ex")
      # => %{"file:///path/to/project/lib/my_app.ex" => [...]}
  """
  @spec get_diagnostics(GenServer.server(), String.t() | nil) ::
          {:ok, %{String.t() => [map()]}} | {:error, :not_initialized}
  def get_diagnostics(server, path \\ nil) do
    GenServer.call(server, {:get_diagnostics, path})
  end

  @doc """
  Clears cached diagnostics for a file or all files.

  ## Parameters

    * `server` - The client pid or registered name.
    * `path` - Optional. File path to clear diagnostics for. If `nil`, clears
      all diagnostics.
  """
  @spec clear_diagnostics(GenServer.server(), String.t() | nil) :: :ok
  def clear_diagnostics(server, path \\ nil) do
    GenServer.cast(server, {:clear_diagnostics, path})
  end

  @doc """
  Checks if Expert is available in the system.
  """
  @spec expert_available?() :: boolean()
  def expert_available? do
    case find_expert_path() do
      {:ok, _path} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Finds the Expert executable path.

  Checks in order:
  1. `EXPERT_PATH` environment variable
  2. `expert` in system PATH
  """
  @spec find_expert_path() :: {:ok, String.t()} | {:error, :not_found}
  def find_expert_path do
    cond do
      path = System.get_env("EXPERT_PATH") ->
        if File.exists?(path), do: {:ok, path}, else: {:error, :not_found}

      path = System.find_executable("expert") ->
        {:ok, path}

      true ->
        {:error, :not_found}
    end
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    project_root = Keyword.fetch!(opts, :project_root)
    expert_path = Keyword.get(opts, :expert_path)
    auto_start = Keyword.get(opts, :auto_start, true)

    state = %{
      port: nil,
      project_root: project_root,
      request_id: 1,
      pending_requests: %{},
      buffer: <<>>,
      initialized: false,
      capabilities: %{},
      subscribers: [],
      expert_path: expert_path,
      diagnostics: %{}
    }

    if auto_start do
      send(self(), :start_expert)
    end

    {:ok, state}
  end

  @impl true
  def handle_call({:request, method, params}, from, state) do
    case state.initialized do
      true ->
        {_request_id, state} = send_request(state, method, params, from)
        {:noreply, state}

      false ->
        {:reply, {:error, :not_initialized}, state}
    end
  end

  def handle_call(:status, _from, state) do
    status = %{
      initialized: state.initialized,
      pending_requests: map_size(state.pending_requests),
      capabilities: state.capabilities,
      port_open: state.port != nil,
      project_root: state.project_root
    }

    {:reply, status, state}
  end

  def handle_call(:shutdown, _from, state) do
    state = do_shutdown(state)
    {:reply, :ok, state}
  end

  def handle_call({:get_diagnostics, path}, _from, state) do
    case state.initialized do
      true ->
        diagnostics = get_diagnostics_from_state(state, path)
        {:reply, {:ok, diagnostics}, state}

      false ->
        {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_cast({:notify, method, params}, state) do
    state = send_notification(state, method, params)
    {:noreply, state}
  end

  def handle_cast({:subscribe, pid}, state) do
    Process.monitor(pid)
    subscribers = [pid | state.subscribers] |> Enum.uniq()
    {:noreply, %{state | subscribers: subscribers}}
  end

  def handle_cast({:unsubscribe, pid}, state) do
    subscribers = List.delete(state.subscribers, pid)
    {:noreply, %{state | subscribers: subscribers}}
  end

  def handle_cast({:clear_diagnostics, nil}, state) do
    {:noreply, %{state | diagnostics: %{}}}
  end

  def handle_cast({:clear_diagnostics, path}, state) do
    uri = path_to_uri(path, state.project_root)
    diagnostics = Map.delete(state.diagnostics, uri)
    {:noreply, %{state | diagnostics: diagnostics}}
  end

  @impl true
  def handle_info(:start_expert, state) do
    case start_expert_process(state) do
      {:ok, state} ->
        # Send initialize request
        state = send_initialize_request(state)
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Failed to start Expert: #{inspect(reason)}")
        # Retry after delay
        Process.send_after(self(), :start_expert, 5_000)
        {:noreply, state}
    end
  end

  def handle_info({port, {:data, data}}, %{port: port} = state) do
    state = handle_port_data(state, data)
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("Expert process exited with status #{status}")
    state = handle_expert_crash(state)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    subscribers = List.delete(state.subscribers, pid)
    {:noreply, %{state | subscribers: subscribers}}
  end

  def handle_info(msg, state) do
    Logger.debug("LSP Client received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    do_shutdown(state)
    :ok
  end

  # ============================================================================
  # Private Functions - Expert Process Management
  # ============================================================================

  defp start_expert_process(state) do
    case resolve_expert_path(state) do
      {:ok, path} ->
        Logger.info("Starting Expert LSP from: #{path}")
        Logger.info("Project root: #{state.project_root}")

        port =
          Port.open(
            {:spawn_executable, path},
            [
              :binary,
              :exit_status,
              :use_stdio,
              :stderr_to_stdout,
              args: ["--stdio"],
              cd: state.project_root
            ]
          )

        {:ok, %{state | port: port}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_expert_path(%{expert_path: path}) when is_binary(path) do
    if File.exists?(path), do: {:ok, path}, else: {:error, :expert_not_found}
  end

  defp resolve_expert_path(_state) do
    find_expert_path()
  end

  defp handle_expert_crash(state) do
    # Fail all pending requests
    for {_id, {from, _ref, _method}} <- state.pending_requests do
      GenServer.reply(from, {:error, :expert_crashed})
    end

    # Reset state and schedule restart
    state = %{state | port: nil, initialized: false, pending_requests: %{}, buffer: <<>>}
    Process.send_after(self(), :start_expert, 1_000)
    state
  end

  defp do_shutdown(state) do
    if state.port && state.initialized do
      # Send shutdown request
      _state = send_request_sync(state, "shutdown", nil)
      # Send exit notification
      send_notification(state, "exit", nil)
      # Close port
      Port.close(state.port)
    end

    %{state | port: nil, initialized: false}
  end

  # ============================================================================
  # Private Functions - Message Sending
  # ============================================================================

  defp send_request(state, method, params, from) do
    id = state.request_id
    message = encode_request(id, method, params)

    case send_to_port(state.port, message) do
      :ok ->
        pending = Map.put(state.pending_requests, id, {from, make_ref(), method})
        {id, %{state | request_id: id + 1, pending_requests: pending}}

      {:error, reason} ->
        GenServer.reply(from, {:error, reason})
        {id, state}
    end
  end

  defp send_request_sync(state, method, params) do
    id = state.request_id
    message = encode_request(id, method, params)
    send_to_port(state.port, message)
    %{state | request_id: id + 1}
  end

  defp send_notification(state, method, params) do
    message = encode_notification(method, params)
    send_to_port(state.port, message)
    state
  end

  defp send_to_port(nil, _message), do: {:error, :port_closed}

  defp send_to_port(port, message) do
    try do
      Port.command(port, message)
      :ok
    rescue
      ArgumentError -> {:error, :port_closed}
    end
  end

  defp send_initialize_request(state) do
    initialize_params = %{
      "processId" => System.pid() |> String.to_integer(),
      "clientInfo" => %{
        "name" => "JidoCode",
        "version" => "0.1.0"
      },
      "rootUri" => "file://#{state.project_root}",
      "rootPath" => state.project_root,
      "capabilities" => client_capabilities(),
      "trace" => "off",
      "workspaceFolders" => [
        %{
          "uri" => "file://#{state.project_root}",
          "name" => Path.basename(state.project_root)
        }
      ]
    }

    id = state.request_id
    message = encode_request(id, "initialize", initialize_params)
    send_to_port(state.port, message)

    pending =
      Map.put(state.pending_requests, id, {nil, make_ref(), "initialize"})

    %{state | request_id: id + 1, pending_requests: pending}
  end

  defp client_capabilities do
    %{
      "textDocument" => %{
        "hover" => %{
          "contentFormat" => ["markdown", "plaintext"]
        },
        "definition" => %{
          "linkSupport" => true
        },
        "references" => %{},
        "publishDiagnostics" => %{
          "relatedInformation" => true
        },
        "synchronization" => %{
          "didSave" => true,
          "willSave" => false,
          "willSaveWaitUntil" => false
        }
      },
      "workspace" => %{
        "workspaceFolders" => true
      }
    }
  end

  # ============================================================================
  # Private Functions - Message Encoding (JSON-RPC)
  # ============================================================================

  defp encode_request(id, method, params) do
    body =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => id,
        "method" => method,
        "params" => params
      })

    frame_message(body)
  end

  defp encode_notification(method, params) do
    body =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => method,
        "params" => params
      })

    frame_message(body)
  end

  defp frame_message(body) do
    content_length = byte_size(body)
    "Content-Length: #{content_length}\r\n\r\n#{body}"
  end

  # ============================================================================
  # Private Functions - Message Receiving and Parsing
  # ============================================================================

  defp handle_port_data(state, data) do
    buffer = state.buffer <> data
    parse_messages(state, buffer)
  end

  defp parse_messages(state, buffer) do
    case parse_one_message(buffer) do
      {:ok, message, rest} ->
        state = handle_message(state, message)
        parse_messages(state, rest)

      :incomplete ->
        %{state | buffer: buffer}

      {:error, reason} ->
        Logger.error("Failed to parse LSP message: #{inspect(reason)}")
        %{state | buffer: <<>>}
    end
  end

  defp parse_one_message(buffer) do
    case parse_headers(buffer) do
      {:ok, content_length, rest} ->
        if byte_size(rest) >= content_length do
          <<body::binary-size(content_length), remaining::binary>> = rest

          case Jason.decode(body) do
            {:ok, message} -> {:ok, message, remaining}
            {:error, reason} -> {:error, {:json_decode, reason}}
          end
        else
          :incomplete
        end

      :incomplete ->
        :incomplete

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_headers(buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [headers, rest] ->
        case parse_content_length(headers) do
          {:ok, length} -> {:ok, length, rest}
          {:error, reason} -> {:error, reason}
        end

      [_] ->
        :incomplete
    end
  end

  defp parse_content_length(headers) do
    headers
    |> String.split("\r\n")
    |> Enum.find_value({:error, :no_content_length}, fn line ->
      case String.split(line, ": ", parts: 2) do
        ["Content-Length", value] ->
          case Integer.parse(String.trim(value)) do
            {length, ""} -> {:ok, length}
            _ -> {:error, :invalid_content_length}
          end

        _ ->
          nil
      end
    end)
  end

  # ============================================================================
  # Private Functions - Message Handling
  # ============================================================================

  defp handle_message(state, %{"id" => id, "result" => result}) do
    # Response to a request
    case Map.pop(state.pending_requests, id) do
      {{from, _ref, method}, pending} ->
        Logger.debug("LSP response for #{method}: #{inspect(result)}")

        if from do
          GenServer.reply(from, {:ok, result})
        else
          # This was the initialize response
          state = handle_initialize_result(state, result)
          %{state | pending_requests: pending}
        end

        %{state | pending_requests: pending}

      {nil, _} ->
        Logger.warning("Received response for unknown request id: #{id}")
        state
    end
  end

  defp handle_message(state, %{"id" => id, "error" => error}) do
    # Error response
    case Map.pop(state.pending_requests, id) do
      {{from, _ref, method}, pending} ->
        Logger.warning("LSP error for #{method}: #{inspect(error)}")

        if from do
          GenServer.reply(from, {:error, error})
        end

        %{state | pending_requests: pending}

      {nil, _} ->
        Logger.warning("Received error for unknown request id: #{id}")
        state
    end
  end

  defp handle_message(state, %{"method" => method, "params" => params}) do
    # Notification from server
    Logger.debug("LSP notification: #{method}")
    state = handle_notification(state, method, params)
    broadcast_notification(state, method, params)
    state
  end

  defp handle_message(state, %{"method" => method}) do
    # Notification without params
    Logger.debug("LSP notification (no params): #{method}")
    broadcast_notification(state, method, nil)
    state
  end

  defp handle_message(state, message) do
    Logger.warning("Unknown LSP message format: #{inspect(message)}")
    state
  end

  defp handle_initialize_result(state, result) do
    capabilities = Map.get(result, "capabilities", %{})
    Logger.info("Expert initialized with capabilities: #{inspect(Map.keys(capabilities))}")

    # Send initialized notification
    state = send_notification(state, "initialized", %{})

    %{state | initialized: true, capabilities: capabilities}
  end

  defp broadcast_notification(state, method, params) do
    message = {:lsp_notification, method, params}

    for subscriber <- state.subscribers do
      send(subscriber, message)
    end
  end

  # ============================================================================
  # Private Functions - Notification Handling
  # ============================================================================

  defp handle_notification(state, "textDocument/publishDiagnostics", params) do
    uri = Map.get(params, "uri", "")
    diagnostics_list = Map.get(params, "diagnostics", [])

    Logger.debug("Caching #{length(diagnostics_list)} diagnostics for #{uri}")

    diagnostics = Map.put(state.diagnostics, uri, diagnostics_list)
    %{state | diagnostics: diagnostics}
  end

  defp handle_notification(state, _method, _params), do: state

  # ============================================================================
  # Private Functions - Diagnostics Retrieval
  # ============================================================================

  defp get_diagnostics_from_state(state, nil) do
    # Return all diagnostics
    state.diagnostics
  end

  defp get_diagnostics_from_state(state, path) do
    uri = path_to_uri(path, state.project_root)

    case Map.get(state.diagnostics, uri) do
      nil -> %{}
      diagnostics -> %{uri => diagnostics}
    end
  end

  defp path_to_uri(path, project_root) do
    abs_path =
      if Path.type(path) == :absolute do
        path
      else
        Path.join(project_root, path)
      end

    "file://#{abs_path}"
  end
end
