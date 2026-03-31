defmodule JidoCode.Agents.SupportAgentConfigs do
  @moduledoc """
  Reads and updates per-project Issue Bot configuration.
  """

  alias JidoCode.Control.Actor
  alias JidoCode.Projects.Project

  @load_error_type "support_agent_config_load_failed"
  @validation_error_type "support_agent_config_validation_failed"
  @not_found_error_type "support_agent_config_project_not_found"
  @persistence_error_type "support_agent_config_persistence_failed"

  @load_remediation """
  Retry loading agent configuration. If this persists, verify project access and database connectivity.
  """

  @validation_remediation """
  Select a valid project row and choose either Enable or Disable Issue Bot.
  """

  @webhook_events_validation_remediation """
  Select only supported webhook events and retry saving Issue Bot webhook event settings.
  """

  @approval_mode_validation_remediation """
  Select either Auto-post or Approval required and retry saving Issue Bot approval mode.
  """

  @not_found_remediation """
  Refresh the Agents page and retry from an existing project row.
  """

  @persistence_remediation """
  Retry the Issue Bot toggle. If this persists, verify project settings persistence health.
  """

  @supported_issue_bot_webhook_events [
    "issues.opened",
    "issues.edited",
    "issue_comment.created"
  ]

  @approval_mode_auto_post "auto_post"
  @approval_mode_approval_required "approval_required"
  @default_issue_bot_approval_mode @approval_mode_approval_required
  @approval_mode_source "support_agent_config.github_issue_bot.approval_mode"
  @project_actor Actor.operator_actor(%{
                   "id" => "system:support-agent-configs",
                   "email" => "support-agent-configs@system.local"
                 })

  @supported_issue_bot_approval_modes [
    @approval_mode_auto_post,
    @approval_mode_approval_required
  ]

  @type typed_error :: %{
          error_type: String.t(),
          detail: String.t(),
          remediation: String.t()
        }

  @type issue_bot_config :: %{
          id: String.t(),
          name: String.t(),
          github_full_name: String.t(),
          enabled: boolean(),
          webhook_events: [String.t()],
          approval_policy: map(),
          last_updated: map()
        }

  @spec supported_issue_bot_webhook_events() :: [String.t()]
  def supported_issue_bot_webhook_events do
    @supported_issue_bot_webhook_events
  end

  @spec supported_issue_bot_approval_modes() :: [String.t()]
  def supported_issue_bot_approval_modes do
    @supported_issue_bot_approval_modes
  end

  @spec list_issue_bot_configs() :: {:ok, [issue_bot_config()]} | {:error, typed_error()}
  def list_issue_bot_configs do
    case list_projects() do
      {:ok, projects} ->
        {:ok, Enum.map(projects, &to_issue_bot_config/1)}

      {:error, typed_error} ->
        {:error, normalize_typed_error(typed_error, @load_error_type, @load_remediation)}
    end
  end

  @spec set_issue_bot_enabled(term(), term()) ::
          {:ok, issue_bot_config()} | {:error, typed_error()}
  def set_issue_bot_enabled(project_id, enabled_value) do
    with {:ok, normalized_project_id} <- normalize_project_id(project_id),
         {:ok, enabled} <- normalize_enabled_input(enabled_value),
         {:ok, project} <- fetch_project(normalized_project_id),
         settings <- project |> map_get(:settings, "settings", %{}) |> normalize_map(),
         updated_settings <- put_issue_bot_enabled(settings, enabled),
         {:ok, updated_project} <- persist_project_settings(project, updated_settings) do
      {:ok, to_issue_bot_config(updated_project)}
    else
      {:error, typed_error} ->
        {:error, typed_error}

      other ->
        {:error,
         typed_error(
           @persistence_error_type,
           "Issue Bot configuration update returned an unexpected result (#{inspect(other)}).",
           @persistence_remediation
         )}
    end
  end

  @spec set_issue_bot_webhook_events(term(), term()) ::
          {:ok, issue_bot_config()} | {:error, typed_error()}
  def set_issue_bot_webhook_events(project_id, webhook_events_value) do
    with {:ok, normalized_project_id} <- normalize_project_id(project_id),
         {:ok, webhook_events} <- normalize_webhook_events_input(webhook_events_value),
         {:ok, project} <- fetch_project(normalized_project_id),
         settings <- project |> map_get(:settings, "settings", %{}) |> normalize_map(),
         updated_settings <- put_issue_bot_webhook_events(settings, webhook_events),
         {:ok, updated_project} <- persist_project_settings(project, updated_settings) do
      {:ok, to_issue_bot_config(updated_project)}
    else
      {:error, typed_error} ->
        {:error, typed_error}

      other ->
        {:error,
         typed_error(
           @persistence_error_type,
           "Issue Bot webhook event configuration update returned an unexpected result (#{inspect(other)}).",
           @persistence_remediation
         )}
    end
  end

  @spec set_issue_bot_approval_mode(term(), term()) ::
          {:ok, issue_bot_config()} | {:error, typed_error()}
  def set_issue_bot_approval_mode(project_id, approval_mode_value) do
    with {:ok, normalized_project_id} <- normalize_project_id(project_id),
         {:ok, approval_mode} <- normalize_issue_bot_approval_mode_input(approval_mode_value),
         {:ok, project} <- fetch_project(normalized_project_id),
         settings <- project |> map_get(:settings, "settings", %{}) |> normalize_map(),
         updated_settings <- put_issue_bot_approval_mode(settings, approval_mode),
         {:ok, updated_project} <- persist_project_settings(project, updated_settings) do
      {:ok, to_issue_bot_config(updated_project)}
    else
      {:error, typed_error} ->
        {:error, typed_error}

      other ->
        {:error,
         typed_error(
           @persistence_error_type,
           "Issue Bot approval mode configuration update returned an unexpected result (#{inspect(other)}).",
           @persistence_remediation
         )}
    end
  end

  defp list_projects do
    loader =
      Application.get_env(
        :jido_code,
        :support_agent_config_project_loader,
        &__MODULE__.default_loader/0
      )

    if is_function(loader, 0) do
      safe_invoke_loader(loader)
    else
      {:error,
       typed_error(
         @load_error_type,
         "Support agent config loader is invalid.",
         @load_remediation
       )}
    end
  end

  @doc false
  @spec default_loader() :: {:ok, [Project.t()]} | {:error, typed_error()}
  def default_loader do
    case Project.read(query: [sort: [github_full_name: :asc]], actor: @project_actor) do
      {:ok, projects} when is_list(projects) ->
        {:ok, projects}

      {:ok, other} ->
        {:error,
         typed_error(
           @load_error_type,
           "Project loader returned an invalid list result (#{inspect(other)}).",
           @load_remediation
         )}

      {:error, reason} ->
        {:error,
         typed_error(
           @load_error_type,
           "Issue Bot configuration load failed (#{format_reason(reason)}).",
           @load_remediation
         )}
    end
  end

  defp safe_invoke_loader(loader) do
    try do
      loader.()
    rescue
      exception ->
        {:error,
         typed_error(
           @load_error_type,
           "Issue Bot configuration loader crashed (#{Exception.message(exception)}).",
           @load_remediation
         )}
    catch
      kind, reason ->
        {:error,
         typed_error(
           @load_error_type,
           "Issue Bot configuration loader threw #{inspect({kind, reason})}.",
           @load_remediation
         )}
    end
  end

  defp normalize_project_id(project_id) do
    case normalize_optional_string(project_id) do
      nil ->
        {:error,
         typed_error(
           @validation_error_type,
           "Project identifier is missing for Issue Bot configuration update.",
           @validation_remediation
         )}

      normalized_project_id ->
        {:ok, normalized_project_id}
    end
  end

  defp normalize_enabled_input(true), do: {:ok, true}
  defp normalize_enabled_input(false), do: {:ok, false}
  defp normalize_enabled_input("true"), do: {:ok, true}
  defp normalize_enabled_input("false"), do: {:ok, false}

  defp normalize_enabled_input(_enabled_value) do
    {:error,
     typed_error(
       @validation_error_type,
       "Issue Bot enabled state is invalid. Expected true or false.",
       @validation_remediation
     )}
  end

  defp normalize_webhook_events_input(webhook_events_value) do
    normalized_events = normalize_webhook_events(webhook_events_value)

    unsupported_events = normalized_events -- @supported_issue_bot_webhook_events

    if unsupported_events == [] do
      {:ok, sort_webhook_events_by_supported_order(normalized_events)}
    else
      {:error,
       typed_error(
         @validation_error_type,
         "Issue Bot webhook event list contains unsupported values: #{Enum.join(unsupported_events, ", ")}.",
         @webhook_events_validation_remediation
       )}
    end
  end

  defp normalize_issue_bot_approval_mode_input(approval_mode_value) do
    case normalize_issue_bot_approval_mode(approval_mode_value) do
      nil ->
        {:error,
         typed_error(
           @validation_error_type,
           "Issue Bot approval mode is invalid. Expected auto_post or approval_required.",
           @approval_mode_validation_remediation
         )}

      approval_mode ->
        {:ok, approval_mode}
    end
  end

  defp fetch_project(project_id) do
    case Project.read(query: [filter: [id: project_id], limit: 1], actor: @project_actor) do
      {:ok, [project | _rest]} ->
        {:ok, project}

      {:ok, []} ->
        {:error,
         typed_error(
           @not_found_error_type,
           "Project #{project_id} was not found for Issue Bot configuration update.",
           @not_found_remediation
         )}

      {:error, reason} ->
        {:error,
         typed_error(
           @load_error_type,
           "Project lookup for Issue Bot configuration failed (#{format_reason(reason)}).",
           @load_remediation
         )}
    end
  end

  defp persist_project_settings(project, updated_settings) do
    updater =
      Application.get_env(
        :jido_code,
        :support_agent_config_project_updater,
        &__MODULE__.default_updater/2
      )

    if is_function(updater, 2) do
      safe_invoke_updater(updater, project, %{settings: updated_settings})
    else
      {:error,
       typed_error(
         @persistence_error_type,
         "Support agent config updater is invalid.",
         @persistence_remediation
       )}
    end
  end

  @doc false
  @spec default_updater(Project.t(), map()) :: {:ok, Project.t()} | {:error, term()}
  def default_updater(project, update_attributes) do
    Project.update(project, update_attributes, actor: @project_actor)
  end

  defp safe_invoke_updater(updater, project, update_attributes) do
    try do
      case updater.(project, update_attributes) do
        {:ok, updated_project} ->
          {:ok, updated_project}

        {:error, reason} ->
          {:error,
           typed_error(
             @persistence_error_type,
             "Issue Bot configuration persistence failed (#{format_reason(reason)}).",
             @persistence_remediation
           )}

        other ->
          {:error,
           typed_error(
             @persistence_error_type,
             "Issue Bot configuration updater returned invalid output (#{inspect(other)}).",
             @persistence_remediation
           )}
      end
    rescue
      exception ->
        {:error,
         typed_error(
           @persistence_error_type,
           "Issue Bot configuration updater crashed (#{Exception.message(exception)}).",
           @persistence_remediation
         )}
    catch
      kind, reason ->
        {:error,
         typed_error(
           @persistence_error_type,
           "Issue Bot configuration updater threw #{inspect({kind, reason})}.",
           @persistence_remediation
         )}
    end
  end

  defp to_issue_bot_config(project) do
    settings =
      project
      |> map_get(:settings, "settings", %{})
      |> normalize_map()

    %{
      id:
        project
        |> map_get(:id, "id")
        |> normalize_optional_string() || "unknown-project",
      name:
        project
        |> map_get(:name, "name")
        |> normalize_optional_string() || "unknown-project",
      github_full_name:
        project
        |> map_get(:github_full_name, "github_full_name")
        |> normalize_optional_string() ||
          project
          |> map_get(:name, "name")
          |> normalize_optional_string() || "unknown-project",
      enabled: issue_bot_enabled(settings),
      webhook_events: issue_bot_webhook_events(settings),
      approval_policy: issue_bot_approval_policy(settings),
      last_updated: issue_bot_last_updated(project)
    }
  end

  defp issue_bot_enabled(settings) when is_map(settings) do
    settings
    |> map_get(:support_agent_config, "support_agent_config", %{})
    |> normalize_map()
    |> map_get(:github_issue_bot, "github_issue_bot", %{})
    |> normalize_map()
    |> map_get(:enabled, "enabled")
    |> normalize_enabled(true)
  end

  defp issue_bot_enabled(_settings), do: true

  defp issue_bot_webhook_events(settings) when is_map(settings) do
    issue_bot_settings = issue_bot_settings(settings)

    if map_has_key?(issue_bot_settings, :webhook_events, "webhook_events") do
      issue_bot_settings
      |> map_get(:webhook_events, "webhook_events")
      |> normalize_webhook_events()
      |> sort_webhook_events_by_supported_order()
    else
      @supported_issue_bot_webhook_events
    end
  end

  defp issue_bot_webhook_events(_settings), do: @supported_issue_bot_webhook_events

  defp issue_bot_approval_policy(settings) when is_map(settings) do
    approval_mode = issue_bot_approval_mode(settings)

    %{
      mode: approval_mode,
      auto_post: approval_mode == @approval_mode_auto_post,
      requires_approval: approval_mode == @approval_mode_approval_required,
      source: @approval_mode_source
    }
  end

  defp issue_bot_approval_policy(_settings), do: issue_bot_approval_policy(%{})

  defp issue_bot_approval_mode(settings) when is_map(settings) do
    settings
    |> issue_bot_settings()
    |> map_get(:approval_mode, "approval_mode", @default_issue_bot_approval_mode)
    |> normalize_issue_bot_approval_mode() || @default_issue_bot_approval_mode
  end

  defp issue_bot_approval_mode(_settings), do: @default_issue_bot_approval_mode

  defp put_issue_bot_enabled(settings, enabled) when is_map(settings) do
    settings
    |> issue_bot_settings()
    |> Map.put("enabled", enabled)
    |> put_issue_bot_settings(settings)
  end

  defp put_issue_bot_enabled(_settings, enabled) do
    put_issue_bot_enabled(%{}, enabled)
  end

  defp put_issue_bot_webhook_events(settings, webhook_events) when is_map(settings) do
    settings
    |> issue_bot_settings()
    |> Map.put("webhook_events", webhook_events)
    |> put_issue_bot_settings(settings)
  end

  defp put_issue_bot_webhook_events(_settings, webhook_events) do
    put_issue_bot_webhook_events(%{}, webhook_events)
  end

  defp put_issue_bot_approval_mode(settings, approval_mode) when is_map(settings) do
    settings
    |> issue_bot_settings()
    |> Map.put("approval_mode", approval_mode)
    |> put_issue_bot_settings(settings)
  end

  defp put_issue_bot_approval_mode(_settings, approval_mode) do
    put_issue_bot_approval_mode(%{}, approval_mode)
  end

  defp issue_bot_settings(settings) when is_map(settings) do
    settings
    |> map_get(:support_agent_config, "support_agent_config", %{})
    |> normalize_map()
    |> map_get(:github_issue_bot, "github_issue_bot", %{})
    |> normalize_map()
  end

  defp issue_bot_settings(_settings), do: %{}

  defp put_issue_bot_settings(issue_bot_config, settings) when is_map(settings) do
    support_agent_config =
      settings
      |> map_get(:support_agent_config, "support_agent_config", %{})
      |> normalize_map()
      |> Map.put("github_issue_bot", normalize_map(issue_bot_config))

    Map.put(settings, "support_agent_config", support_agent_config)
  end

  defp put_issue_bot_settings(issue_bot_config, _settings),
    do: put_issue_bot_settings(issue_bot_config, %{})

  defp issue_bot_last_updated(project) do
    updated_at =
      project
      |> map_get(:updated_at, "updated_at")
      |> normalize_optional_datetime()

    inserted_at =
      project
      |> map_get(:inserted_at, "inserted_at")
      |> normalize_optional_datetime()

    {updated_at_iso8601, source} =
      cond do
        is_struct(updated_at, DateTime) ->
          {DateTime.to_iso8601(updated_at), "project.updated_at"}

        is_struct(inserted_at, DateTime) ->
          {DateTime.to_iso8601(inserted_at), "project.inserted_at"}

        true ->
          {nil, "unavailable"}
      end

    %{
      updated_at: updated_at_iso8601,
      source: source
    }
  end

  defp normalize_typed_error(error, fallback_error_type, fallback_remediation) do
    typed_error(
      map_get(error, :error_type, "error_type", fallback_error_type),
      map_get(error, :detail, "detail", "Support agent configuration update failed."),
      map_get(error, :remediation, "remediation", fallback_remediation)
    )
  end

  defp typed_error(error_type, detail, remediation) do
    %{
      error_type: normalize_optional_string(error_type) || @persistence_error_type,
      detail: normalize_optional_string(detail) || "Support agent configuration update failed.",
      remediation: normalize_optional_string(remediation) || @persistence_remediation
    }
  end

  defp format_reason(reason) do
    reason
    |> Exception.message()
  rescue
    _exception -> inspect(reason)
  end

  defp normalize_enabled(true, _default), do: true
  defp normalize_enabled(false, _default), do: false
  defp normalize_enabled("true", _default), do: true
  defp normalize_enabled("false", _default), do: false
  defp normalize_enabled("enabled", _default), do: true
  defp normalize_enabled("disabled", _default), do: false
  defp normalize_enabled(:enabled, _default), do: true
  defp normalize_enabled(:disabled, _default), do: false
  defp normalize_enabled(_enabled, default), do: default

  defp sort_webhook_events_by_supported_order(webhook_events) when is_list(webhook_events) do
    @supported_issue_bot_webhook_events
    |> Enum.filter(&(&1 in webhook_events))
  end

  defp sort_webhook_events_by_supported_order(_webhook_events), do: []

  defp normalize_webhook_events(webhook_events) when is_binary(webhook_events) do
    webhook_events
    |> normalize_optional_string()
    |> case do
      nil -> []
      normalized_event -> [normalized_event]
    end
  end

  defp normalize_webhook_events(webhook_events) when is_list(webhook_events) do
    webhook_events
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_webhook_events(_webhook_events), do: []

  defp normalize_issue_bot_approval_mode(approval_mode) when is_binary(approval_mode) do
    case approval_mode |> String.trim() |> String.downcase() do
      "auto_post" -> @approval_mode_auto_post
      "auto-post" -> @approval_mode_auto_post
      "auto" -> @approval_mode_auto_post
      "approval_required" -> @approval_mode_approval_required
      "approval-required" -> @approval_mode_approval_required
      "manual" -> @approval_mode_approval_required
      "manual_gate" -> @approval_mode_approval_required
      "manual-gate" -> @approval_mode_approval_required
      _other -> nil
    end
  end

  defp normalize_issue_bot_approval_mode(approval_mode) when is_atom(approval_mode) do
    approval_mode
    |> Atom.to_string()
    |> normalize_issue_bot_approval_mode()
  end

  defp normalize_issue_bot_approval_mode(_approval_mode), do: nil

  defp normalize_optional_datetime(%DateTime{} = datetime),
    do: DateTime.truncate(datetime, :second)

  defp normalize_optional_datetime(%NaiveDateTime{} = datetime) do
    case DateTime.from_naive(datetime, "Etc/UTC") do
      {:ok, parsed_datetime} -> normalize_optional_datetime(parsed_datetime)
      _other -> nil
    end
  end

  defp normalize_optional_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, parsed_datetime, _offset} ->
        normalize_optional_datetime(parsed_datetime)

      _other ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, parsed_datetime} ->
            normalize_optional_datetime(parsed_datetime)

          _fallback ->
            nil
        end
    end
  end

  defp normalize_optional_datetime(_value), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized_value -> normalized_value
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: normalize_optional_string(Atom.to_string(value))

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp map_has_key?(map, atom_key, string_key) when is_map(map) do
    Map.has_key?(map, atom_key) or Map.has_key?(map, string_key)
  end

  defp map_has_key?(_map, _atom_key, _string_key), do: false
end
