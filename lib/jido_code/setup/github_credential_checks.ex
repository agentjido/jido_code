defmodule JidoCode.Setup.GitHubCredentialChecks do
  @moduledoc """
  Validates GitHub integration credentials before setup step 4 can advance.
  """

  # covers: auth.github_integration.readiness_feedback
  # covers: auth.github_integration.github_app_preferred
  # covers: auth.github_integration.non_blocking_local_auth
  # covers: auth.github_service_credentials.login_service_split
  # covers: source.provider_adapter.github_adapter

  alias JidoCode.SourceProviders

  @default_checker_remediation "Verify GitHub credential checker configuration and retry setup."
  @default_repo_access_remediation "Grant repository access for this owner context and retry validation."
  @default_installation_access_remediation "Grant GitHub App installation access to expected repositories and retry validation."

  @type status :: :ready | :invalid | :not_configured
  @type path :: :github_app | :pat
  @type repository_access :: :confirmed | :unconfirmed
  @type readiness_status :: :ready | :blocked

  @type integration_health :: %{
          readiness_status: readiness_status(),
          github_app_status: status(),
          github_app_ready: boolean(),
          github_app_repository_access: repository_access(),
          expected_repositories: [String.t()],
          missing_repositories: [String.t()],
          last_checked_at: DateTime.t()
        }

  @type path_result :: %{
          path: path(),
          name: String.t(),
          status: status(),
          previous_status: status(),
          transition: String.t(),
          owner_context: String.t() | nil,
          repository_access: repository_access(),
          repositories: [String.t()],
          expected_repositories: [String.t()],
          missing_repositories: [String.t()],
          detail: String.t(),
          remediation: String.t(),
          error_type: String.t() | nil,
          validated_at: DateTime.t() | nil,
          checked_at: DateTime.t()
        }

  @type report :: %{
          checked_at: DateTime.t(),
          status: readiness_status(),
          owner_context: String.t() | nil,
          paths: [path_result()],
          integration_health: integration_health()
        }

  @spec run(map() | nil, String.t() | nil) :: report()
  def run(previous_state \\ nil, owner_context \\ nil) do
    checked_at = DateTime.utc_now() |> DateTime.truncate(:second)
    previous_statuses = previous_statuses(previous_state)
    owner_context = normalize_owner_context(owner_context, previous_owner_context(previous_state))

    checker =
      Application.get_env(
        :jido_code,
        :setup_github_credential_checker,
        &__MODULE__.default_checker/1
      )

    checker
    |> safe_invoke_checker(%{
      checked_at: checked_at,
      previous_statuses: previous_statuses,
      owner_context: owner_context
    })
    |> normalize_report(checked_at, previous_statuses, owner_context)
    |> with_integration_health()
  end

  @spec blocked?(report()) :: boolean()
  def blocked?(%{paths: paths}) when is_list(paths) do
    not Enum.any?(paths, &ready_path?/1)
  end

  def blocked?(_), do: true

  @spec blocked_paths(report()) :: [path_result()]
  def blocked_paths(%{paths: paths}) when is_list(paths) do
    Enum.filter(paths, fn path_result -> not ready_path?(path_result) end)
  end

  def blocked_paths(_), do: []

  @spec serialize_for_state(report()) :: map()
  def serialize_for_state(
        %{checked_at: checked_at, status: status, owner_context: owner_context, paths: paths} =
          report
      )
      when is_list(paths) do
    integration_health =
      report
      |> with_integration_health()
      |> Map.get(:integration_health)

    %{
      "checked_at" => DateTime.to_iso8601(checked_at),
      "status" => Atom.to_string(status),
      "owner_context" => owner_context,
      "integration_health" => serialize_integration_health(integration_health),
      "paths" =>
        Enum.map(paths, fn path_result ->
          %{
            "path" => Atom.to_string(path_result.path),
            "name" => path_result.name,
            "status" => Atom.to_string(path_result.status),
            "previous_status" => Atom.to_string(path_result.previous_status),
            "transition" => path_result.transition,
            "owner_context" => path_result.owner_context,
            "repository_access" => Atom.to_string(path_result.repository_access),
            "repositories" => path_result.repositories,
            "expected_repositories" => path_result.expected_repositories,
            "missing_repositories" => path_result.missing_repositories,
            "detail" => path_result.detail,
            "remediation" => path_result.remediation,
            "error_type" => path_result.error_type,
            "validated_at" => format_datetime(path_result.validated_at),
            "checked_at" => DateTime.to_iso8601(path_result.checked_at)
          }
        end)
    }
  end

  def serialize_for_state(_), do: %{}

  @spec from_state(map() | nil) :: report() | nil
  def from_state(nil), do: nil

  def from_state(state) when is_map(state) do
    checked_at =
      state
      |> map_get(:checked_at, "checked_at")
      |> normalize_checked_at(DateTime.utc_now() |> DateTime.truncate(:second))

    owner_context =
      state
      |> map_get(:owner_context, "owner_context")
      |> normalize_owner_context(nil)

    paths =
      state
      |> map_get(:paths, "paths", [])
      |> normalize_paths(checked_at, %{}, owner_context)

    if paths == [] do
      nil
    else
      integration_health =
        state
        |> map_get(:integration_health, "integration_health", nil)
        |> integration_health_from_state(checked_at, paths)

      %{
        checked_at: checked_at,
        owner_context: owner_context,
        paths: paths,
        status:
          state
          |> map_get(:status, "status", nil)
          |> normalize_report_status(overall_status(paths)),
        integration_health: integration_health
      }
    end
  end

  def from_state(_), do: nil

  @doc false
  def default_checker(%{
        checked_at: checked_at,
        previous_statuses: previous_statuses,
        owner_context: owner_context
      })
      when is_map(previous_statuses) do
    path_results =
      Enum.map(path_definitions(), fn definition ->
        previous_status = Map.get(previous_statuses, definition.path, :not_configured)

        build_default_path_result(
          definition,
          checked_at,
          owner_context,
          previous_status
        )
      end)

    %{
      checked_at: checked_at,
      status: overall_status(path_results),
      owner_context: owner_context,
      paths: path_results
    }
  end

  defp build_default_path_result(
         definition,
         checked_at,
         owner_context,
         previous_status
       ) do
    repository_result = fetch_repositories(definition, owner_context)
    repositories = repository_names(repository_result)
    expected_repositories = fetch_expected_repositories(definition)
    missing_repositories = missing_expected_repositories(expected_repositories, repositories)

    cond do
      credentials_present?(definition) and owner_context == nil ->
        path_result(
          definition,
          :invalid,
          previous_status,
          owner_context,
          :unconfirmed,
          repositories,
          expected_repositories,
          missing_repositories,
          "Cannot verify repository access because owner context is missing.",
          @default_repo_access_remediation,
          definition.owner_context_error_type,
          nil,
          checked_at
        )

      credentials_present?(definition) and match?({:error, _failure}, repository_result) ->
        %{detail: detail, remediation: remediation, error_type: error_type} =
          normalize_repository_fetch_failure(repository_result)

        path_result(
          definition,
          :invalid,
          previous_status,
          owner_context,
          :unconfirmed,
          repositories,
          expected_repositories,
          missing_repositories,
          detail,
          remediation,
          error_type,
          nil,
          checked_at
        )

      credentials_present?(definition) and repositories == [] ->
        path_result(
          definition,
          :invalid,
          previous_status,
          owner_context,
          :unconfirmed,
          repositories,
          expected_repositories,
          missing_repositories,
          "Credential path is configured but did not confirm accessible repositories for owner context.",
          @default_repo_access_remediation,
          definition.repo_access_error_type,
          nil,
          checked_at
        )

      credentials_present?(definition) and missing_repositories != [] ->
        path_result(
          definition,
          :invalid,
          previous_status,
          owner_context,
          :unconfirmed,
          repositories,
          expected_repositories,
          missing_repositories,
          "Credential path is configured but GitHub App installation access is missing expected repositories: #{Enum.join(missing_repositories, ", ")}.",
          Map.get(definition, :installation_access_remediation) ||
            @default_installation_access_remediation,
          Map.get(definition, :installation_access_error_type) ||
            definition.repo_access_error_type,
          nil,
          checked_at
        )

      credentials_present?(definition) ->
        path_result(
          definition,
          :ready,
          previous_status,
          owner_context,
          :confirmed,
          repositories,
          expected_repositories,
          missing_repositories,
          "Credential path is configured and confirms repository access for owner context.",
          "Credential path is ready.",
          nil,
          checked_at,
          checked_at
        )

      true ->
        path_result(
          definition,
          :not_configured,
          previous_status,
          owner_context,
          :unconfirmed,
          repositories,
          expected_repositories,
          missing_repositories,
          definition.not_configured_detail,
          definition.not_configured_remediation,
          definition.not_configured_error_type,
          nil,
          checked_at
        )
    end
  end

  defp path_result(
         definition,
         status,
         previous_status,
         owner_context,
         repository_access,
         repositories,
         expected_repositories,
         missing_repositories,
         detail,
         remediation,
         error_type,
         validated_at,
         checked_at
       ) do
    %{
      path: definition.path,
      name: definition.name,
      status: status,
      previous_status: previous_status,
      transition: transition_label(previous_status, status),
      owner_context: owner_context,
      repository_access: repository_access,
      repositories: repositories,
      expected_repositories: expected_repositories,
      missing_repositories: missing_repositories,
      detail: detail,
      remediation: remediation,
      error_type: error_type,
      validated_at: validated_at,
      checked_at: checked_at
    }
  end

  defp safe_invoke_checker(checker, context) when is_function(checker, 1) do
    try do
      checker.(context)
    rescue
      exception ->
        {:error, {:checker_exception, Exception.message(exception)}}
    catch
      kind, reason ->
        {:error, {:checker_throw, {kind, reason}}}
    end
  end

  defp safe_invoke_checker(_checker, _context), do: {:error, :invalid_checker}

  defp normalize_report(
         %{paths: paths} = report,
         default_checked_at,
         previous_statuses,
         default_owner_context
       )
       when is_list(paths) do
    checked_at =
      report
      |> map_get(:checked_at, "checked_at")
      |> normalize_checked_at(default_checked_at)

    owner_context =
      report
      |> map_get(:owner_context, "owner_context", default_owner_context)
      |> normalize_owner_context(default_owner_context)

    normalized_paths = normalize_paths(paths, checked_at, previous_statuses, owner_context)

    %{
      checked_at: checked_at,
      owner_context: owner_context,
      paths: normalized_paths,
      status:
        report
        |> map_get(:status, "status", nil)
        |> normalize_report_status(overall_status(normalized_paths))
    }
  end

  defp normalize_report(paths, default_checked_at, previous_statuses, default_owner_context)
       when is_list(paths) do
    normalize_report(
      %{paths: paths, owner_context: default_owner_context},
      default_checked_at,
      previous_statuses,
      default_owner_context
    )
  end

  defp normalize_report(
         {:error, reason},
         default_checked_at,
         _previous_statuses,
         default_owner_context
       ) do
    checker_error_report(reason, default_checked_at, default_owner_context)
  end

  defp normalize_report(other, default_checked_at, _previous_statuses, default_owner_context) do
    checker_error_report(
      {:invalid_checker_result, other},
      default_checked_at,
      default_owner_context
    )
  end

  defp checker_error_report(reason, checked_at, owner_context) do
    paths =
      Enum.map(path_definitions(), fn definition ->
        path_result(
          definition,
          :invalid,
          :not_configured,
          owner_context,
          :unconfirmed,
          [],
          fetch_expected_repositories(definition),
          [],
          "Unable to verify GitHub credential path: #{inspect(reason)}",
          @default_checker_remediation,
          "github_credential_checker_failed",
          nil,
          checked_at
        )
      end)

    %{
      checked_at: checked_at,
      owner_context: owner_context,
      status: :blocked,
      paths: paths
    }
  end

  defp normalize_paths(paths, checked_at, previous_statuses, owner_context) do
    paths
    |> Enum.with_index()
    |> Enum.map(fn {path_result, index} ->
      normalize_path_result(path_result, checked_at, previous_statuses, owner_context, index)
    end)
  end

  defp normalize_path_result(
         path_result,
         default_checked_at,
         previous_statuses,
         owner_context,
         index
       )
       when is_map(path_result) do
    definition = default_path_definition(index)

    path =
      path_result
      |> map_get(:path, "path", definition.path)
      |> normalize_path(definition.path)

    path_definition = path_definition(path)
    status = path_result |> map_get(:status, "status", nil) |> normalize_status(:not_configured)

    previous_status =
      path_result
      |> map_get(
        :previous_status,
        "previous_status",
        Map.get(previous_statuses, path, :not_configured)
      )
      |> normalize_status(Map.get(previous_statuses, path, :not_configured))

    normalized_owner_context =
      path_result
      |> map_get(:owner_context, "owner_context", owner_context)
      |> normalize_owner_context(owner_context)

    repository_access =
      path_result
      |> map_get(:repository_access, "repository_access", nil)
      |> normalize_repository_access(default_repository_access(status))

    repositories =
      path_result
      |> map_get(:repositories, "repositories", [])
      |> normalize_repositories()

    expected_repositories =
      path_result
      |> map_get(
        :expected_repositories,
        "expected_repositories",
        fetch_expected_repositories(path_definition)
      )
      |> normalize_repositories()

    default_missing_repositories =
      missing_expected_repositories(expected_repositories, repositories)

    missing_repositories =
      path_result
      |> map_get(:missing_repositories, "missing_repositories", default_missing_repositories)
      |> normalize_repositories()

    %{
      path: path,
      name:
        path_result
        |> map_get(:name, "name", path_definition.name)
        |> normalize_text(path_definition.name),
      status: status,
      previous_status: previous_status,
      transition:
        path_result
        |> map_get(:transition, "transition", nil)
        |> normalize_text(transition_label(previous_status, status)),
      owner_context: normalized_owner_context,
      repository_access: repository_access,
      repositories: repositories,
      expected_repositories: expected_repositories,
      missing_repositories: missing_repositories,
      detail:
        path_result
        |> map_get(:detail, "detail", nil)
        |> normalize_text(default_detail(path_definition, status)),
      remediation:
        path_result
        |> map_get(:remediation, "remediation", nil)
        |> normalize_text(default_remediation(path_definition, status)),
      error_type:
        path_result
        |> map_get(:error_type, "error_type", nil)
        |> normalize_error_type(default_error_type(path_definition, status)),
      validated_at:
        path_result
        |> map_get(:validated_at, "validated_at")
        |> normalize_validated_at(status, default_checked_at),
      checked_at:
        path_result
        |> map_get(:checked_at, "checked_at")
        |> normalize_checked_at(default_checked_at)
    }
  end

  defp normalize_path_result(
         _path_result,
         default_checked_at,
         previous_statuses,
         owner_context,
         index
       ) do
    definition = default_path_definition(index)
    previous_status = Map.get(previous_statuses, definition.path, :not_configured)

    %{
      path: definition.path,
      name: definition.name,
      status: :invalid,
      previous_status: previous_status,
      transition: transition_label(previous_status, :invalid),
      owner_context: owner_context,
      repository_access: :unconfirmed,
      repositories: [],
      expected_repositories: fetch_expected_repositories(definition),
      missing_repositories: [],
      detail: "GitHub credential check result was not a map.",
      remediation: @default_checker_remediation,
      error_type: "github_credential_invalid_result",
      validated_at: nil,
      checked_at: default_checked_at
    }
  end

  defp path_definitions do
    source_provider_adapter().path_definitions()
  end

  defp path_definition(path) do
    Enum.find(path_definitions(), fn definition -> definition.path == path end) ||
      default_path_definition(0)
  end

  defp default_path_definition(index) do
    definitions = path_definitions()
    Enum.at(definitions, index, hd(definitions))
  end

  defp credentials_present?(definition) do
    definition
    |> credential_values()
    |> Enum.all?(fn value -> value != nil end)
  end

  defp credential_values(definition) do
    definition
    |> Map.get(:credential_keys, [])
    |> Enum.map(fn credential ->
      case source_provider_adapter().resolve_service_credential(credential) do
        {:ok, value, _diagnostics} -> value
        {:error, _status, _diagnostics} -> nil
      end
    end)
  end

  defp fetch_repositories(definition, owner_context) do
    configured_repositories = configured_repositories(definition)

    cond do
      configured_repositories != [] ->
        {:ok, configured_repositories}

      not credentials_present?(definition) ->
        {:ok, []}

      owner_context == nil ->
        {:ok, []}

      true ->
        fetch_repositories_from_http(definition, owner_context)
    end
  end

  defp configured_repositories(definition) do
    repo_env = Map.fetch!(definition, :repo_env)
    repo_app_env = Map.fetch!(definition, :repo_app_env)

    case repository_values(repo_env, repo_app_env) do
      [] -> repository_values("GITHUB_ACCESSIBLE_REPOS", :github_accessible_repos)
      repositories -> repositories
    end
  end

  defp fetch_repositories_from_http(definition, owner_context) do
    with token when is_binary(token) <- source_provider_adapter().resolve_api_token(definition),
         {:ok, repositories} <-
           source_provider_adapter().list_accessible_repositories(
             definition.path,
             token,
             owner_context: owner_context
           ) do
      {:ok, extract_repository_names(repositories)}
    else
      nil ->
        {:ok, []}

      {:error, _failure} = error ->
        error
    end
  end

  defp extract_repository_names(repositories) when is_list(repositories) do
    repositories
    |> Enum.map(&repository_name/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp extract_repository_names(_repositories), do: []

  defp repository_name(repository) when is_binary(repository) do
    repository
    |> String.trim()
    |> case do
      "" -> nil
      full_name -> full_name
    end
  end

  defp repository_name(repository) when is_map(repository) do
    repository
    |> map_get(:full_name, "full_name")
    |> case do
      nil ->
        owner =
          repository
          |> map_get(:owner, "owner", %{})
          |> map_get(:login, "login")
          |> normalize_owner_context(nil)

        name =
          repository
          |> map_get(:name, "name")
          |> normalize_owner_context(nil)

        if owner && name, do: "#{owner}/#{name}", else: nil

      full_name ->
        normalize_owner_context(full_name, nil)
    end
  end

  defp repository_name(_repository), do: nil

  defp repository_names({:ok, repositories}) when is_list(repositories), do: repositories
  defp repository_names({:error, _failure}), do: []
  defp repository_names(_), do: []

  defp normalize_repository_fetch_failure({:error, failure}) when is_map(failure) do
    request_intent = failure |> map_get(:request_intent, "request_intent", "github_repository_listing")
    detail = failure |> map_get(:detail, "detail", "GitHub API repository validation failed.")
    remediation = failure |> map_get(:remediation, "remediation", @default_repo_access_remediation)
    error_type = failure |> map_get(:error_type, "error_type", "github_api_request_failed")

    %{
      detail: "GitHub request intent `#{request_intent}` failed. #{normalize_text(detail, detail)}",
      remediation: normalize_text(remediation, @default_repo_access_remediation),
      error_type: normalize_error_type(error_type, "github_api_request_failed")
    }
  end

  defp normalize_repository_fetch_failure(_failure) do
    %{
      detail: "GitHub API repository validation failed.",
      remediation: @default_repo_access_remediation,
      error_type: "github_api_request_failed"
    }
  end

  defp repository_values(env_key, app_env_key) do
    env_key
    |> System.get_env()
    |> normalize_repositories()
    |> case do
      [] ->
        Application.get_env(:jido_code, app_env_key)
        |> normalize_repositories()

      repositories ->
        repositories
    end
  end

  defp fetch_expected_repositories(definition) do
    if Map.get(definition, :tracks_expected_repositories, false) do
      configured_expected_repositories =
        case {Map.get(definition, :expected_repo_env), Map.get(definition, :expected_repo_app_env)} do
          {env_key, app_env_key} when is_binary(env_key) and is_atom(app_env_key) ->
            repository_values(env_key, app_env_key)

          _other ->
            []
        end

      case configured_expected_repositories do
        [] -> repository_values("GITHUB_EXPECTED_REPOS", :github_expected_repos)
        repositories -> repositories
      end
    else
      []
    end
  end

  defp missing_expected_repositories(expected_repositories, repositories) do
    Enum.reject(expected_repositories, fn expected_repository ->
      expected_repository in repositories
    end)
  end

  defp normalize_path(:github_app, _default), do: :github_app
  defp normalize_path(:pat, _default), do: :pat
  defp normalize_path("github_app", _default), do: :github_app
  defp normalize_path("pat", _default), do: :pat
  defp normalize_path(_path, default), do: default

  defp normalize_status(:ready, _default), do: :ready
  defp normalize_status(:invalid, _default), do: :invalid
  defp normalize_status(:not_configured, _default), do: :not_configured
  defp normalize_status("ready", _default), do: :ready
  defp normalize_status("invalid", _default), do: :invalid
  defp normalize_status("not_configured", _default), do: :not_configured
  defp normalize_status(_status, default), do: default

  defp normalize_repository_access(:confirmed, _default), do: :confirmed
  defp normalize_repository_access(:unconfirmed, _default), do: :unconfirmed
  defp normalize_repository_access("confirmed", _default), do: :confirmed
  defp normalize_repository_access("unconfirmed", _default), do: :unconfirmed
  defp normalize_repository_access(_repository_access, default), do: default

  defp normalize_report_status(:ready, _default), do: :ready
  defp normalize_report_status(:blocked, _default), do: :blocked
  defp normalize_report_status("ready", _default), do: :ready
  defp normalize_report_status("blocked", _default), do: :blocked
  defp normalize_report_status(_status, default), do: default

  defp normalize_validated_at(value, :ready, default_checked_at) do
    value
    |> normalize_checked_at(default_checked_at)
  end

  defp normalize_validated_at(_value, _status, _default_checked_at), do: nil

  defp normalize_checked_at(%DateTime{} = checked_at, _default), do: checked_at

  defp normalize_checked_at(checked_at, default) when is_binary(checked_at) do
    case DateTime.from_iso8601(checked_at) do
      {:ok, parsed_checked_at, _offset} -> parsed_checked_at
      {:error, _reason} -> default
    end
  end

  defp normalize_checked_at(_checked_at, default), do: default

  defp normalize_repositories(value) when is_binary(value) do
    value
    |> String.split([",", "\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_repositories(values) when is_list(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_repositories(_values), do: []

  defp map_get(map, atom_key, string_key) do
    map_get(map, atom_key, string_key, nil)
  end

  defp map_get(map, atom_key, string_key, default) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp normalize_text(value, _fallback) when is_binary(value) and byte_size(value) > 0 do
    String.trim(value)
  end

  defp normalize_text(_value, fallback), do: fallback

  defp normalize_error_type(value, _fallback) when is_binary(value) and value != "" do
    String.trim(value)
  end

  defp normalize_error_type(nil, fallback), do: fallback

  defp normalize_error_type(value, fallback) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_error_type(fallback)
  end

  defp normalize_error_type(_value, fallback), do: fallback

  defp normalize_boolean(value, _fallback) when is_boolean(value), do: value
  defp normalize_boolean(_value, fallback), do: fallback

  defp normalize_owner_context(value, fallback) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> fallback
      normalized -> normalized
    end
  end

  defp normalize_owner_context(nil, fallback), do: fallback
  defp normalize_owner_context(_value, fallback), do: fallback

  defp transition_label(previous_status, status) do
    "#{status_label(previous_status)} -> #{status_label(status)}"
  end

  defp status_label(:ready), do: "Ready"
  defp status_label(:invalid), do: "Invalid"
  defp status_label(:not_configured), do: "Not configured"

  defp default_detail(_path_definition, :ready),
    do: "Credential path is configured and confirms repository access for owner context."

  defp default_detail(path_definition, :invalid),
    do: "#{path_definition.name} validation failed for the owner context."

  defp default_detail(path_definition, :not_configured), do: path_definition.not_configured_detail

  defp default_remediation(_path_definition, :ready), do: "Credential path is ready."

  defp default_remediation(_path_definition, :invalid),
    do: @default_repo_access_remediation

  defp default_remediation(path_definition, :not_configured),
    do: path_definition.not_configured_remediation

  defp default_error_type(_path_definition, :ready), do: nil
  defp default_error_type(path_definition, :invalid), do: path_definition.repo_access_error_type

  defp default_error_type(path_definition, :not_configured),
    do: path_definition.not_configured_error_type

  defp default_repository_access(:ready), do: :confirmed
  defp default_repository_access(_status), do: :unconfirmed

  @spec integration_health(report()) :: integration_health()
  def integration_health(%{checked_at: checked_at, status: status, paths: paths})
      when is_list(paths) do
    github_app_path =
      Enum.find(paths, fn path_result -> path_result.path == :github_app end) || %{}

    expected_repositories =
      github_app_path
      |> Map.get(:expected_repositories, [])
      |> normalize_repositories()

    missing_repositories =
      github_app_path
      |> Map.get(:missing_repositories, [])
      |> normalize_repositories()

    github_app_status =
      github_app_path
      |> Map.get(:status, :not_configured)
      |> normalize_status(:not_configured)

    github_app_repository_access =
      github_app_path
      |> Map.get(:repository_access, :unconfirmed)
      |> normalize_repository_access(:unconfirmed)

    %{
      readiness_status: normalize_report_status(status, overall_status(paths)),
      github_app_status: github_app_status,
      github_app_ready:
        github_app_status == :ready and github_app_repository_access == :confirmed and
          missing_repositories == [],
      github_app_repository_access: github_app_repository_access,
      expected_repositories: expected_repositories,
      missing_repositories: missing_repositories,
      last_checked_at: checked_at
    }
  end

  def integration_health(_report) do
    checked_at = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      readiness_status: :blocked,
      github_app_status: :not_configured,
      github_app_ready: false,
      github_app_repository_access: :unconfirmed,
      expected_repositories: [],
      missing_repositories: [],
      last_checked_at: checked_at
    }
  end

  defp with_integration_health(%{checked_at: _checked_at, paths: _paths} = report) do
    Map.put(report, :integration_health, integration_health(report))
  end

  defp with_integration_health(report), do: report

  defp serialize_integration_health(%{
         readiness_status: readiness_status,
         github_app_status: github_app_status,
         github_app_ready: github_app_ready,
         github_app_repository_access: github_app_repository_access,
         expected_repositories: expected_repositories,
         missing_repositories: missing_repositories,
         last_checked_at: last_checked_at
       }) do
    %{
      "readiness_status" => Atom.to_string(readiness_status),
      "github_app_status" => Atom.to_string(github_app_status),
      "github_app_ready" => github_app_ready,
      "github_app_repository_access" => Atom.to_string(github_app_repository_access),
      "expected_repositories" => expected_repositories,
      "missing_repositories" => missing_repositories,
      "last_checked_at" => format_datetime(last_checked_at)
    }
  end

  defp serialize_integration_health(_integration_health), do: %{}

  defp integration_health_from_state(state, checked_at, paths) when is_map(state) do
    default_integration_health =
      integration_health(%{
        checked_at: checked_at,
        status: overall_status(paths),
        paths: paths
      })

    %{
      readiness_status:
        state
        |> map_get(
          :readiness_status,
          "readiness_status",
          default_integration_health.readiness_status
        )
        |> normalize_report_status(default_integration_health.readiness_status),
      github_app_status:
        state
        |> map_get(
          :github_app_status,
          "github_app_status",
          default_integration_health.github_app_status
        )
        |> normalize_status(default_integration_health.github_app_status),
      github_app_ready:
        state
        |> map_get(
          :github_app_ready,
          "github_app_ready",
          default_integration_health.github_app_ready
        )
        |> normalize_boolean(default_integration_health.github_app_ready),
      github_app_repository_access:
        state
        |> map_get(
          :github_app_repository_access,
          "github_app_repository_access",
          default_integration_health.github_app_repository_access
        )
        |> normalize_repository_access(default_integration_health.github_app_repository_access),
      expected_repositories:
        state
        |> map_get(
          :expected_repositories,
          "expected_repositories",
          default_integration_health.expected_repositories
        )
        |> normalize_repositories(),
      missing_repositories:
        state
        |> map_get(
          :missing_repositories,
          "missing_repositories",
          default_integration_health.missing_repositories
        )
        |> normalize_repositories(),
      last_checked_at:
        state
        |> map_get(:last_checked_at, "last_checked_at", checked_at)
        |> normalize_checked_at(checked_at)
    }
  end

  defp integration_health_from_state(_state, checked_at, paths) do
    integration_health(%{
      checked_at: checked_at,
      status: overall_status(paths),
      paths: paths
    })
  end

  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_datetime(_), do: nil

  defp ready_path?(path_result) do
    path_result.status == :ready and path_result.repository_access == :confirmed
  end

  defp source_provider_adapter do
    Application.get_env(:jido_code, :github_source_provider_adapter, SourceProviders.adapter!(:github))
  end

  defp previous_statuses(previous_state) do
    previous_state
    |> from_state()
    |> case do
      %{paths: paths} ->
        Enum.reduce(paths, %{}, fn path_result, acc ->
          Map.put(acc, path_result.path, path_result.status)
        end)

      _ ->
        %{}
    end
  end

  defp previous_owner_context(previous_state) do
    previous_state
    |> from_state()
    |> case do
      %{owner_context: owner_context} -> owner_context
      _ -> nil
    end
  end

  defp overall_status(paths) do
    if Enum.any?(paths, &ready_path?/1) do
      :ready
    else
      :blocked
    end
  end
end
