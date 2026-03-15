defmodule JidoCode.Setup.GitHubInstallationSync do
  @moduledoc """
  Applies GitHub installation webhook events to onboarding repository availability metadata.
  """
  # covers: auth.github_integration.github_app_preferred

  alias JidoCode.Setup.SystemConfig

  @installation_events ["installation", "installation_repositories"]
  @stale_error_type "github_installation_sync_stale"
  @access_revoked_error_type "github_installation_access_revoked"
  @access_empty_error_type "github_installation_access_empty"
  @default_retry_remediation "Retry repository refresh in step 7 after confirming GitHub App installation access."

  @type repository_option :: %{
          id: String.t(),
          full_name: String.t(),
          owner: String.t(),
          name: String.t()
        }

  @type sync_summary :: %{
          status: :ready | :stale,
          event: String.t(),
          action: String.t(),
          installation_id: integer() | nil,
          repositories: [repository_option()],
          detail: String.t(),
          remediation: String.t(),
          error_type: String.t() | nil
        }

  @spec sync_verified_delivery(map()) :: :ignored | {:ok, sync_summary()} | {:error, sync_summary()}
  def sync_verified_delivery(%{} = delivery) do
    event =
      delivery
      |> Map.get(:event)
      |> normalize_optional_string()

    if event in @installation_events do
      sync_installation_event(
        event,
        Map.get(delivery, :payload),
        DateTime.utc_now() |> DateTime.truncate(:second)
      )
    else
      :ignored
    end
  end

  def sync_verified_delivery(_delivery), do: :ignored

  @spec repository_names(sync_summary()) :: [String.t()]
  def repository_names(%{repositories: repositories}) when is_list(repositories) do
    repositories
    |> Enum.map(&Map.get(&1, :full_name))
    |> Enum.reject(&is_nil/1)
  end

  def repository_names(_summary), do: []

  defp sync_installation_event(event, payload, checked_at) do
    case SystemConfig.load() do
      {:ok, %SystemConfig{} = config} ->
        case build_sync_result(config.onboarding_state, event, payload) do
          {:ok, %{} = summary} ->
            updated_onboarding_state =
              apply_sync_summary(config.onboarding_state, summary, checked_at)

            case persist_onboarding_state(updated_onboarding_state) do
              :ok ->
                {:ok, summary}

              {:error, reason} ->
                {:error,
                 stale_summary(
                   event,
                   summary.action,
                   summary.installation_id,
                   summary.repositories,
                   "Failed to persist installation sync metadata (#{inspect(reason)}).",
                   summary.remediation
                 )}
            end

          {:error, %{} = stale_summary} ->
            updated_onboarding_state =
              apply_sync_summary(config.onboarding_state, stale_summary, checked_at)

            case persist_onboarding_state(updated_onboarding_state) do
              :ok ->
                {:error, stale_summary}

              {:error, reason} ->
                {:error,
                 %{
                   stale_summary
                   | detail:
                       "#{stale_summary.detail} Failed to persist stale-state warning metadata (#{inspect(reason)})."
                 }}
            end
        end

      {:error, reason} ->
        {:error,
         stale_summary(
           event,
           "unknown",
           nil,
           [],
           "Failed to load system configuration for installation sync (#{inspect(reason)}).",
           @default_retry_remediation
         )}
    end
  end

  defp persist_onboarding_state(updated_onboarding_state) when is_map(updated_onboarding_state) do
    case SystemConfig.update_onboarding_state(fn _onboarding_state ->
           updated_onboarding_state
         end) do
      {:ok, %SystemConfig{}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_sync_result(onboarding_state, event, payload) when is_map(payload) do
    action = payload |> map_get(:action, "action") |> normalize_optional_string() || "unknown"
    installation_id = payload |> installation_payload() |> map_get(:id, "id") |> normalize_installation_id()
    existing_repositories = current_repository_options(onboarding_state)
    payload_repositories = payload_repositories(event, payload)

    case installation_id do
      nil ->
        {:error,
         stale_summary(
           event,
           action,
           nil,
           existing_repositories,
           "Installation payload is missing `installation.id`.",
           @default_retry_remediation
         )}

      normalized_installation_id ->
        repositories =
          resolve_repositories(
            event,
            action,
            existing_repositories,
            payload_repositories,
            payload
          )

        {:ok,
         ready_summary(
           event,
           action,
           normalized_installation_id,
           repositories
         )}
    end
  end

  defp build_sync_result(onboarding_state, event, _payload) do
    {:error,
     stale_summary(
       event,
       "unknown",
       nil,
       current_repository_options(onboarding_state),
       "Webhook payload is invalid for installation sync.",
       @default_retry_remediation
     )}
  end

  defp resolve_repositories(
         "installation_repositories",
         "added",
         existing_repositories,
         %{added: added_repositories, base: base_repositories},
         _payload
       ) do
    merge_repository_options(existing_repositories, added_repositories ++ base_repositories)
  end

  defp resolve_repositories(
         "installation_repositories",
         "removed",
         existing_repositories,
         %{removed: removed_repositories},
         _payload
       ) do
    removed_full_names =
      removed_repositories
      |> Enum.map(&Map.get(&1, :full_name))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    existing_repositories
    |> Enum.reject(fn repository ->
      Map.get(repository, :full_name) in removed_full_names
    end)
    |> sort_repository_options()
  end

  defp resolve_repositories(
         "installation",
         action,
         _existing_repositories,
         payload_repositories,
         _payload
       )
       when action in ["deleted", "suspend"] do
    []
    |> merge_repository_options(payload_repositories.base)
    |> remove_all_repositories()
  end

  defp resolve_repositories(
         "installation",
         _action,
         existing_repositories,
         payload_repositories,
         _payload
       ) do
    if payload_repositories.base == [] do
      existing_repositories
    else
      payload_repositories.base |> sort_repository_options()
    end
  end

  defp resolve_repositories(
         _event,
         _action,
         existing_repositories,
         payload_repositories,
         _payload
       ) do
    merge_repository_options(existing_repositories, payload_repositories.base)
  end

  defp remove_all_repositories(_repositories), do: []

  defp payload_repositories(event, payload) do
    base_repositories =
      payload
      |> map_get(:repositories, "repositories", [])
      |> normalize_repository_options()

    if event == "installation_repositories" do
      %{
        base: base_repositories,
        added:
          payload
          |> map_get(:repositories_added, "repositories_added", [])
          |> normalize_repository_options(),
        removed:
          payload
          |> map_get(:repositories_removed, "repositories_removed", [])
          |> normalize_repository_options()
      }
    else
      %{base: base_repositories, added: [], removed: []}
    end
  end

  defp ready_summary(event, action, installation_id, repositories) do
    normalized_repositories = sort_repository_options(repositories)
    repository_count = length(normalized_repositories)
    event_action = "#{event}.#{action}"

    cond do
      action in ["deleted", "suspend"] ->
        %{
          status: :ready,
          event: event,
          action: action,
          installation_id: installation_id,
          repositories: [],
          detail:
            "Installation sync processed `#{event_action}` and revoked repository availability for this installation.",
          remediation: "Reinstall the GitHub App or restore installation permissions, then retry repository refresh.",
          error_type: @access_revoked_error_type
        }

      normalized_repositories == [] ->
        %{
          status: :ready,
          event: event,
          action: action,
          installation_id: installation_id,
          repositories: [],
          detail: "Installation sync processed `#{event_action}` but no accessible repositories were reported.",
          remediation:
            "Grant GitHub App installation access to at least one repository, then retry repository refresh.",
          error_type: @access_empty_error_type
        }

      true ->
        %{
          status: :ready,
          event: event,
          action: action,
          installation_id: installation_id,
          repositories: normalized_repositories,
          detail:
            "Installation sync processed `#{event_action}` and updated accessible repository metadata (#{repository_count} repositories).",
          remediation: "Installation metadata is current.",
          error_type: nil
        }
    end
  end

  defp stale_summary(event, action, installation_id, repositories, detail, remediation) do
    %{
      status: :stale,
      event: event,
      action: action,
      installation_id: installation_id,
      repositories: sort_repository_options(repositories),
      detail:
        "Installation sync failed while processing `#{event}.#{action}`. Repository availability may be stale. #{normalize_detail(detail)}",
      remediation: remediation || @default_retry_remediation,
      error_type: @stale_error_type
    }
  end

  defp apply_sync_summary(onboarding_state, summary, checked_at) do
    updated_onboarding_state =
      onboarding_state
      |> put_step_state(7, update_step_7_state(fetch_step_state(onboarding_state, 7), summary, checked_at))

    if summary.status == :ready do
      updated_onboarding_state
      |> put_step_state(
        4,
        update_step_4_state(fetch_step_state(updated_onboarding_state, 4), summary, checked_at)
      )
    else
      updated_onboarding_state
    end
  end

  defp update_step_7_state(step_state, summary, checked_at) do
    repository_listing_state = repository_listing_state(summary, checked_at)

    step_state
    |> normalize_keyed_map()
    |> Map.put("installation_sync", serialize_installation_sync(summary, checked_at))
    |> Map.put("repository_listing", repository_listing_state)
  end

  defp update_step_4_state(step_state, summary, checked_at) do
    step_state = normalize_keyed_map(step_state)
    github_credentials = step_state |> Map.get("github_credentials", %{}) |> normalize_keyed_map()
    paths = github_credentials |> Map.get("paths", []) |> normalize_paths()

    updated_paths =
      paths
      |> upsert_github_app_path(summary, checked_at)
      |> Enum.sort_by(fn path ->
        path
        |> map_get(:path, "path", "github_app")
        |> normalize_optional_string()
      end)

    updated_github_credentials =
      github_credentials
      |> Map.put("checked_at", DateTime.to_iso8601(checked_at))
      |> Map.put("paths", updated_paths)
      |> Map.put("status", github_credentials_status(updated_paths))

    Map.put(step_state, "github_credentials", updated_github_credentials)
  end

  defp github_credentials_status(paths) when is_list(paths) do
    if Enum.any?(paths, &path_ready?/1), do: "ready", else: "blocked"
  end

  defp github_credentials_status(_paths), do: "blocked"

  defp path_ready?(path) when is_map(path) do
    path
    |> map_get(:status, "status")
    |> case do
      :ready -> true
      "ready" -> true
      _other -> false
    end
  end

  defp path_ready?(_path), do: false

  defp upsert_github_app_path(paths, summary, checked_at) do
    normalized_paths = Enum.map(paths, &normalize_keyed_map/1)
    github_app_path = build_github_app_path(summary, checked_at)

    {existing_paths, has_github_app_path?} =
      Enum.map_reduce(normalized_paths, false, fn path, found ->
        path_name =
          path
          |> map_get(:path, "path")
          |> normalize_optional_string()

        if path_name == "github_app" do
          {Map.merge(path, github_app_path), true}
        else
          {path, found}
        end
      end)

    if has_github_app_path? do
      existing_paths
    else
      [github_app_path | existing_paths]
    end
  end

  defp build_github_app_path(summary, checked_at) do
    repositories = Enum.map(summary.repositories, &serialize_repository_option/1)
    checked_at_iso8601 = DateTime.to_iso8601(checked_at)
    ready? = repositories != []

    %{
      "path" => "github_app",
      "name" => "GitHub App",
      "status" => if(ready?, do: "ready", else: "invalid"),
      "repository_access" => if(ready?, do: "confirmed", else: "unconfirmed"),
      "repositories" => repositories,
      "detail" => summary.detail,
      "remediation" => summary.remediation,
      "error_type" => summary.error_type,
      "checked_at" => checked_at_iso8601,
      "validated_at" => if(ready?, do: checked_at_iso8601, else: nil),
      "installation" => %{
        "id" => summary.installation_id,
        "event" => summary.event,
        "action" => summary.action,
        "status" => Atom.to_string(summary.status),
        "checked_at" => checked_at_iso8601
      }
    }
  end

  defp repository_listing_state(summary, checked_at) do
    checked_at_iso8601 = DateTime.to_iso8601(checked_at)
    repositories = Enum.map(summary.repositories, &serialize_repository_option/1)

    {status, error_type} =
      cond do
        summary.status == :stale ->
          {"blocked", summary.error_type || @stale_error_type}

        repositories == [] ->
          {"blocked", summary.error_type || @access_empty_error_type}

        true ->
          {"ready", nil}
      end

    %{
      "checked_at" => checked_at_iso8601,
      "status" => status,
      "repositories" => repositories,
      "detail" => summary.detail,
      "remediation" => summary.remediation,
      "error_type" => error_type
    }
  end

  defp serialize_installation_sync(summary, checked_at) do
    %{
      "checked_at" => DateTime.to_iso8601(checked_at),
      "status" => Atom.to_string(summary.status),
      "event" => summary.event,
      "action" => summary.action,
      "installation_id" => summary.installation_id,
      "accessible_repositories" => Enum.map(summary.repositories, &serialize_repository_option/1),
      "detail" => summary.detail,
      "remediation" => summary.remediation,
      "error_type" => summary.error_type
    }
  end

  defp current_repository_options(onboarding_state) do
    installation_repositories =
      onboarding_state
      |> fetch_step_state(7)
      |> map_get(:installation_sync, "installation_sync", %{})
      |> map_get(:accessible_repositories, "accessible_repositories", [])
      |> normalize_repository_options()

    listing_repositories =
      onboarding_state
      |> fetch_step_state(7)
      |> map_get(:repository_listing, "repository_listing", %{})
      |> map_get(:repositories, "repositories", [])
      |> normalize_repository_options()

    github_app_repositories =
      onboarding_state
      |> fetch_step_state(4)
      |> map_get(:github_credentials, "github_credentials", %{})
      |> map_get(:paths, "paths", [])
      |> normalize_paths()
      |> Enum.filter(fn path ->
        path_name =
          path
          |> map_get(:path, "path")
          |> normalize_optional_string()

        path_name in [nil, "github_app"]
      end)
      |> Enum.flat_map(fn path ->
        path
        |> map_get(:repositories, "repositories", [])
        |> normalize_repository_options()
      end)

    installation_repositories
    |> merge_repository_options(listing_repositories ++ github_app_repositories)
  end

  defp merge_repository_options(primary, secondary) do
    (primary ++ secondary)
    |> normalize_repository_options()
    |> Enum.uniq_by(& &1.full_name)
    |> sort_repository_options()
  end

  defp normalize_repository_options(repositories) when is_list(repositories) do
    repositories
    |> Enum.map(&normalize_repository_option/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_repository_options(_repositories), do: []

  defp normalize_repository_option(repository) when is_binary(repository) do
    repository
    |> normalize_optional_string()
    |> case do
      nil -> nil
      full_name -> build_repository_option(full_name, "repo:#{full_name}")
    end
  end

  defp normalize_repository_option(repository) when is_map(repository) do
    full_name =
      repository
      |> map_get(:full_name, "full_name")
      |> normalize_optional_string()
      |> case do
        nil ->
          owner =
            repository
            |> map_get(:owner, "owner")
            |> normalize_owner(repository)

          name =
            repository
            |> map_get(:name, "name")
            |> normalize_optional_string()

          if owner && name, do: "#{owner}/#{name}", else: nil

        normalized_full_name ->
          normalized_full_name
      end

    repository_id =
      repository
      |> map_get(:id, "id")
      |> normalize_optional_string()
      |> case do
        nil ->
          repository
          |> map_get(:node_id, "node_id")
          |> normalize_optional_string()

        normalized_id ->
          normalized_id
      end

    build_repository_option(full_name, repository_id || "repo:#{full_name}")
  end

  defp normalize_repository_option(_repository), do: nil

  defp normalize_owner(repository_owner, repository) do
    case normalize_optional_string(repository_owner) do
      nil ->
        repository
        |> map_get(:owner, "owner", %{})
        |> case do
          %{} = owner_map ->
            owner_map
            |> map_get(:login, "login")
            |> normalize_optional_string()

          _other ->
            nil
        end

      owner ->
        owner
    end
  end

  defp build_repository_option(nil, _repository_id), do: nil

  defp build_repository_option(full_name, repository_id) do
    case String.split(full_name, "/", parts: 2) do
      [owner, name] when owner != "" and name != "" ->
        %{
          id: repository_id,
          full_name: full_name,
          owner: owner,
          name: name
        }

      _other ->
        nil
    end
  end

  defp sort_repository_options(repositories) when is_list(repositories) do
    Enum.sort_by(repositories, fn repository ->
      {repository.full_name, repository.id}
    end)
  end

  defp serialize_repository_option(repository_option) do
    %{
      "id" => Map.get(repository_option, :id),
      "full_name" => Map.get(repository_option, :full_name),
      "owner" => Map.get(repository_option, :owner),
      "name" => Map.get(repository_option, :name)
    }
  end

  defp installation_payload(payload) when is_map(payload) do
    payload
    |> map_get(:installation, "installation", %{})
    |> normalize_keyed_map()
  end

  defp installation_payload(_payload), do: %{}

  defp normalize_installation_id(nil), do: nil

  defp normalize_installation_id(value) when is_integer(value) and value > 0,
    do: value

  defp normalize_installation_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed_value, ""} when parsed_value > 0 -> parsed_value
      _other -> nil
    end
  end

  defp normalize_installation_id(_value), do: nil

  defp fetch_step_state(onboarding_state, onboarding_step) when is_map(onboarding_state) do
    step_key = Integer.to_string(onboarding_step)
    Map.get(onboarding_state, step_key) || Map.get(onboarding_state, onboarding_step) || %{}
  end

  defp fetch_step_state(_onboarding_state, _onboarding_step), do: %{}

  defp put_step_state(onboarding_state, onboarding_step, step_state) when is_map(onboarding_state) do
    onboarding_state
    |> Map.delete(onboarding_step)
    |> Map.put(Integer.to_string(onboarding_step), step_state)
  end

  defp put_step_state(_onboarding_state, onboarding_step, step_state) do
    %{Integer.to_string(onboarding_step) => step_state}
  end

  defp normalize_paths(paths) when is_list(paths), do: paths
  defp normalize_paths(_paths), do: []

  defp normalize_keyed_map(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {key, value}, acc when is_atom(key) ->
        Map.put(acc, Atom.to_string(key), value)

      {key, value}, acc when is_binary(key) ->
        Map.put(acc, key, value)

      {key, value}, acc ->
        Map.put(acc, to_string(key), value)
    end)
  end

  defp normalize_keyed_map(_map), do: %{}

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

  defp normalize_detail(detail) when is_binary(detail) and detail != "", do: detail
  defp normalize_detail(detail), do: inspect(detail)

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default
end
