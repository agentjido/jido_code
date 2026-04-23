defmodule JidoCode.Setup.GitHubRepositoryListing do
  # covers: setup.onboarding.deferred_integrations
  # covers: setup.onboarding.github_repository_selection_persisted_metadata
  @moduledoc """
  Lists repositories accessible through validated GitHub credentials for setup step 7.
  """

  @default_fetcher_remediation "Re-run GitHub credential validation in step 4 and retry repository refresh."
  @default_missing_prerequisite_remediation "Complete GitHub setup in step 4 before importing a project."
  @default_no_access_remediation "Grant repository access for the configured GitHub credentials and refresh the list."
  @default_installation_stale_remediation "Retry repository refresh in step 7 after resolving GitHub App installation sync failures."
  @installation_revoked_error_type "github_installation_access_revoked"
  @installation_stale_error_type "github_installation_sync_stale"

  @type status :: :ready | :blocked

  @type repository_option :: %{
          id: String.t(),
          full_name: String.t(),
          owner: String.t(),
          name: String.t()
        }

  @type report :: %{
          checked_at: DateTime.t(),
          status: status(),
          repositories: [repository_option()],
          detail: String.t(),
          remediation: String.t(),
          error_type: String.t() | nil
        }

  @spec run(report() | map() | nil, map() | nil) :: report()
  def run(previous_state \\ nil, onboarding_state \\ %{}) do
    checked_at = DateTime.utc_now() |> DateTime.truncate(:second)
    previous_report = from_state(previous_state) || ready_report(checked_at, [])

    fetcher =
      Application.get_env(
        :jido_code,
        :setup_github_repository_fetcher,
        &__MODULE__.default_fetcher/1
      )

    fetcher
    |> safe_invoke_fetcher(%{
      checked_at: checked_at,
      onboarding_state: onboarding_state,
      previous_report: previous_report
    })
    |> normalize_report(checked_at)
    |> preserve_previous_repositories(previous_report)
  end

  @spec blocked?(report() | nil) :: boolean()
  def blocked?(%{status: :ready}), do: false
  def blocked?(_), do: true

  @spec repository_options(report() | nil) :: [repository_option()]
  def repository_options(%{repositories: repositories}) when is_list(repositories),
    do: repositories

  def repository_options(_report), do: []

  @spec repository_full_names(report() | nil) :: [String.t()]
  def repository_full_names(report) do
    report
    |> repository_options()
    |> Enum.map(&Map.get(&1, :full_name))
    |> Enum.reject(&is_nil/1)
  end

  @spec serialize_for_state(report() | nil) :: map()
  def serialize_for_state(%{
        checked_at: checked_at,
        status: status,
        repositories: repositories,
        detail: detail,
        remediation: remediation,
        error_type: error_type
      }) do
    %{
      "checked_at" => DateTime.to_iso8601(checked_at),
      "status" => Atom.to_string(status),
      "repositories" => Enum.map(repositories, &serialize_repository_option/1),
      "detail" => detail,
      "remediation" => remediation,
      "error_type" => error_type
    }
  end

  def serialize_for_state(_report), do: %{}

  @spec from_state(report() | map() | nil) :: report() | nil
  def from_state(nil), do: nil

  def from_state(state) when is_map(state) do
    checked_at =
      state
      |> map_get(:checked_at, "checked_at")
      |> normalize_datetime(DateTime.utc_now() |> DateTime.truncate(:second))

    repositories =
      state
      |> map_get(:repositories, "repositories", [])
      |> normalize_repository_options()
      |> uniq_repository_options()
      |> Enum.sort_by(fn repository -> {repository.full_name, repository.id} end)

    status =
      state
      |> map_get(:status, "status", nil)
      |> normalize_status(default_status(repositories))

    detail =
      state
      |> map_get(:detail, "detail", nil)
      |> normalize_detail(status)

    remediation =
      state
      |> map_get(:remediation, "remediation", nil)
      |> normalize_remediation(status)

    error_type =
      state
      |> map_get(:error_type, "error_type", nil)
      |> normalize_error_type()

    normalized_status =
      if status == :ready and repositories == [] do
        :blocked
      else
        status
      end

    %{
      checked_at: checked_at,
      status: normalized_status,
      repositories: repositories,
      detail: detail,
      remediation: remediation,
      error_type: if(normalized_status == :ready, do: nil, else: error_type)
    }
  end

  def from_state(_state), do: nil

  @doc false
  def default_fetcher(%{checked_at: checked_at, onboarding_state: onboarding_state}) do
    installation_sync_state = installation_sync_state(onboarding_state)

    case installation_sync_state do
      %{status: :stale} = stale_state ->
        blocked_report(
          checked_at,
          stale_state.repositories,
          stale_state.error_type || @installation_stale_error_type,
          stale_state.detail,
          stale_state.remediation
        )

      %{status: :ready} = ready_state ->
        if ready_state.repositories == [] do
          blocked_report(
            checked_at,
            [],
            ready_state.error_type || @installation_revoked_error_type,
            ready_state.detail,
            ready_state.remediation
          )
        else
          ready_report(
            checked_at,
            ready_state.repositories,
            ready_state.detail
          )
        end

      _other ->
        default_fetcher_without_installation_override(checked_at, onboarding_state)
    end
  end

  def default_fetcher(_context) do
    blocked_report(
      DateTime.utc_now() |> DateTime.truncate(:second),
      [],
      "github_repository_fetch_context_invalid",
      "GitHub repository listing context is invalid.",
      @default_fetcher_remediation
    )
  end

  defp default_fetcher_without_installation_override(checked_at, onboarding_state) do
    github_credentials =
      onboarding_state
      |> fetch_step_state(4)
      |> map_get(:github_credentials, "github_credentials", %{})

    paths =
      github_credentials
      |> map_get(:paths, "paths", [])
      |> normalize_paths()

    cond do
      paths == [] ->
        blocked_report(
          checked_at,
          [],
          "github_repository_fetch_prerequisite_missing",
          "GitHub credentials are unavailable for repository listing.",
          @default_missing_prerequisite_remediation
        )

      true ->
        ready_paths = Enum.filter(paths, &path_access_confirmed?/1)

        repositories =
          ready_paths
          |> Enum.flat_map(fn path ->
            path
            |> map_get(:repositories, "repositories", [])
            |> normalize_repository_options()
          end)
          |> uniq_repository_options()
          |> Enum.sort_by(fn repository -> {repository.full_name, repository.id} end)

        cond do
          ready_paths == [] ->
            blocked_paths_report(checked_at, paths)

          repositories == [] ->
            blocked_report(
              checked_at,
              [],
              "github_repository_fetch_empty",
              "GitHub repository listing returned no accessible repositories.",
              @default_no_access_remediation
            )

          true ->
            ready_report(
              checked_at,
              repositories,
              "Accessible repositories were fetched for import selection."
            )
        end
    end
  end

  defp safe_invoke_fetcher(fetcher, context) when is_function(fetcher, 1) do
    try do
      case fetcher.(context) do
        %{} = report -> {:ok, report}
        {:ok, %{} = report} -> {:ok, report}
        {:error, reason} -> {:error, reason}
        other -> {:error, {:invalid_fetcher_result, other}}
      end
    rescue
      exception ->
        {:error, {:fetcher_exception, Exception.message(exception)}}
    catch
      kind, reason ->
        {:error, {:fetcher_throw, {kind, reason}}}
    end
  end

  defp safe_invoke_fetcher(_fetcher, _context), do: {:error, :invalid_fetcher}

  defp normalize_report({:ok, report}, checked_at) do
    case from_state(report) do
      nil ->
        blocked_report(
          checked_at,
          [],
          "github_repository_fetch_invalid_report",
          "GitHub repository listing returned an invalid report.",
          @default_fetcher_remediation
        )

      normalized_report ->
        normalized_report
    end
  end

  defp normalize_report({:error, {error_type, detail}}, checked_at) do
    blocked_report(
      checked_at,
      [],
      normalize_error_type(error_type) || "github_repository_fetch_failed",
      normalize_error_detail(detail),
      @default_fetcher_remediation
    )
  end

  defp normalize_report({:error, reason}, checked_at) do
    blocked_report(
      checked_at,
      [],
      "github_repository_fetch_failed",
      "GitHub repository listing failed (#{inspect(reason)}).",
      @default_fetcher_remediation
    )
  end

  defp preserve_previous_repositories(report, previous_report) do
    previous_repositories = repository_options(previous_report)

    if blocked?(report) and report.repositories == [] and previous_repositories != [] and
         not authoritative_empty_listing?(report.error_type) do
      %{
        report
        | repositories: previous_repositories,
          detail: "#{report.detail} Previously listed repositories were preserved for retry."
      }
    else
      report
    end
  end

  defp ready_report(
         checked_at,
         repositories,
         detail \\ "Accessible repositories are ready for import selection."
       ) do
    %{
      checked_at: checked_at,
      status: :ready,
      repositories: repositories,
      detail: detail,
      remediation: "Repository listing is ready.",
      error_type: nil
    }
  end

  defp blocked_report(checked_at, repositories, error_type, detail, remediation) do
    %{
      checked_at: checked_at,
      status: :blocked,
      repositories: repositories,
      detail: detail,
      remediation: remediation,
      error_type: error_type
    }
  end

  defp blocked_paths_report(checked_at, paths) do
    blocked_report(
      checked_at,
      [],
      blocked_paths_error_type(paths),
      blocked_paths_detail(paths),
      blocked_paths_remediation(paths)
    )
  end

  defp blocked_paths_error_type(paths) do
    path_error_types =
      paths
      |> Enum.map(fn path ->
        path
        |> map_get(:error_type, "error_type", nil)
        |> normalize_error_type()
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    cond do
      Enum.all?(paths, &path_not_configured?/1) ->
        "github_repository_fetch_not_configured"

      length(path_error_types) == 1 ->
        hd(path_error_types)

      true ->
        "github_repository_fetch_access_unconfirmed"
    end
  end

  defp blocked_paths_detail(paths) do
    base_detail = "GitHub credential validation has no confirmed repository access paths."

    path_details =
      paths
      |> Enum.map(&blocked_path_detail/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case path_details do
      [] -> base_detail
      details -> "#{base_detail} #{Enum.join(details, " ")}"
    end
  end

  defp blocked_path_detail(path) when is_map(path) do
    name =
      path
      |> map_get(:name, "name", nil)
      |> normalize_optional_string()

    detail =
      path
      |> map_get(:detail, "detail", nil)
      |> normalize_optional_string()

    case {name, detail} do
      {nil, nil} -> nil
      {nil, normalized_detail} -> normalized_detail
      {_name, nil} -> nil
      {normalized_name, normalized_detail} -> "#{normalized_name}: #{normalized_detail}"
    end
  end

  defp blocked_path_detail(_path), do: nil

  defp blocked_paths_remediation(paths) do
    path_remediations =
      paths
      |> Enum.map(fn path ->
        path
        |> map_get(:remediation, "remediation", nil)
        |> normalize_optional_string()
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case path_remediations do
      [] -> @default_no_access_remediation
      [remediation] -> remediation
      remediations -> Enum.join(remediations, " ")
    end
  end

  defp default_status(repositories) when repositories == [], do: :blocked
  defp default_status(_repositories), do: :ready

  defp normalize_status(:ready, _default), do: :ready
  defp normalize_status("ready", _default), do: :ready
  defp normalize_status(:blocked, _default), do: :blocked
  defp normalize_status("blocked", _default), do: :blocked
  defp normalize_status(_status, default), do: default

  defp normalize_detail(detail, _status) when is_binary(detail) and detail != "", do: detail

  defp normalize_detail(_detail, :ready),
    do: "Accessible repositories are ready for import selection."

  defp normalize_detail(_detail, :blocked),
    do: "GitHub repository listing is blocked until credential access is confirmed."

  defp normalize_remediation(remediation, _status)
       when is_binary(remediation) and remediation != "",
       do: remediation

  defp normalize_remediation(_remediation, :ready), do: "Repository listing is ready."
  defp normalize_remediation(_remediation, :blocked), do: @default_fetcher_remediation

  defp normalize_error_type(error_type) when is_atom(error_type), do: Atom.to_string(error_type)

  defp normalize_error_type(error_type) when is_binary(error_type) do
    case String.trim(error_type) do
      "" -> nil
      normalized_error_type -> normalized_error_type
    end
  end

  defp normalize_error_type(_error_type), do: nil

  defp normalize_error_detail(detail) when is_binary(detail) and detail != "", do: detail
  defp normalize_error_detail(detail), do: inspect(detail)

  defp path_access_confirmed?(path) when is_map(path) do
    status =
      path
      |> map_get(:status, "status", nil)
      |> normalize_status(:blocked)

    repository_access =
      path
      |> map_get(:repository_access, "repository_access", nil)
      |> normalize_repository_access()

    status == :ready and repository_access in [:confirmed, :unknown]
  end

  defp path_access_confirmed?(_path), do: false

  defp path_not_configured?(path) when is_map(path) do
    path
    |> map_get(:status, "status", nil)
    |> normalize_optional_string()
    |> case do
      "not_configured" -> true
      _other -> false
    end
  end

  defp path_not_configured?(_path), do: false

  defp normalize_repository_access(:confirmed), do: :confirmed
  defp normalize_repository_access("confirmed"), do: :confirmed
  defp normalize_repository_access(:unconfirmed), do: :unconfirmed
  defp normalize_repository_access("unconfirmed"), do: :unconfirmed
  defp normalize_repository_access(nil), do: :unknown
  defp normalize_repository_access(_repository_access), do: :unknown

  defp serialize_repository_option(repository_option) do
    %{
      "id" => Map.get(repository_option, :id),
      "full_name" => Map.get(repository_option, :full_name),
      "owner" => Map.get(repository_option, :owner),
      "name" => Map.get(repository_option, :name)
    }
  end

  defp uniq_repository_options(repository_options) when is_list(repository_options) do
    Enum.uniq_by(repository_options, fn repository_option -> repository_option.full_name end)
  end

  defp normalize_paths(paths) when is_list(paths), do: paths
  defp normalize_paths(_paths), do: []

  defp normalize_repository_options(repositories) when is_list(repositories) do
    repositories
    |> Enum.map(&normalize_repository_option/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_repository_options(_repositories), do: []

  defp normalize_repository_option(repository) when is_binary(repository) do
    full_name =
      repository
      |> String.trim()
      |> case do
        "" -> nil
        normalized_full_name -> normalized_full_name
      end

    build_repository_option(full_name, "repo:#{full_name}")
  end

  defp normalize_repository_option(repository) when is_map(repository) do
    full_name =
      repository
      |> map_get(:full_name, "full_name")
      |> normalize_optional_string()
      |> case do
        nil ->
          owner = repository |> map_get(:owner, "owner") |> normalize_optional_string()
          name = repository |> map_get(:name, "name") |> normalize_optional_string()

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

        normalized_repository_id ->
          normalized_repository_id
      end

    build_repository_option(full_name, repository_id || "repo:#{full_name}")
  end

  defp normalize_repository_option(_repository), do: nil

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

  defp normalize_datetime(%DateTime{} = datetime, _default), do: datetime

  defp normalize_datetime(datetime, default) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, parsed_datetime, _offset} -> parsed_datetime
      _other -> default
    end
  end

  defp normalize_datetime(_datetime, default), do: default

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

  defp installation_sync_state(onboarding_state) when is_map(onboarding_state) do
    onboarding_state
    |> fetch_step_state(7)
    |> map_get(:installation_sync, "installation_sync", %{})
    |> normalize_installation_sync_state()
  end

  defp installation_sync_state(_onboarding_state), do: nil

  defp normalize_installation_sync_state(%{} = installation_sync) do
    status =
      installation_sync
      |> map_get(:status, "status", nil)
      |> normalize_installation_sync_status()

    repositories =
      installation_sync
      |> map_get(:accessible_repositories, "accessible_repositories", [])
      |> normalize_repository_options()
      |> uniq_repository_options()
      |> Enum.sort_by(fn repository -> {repository.full_name, repository.id} end)

    detail =
      installation_sync
      |> map_get(:detail, "detail", nil)
      |> normalize_optional_string()

    remediation =
      installation_sync
      |> map_get(:remediation, "remediation", nil)
      |> normalize_optional_string()

    error_type =
      installation_sync
      |> map_get(:error_type, "error_type", nil)
      |> normalize_error_type()

    case status do
      nil ->
        nil

      normalized_status ->
        %{
          status: normalized_status,
          repositories: repositories,
          detail:
            detail ||
              "Repository availability was updated from GitHub installation sync metadata.",
          remediation:
            remediation ||
              if(normalized_status == :stale,
                do: @default_installation_stale_remediation,
                else: "Repository listing is ready."
              ),
          error_type:
            if(normalized_status == :ready, do: error_type, else: error_type || @installation_stale_error_type)
        }
    end
  end

  defp normalize_installation_sync_state(_installation_sync), do: nil

  defp normalize_installation_sync_status(:ready), do: :ready
  defp normalize_installation_sync_status("ready"), do: :ready
  defp normalize_installation_sync_status(:stale), do: :stale
  defp normalize_installation_sync_status("stale"), do: :stale
  defp normalize_installation_sync_status(_status), do: nil

  defp authoritative_empty_listing?(@installation_revoked_error_type), do: true
  defp authoritative_empty_listing?(_error_type), do: false

  defp fetch_step_state(onboarding_state, onboarding_step) when is_map(onboarding_state) do
    step_key = Integer.to_string(onboarding_step)
    Map.get(onboarding_state, step_key) || Map.get(onboarding_state, onboarding_step) || %{}
  end

  defp fetch_step_state(_onboarding_state, _onboarding_step), do: %{}

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
