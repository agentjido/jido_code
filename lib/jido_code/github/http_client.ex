defmodule JidoCode.GitHub.HTTPClient do
  @moduledoc """
  GitHub HTTP integration layer built on Req with explicit timeout and retry behavior.
  """

  # covers: source.provider_adapter.github_repository_listing_fetches_full_accessible_set

  @default_base_url "https://api.github.com"
  @default_connect_timeout_ms 5_000
  @default_receive_timeout_ms 10_000
  @default_max_retries 2
  @default_retry_base_delay_ms 200
  @default_per_page 100

  @retriable_statuses [408, 409, 425, 429, 500, 502, 503, 504]

  @type auth_mode :: :github_app | :pat

  @type repository_option :: %{
          id: String.t(),
          full_name: String.t(),
          owner: String.t(),
          name: String.t()
        }

  @type reason_type ::
          :authentication
          | :forbidden
          | :not_found
          | :invalid_request
          | :retry_exhausted
          | :transport
          | :invalid_response
          | :unexpected_status

  @type typed_failure :: %{
          error_type: String.t(),
          reason_type: reason_type(),
          request_intent: String.t(),
          detail: String.t(),
          remediation: String.t(),
          method: String.t(),
          path: String.t(),
          status: integer() | nil,
          attempt_count: pos_integer(),
          max_retries: non_neg_integer()
        }

  @spec list_accessible_repositories(auth_mode(), String.t(), keyword()) ::
          {:ok, [repository_option()]} | {:error, typed_failure()}
  def list_accessible_repositories(auth_mode, token, opts \\ [])

  def list_accessible_repositories(auth_mode, token, opts)
      when auth_mode in [:github_app, :pat] and is_binary(token) do
    trimmed_token = String.trim(token)

    if trimmed_token == "" do
      {:error, missing_token_failure(auth_mode)}
    else
      request_metadata = request_metadata(auth_mode, opts)
      request_fun = Keyword.get(opts, :request_fun, &Req.request/1)

      execute_paginated_request(request_fun, trimmed_token, request_metadata)
    end
  end

  def list_accessible_repositories(_auth_mode, _token, _opts) do
    {:error,
     %{
       error_type: "github_api_invalid_credentials",
       reason_type: :invalid_request,
       request_intent: "github_repository_listing",
       detail: "GitHub API credentials are missing or invalid for repository listing.",
       remediation: "Configure a valid GitHub token and retry repository validation.",
       method: "GET",
       path: "/user/repos",
       status: nil,
       attempt_count: 1,
       max_retries: 0
     }}
  end

  defp execute_paginated_request(request_fun, token, request_metadata)
       when is_function(request_fun, 1) do
    do_execute_paginated_request(request_fun, token, request_metadata, 1, [])
  rescue
    exception ->
      {:error, map_transport_failure(exception, request_metadata)}
  catch
    kind, reason ->
      {:error,
       %{
         error_type: "github_api_transport_error",
         reason_type: :transport,
         request_intent: request_metadata.request_intent,
         detail: "GitHub API request failed due to runtime throw (#{inspect(kind)}: #{inspect(reason)}).",
         remediation: remediation_message(request_metadata.request_intent),
         method: request_metadata.method,
         path: request_metadata.path,
         status: nil,
         attempt_count: 1,
         max_retries: request_metadata.max_retries
       }}
  end

  defp do_execute_paginated_request(request_fun, token, request_metadata, page, repositories) do
    request_opts = request_options(token, request_metadata, page)

    case request_fun.(request_opts) do
      {:ok, %Req.Response{} = response} ->
        case handle_page_response(response, request_metadata) do
          {:ok, page_repositories, page_count} ->
            repositories = repositories ++ page_repositories

            if page_count < request_metadata.per_page do
              {:ok, finalize_repository_options(repositories)}
            else
              do_execute_paginated_request(
                request_fun,
                token,
                request_metadata,
                page + 1,
                repositories
              )
            end

          {:error, failure} ->
            {:error, failure}
        end

      {:error, exception} ->
        {:error, map_transport_failure(exception, request_metadata)}

      other ->
        {:error, invalid_response_failure(other, request_metadata)}
    end
  end

  defp request_options(token, request_metadata, page) do
    [
      method: :get,
      base_url: request_metadata.base_url,
      url: request_metadata.path,
      params: [page: page, per_page: request_metadata.per_page],
      headers: [
        {"accept", "application/vnd.github+json"},
        {"x-github-api-version", "2022-11-28"},
        {"authorization", "Bearer #{token}"}
      ],
      connect_options: [timeout: request_metadata.connect_timeout_ms],
      receive_timeout: request_metadata.receive_timeout_ms,
      retry: &retry_request?/2,
      retry_delay: fn retry_count ->
        request_metadata.retry_base_delay_ms * Integer.pow(2, retry_count)
      end,
      retry_log_level: false,
      max_retries: request_metadata.max_retries
    ]
  end

  defp request_metadata(auth_mode, opts) do
    max_retries = normalize_positive_integer(Keyword.get(opts, :max_retries), @default_max_retries)

    %{
      auth_mode: auth_mode,
      base_url: Keyword.get(opts, :base_url, @default_base_url),
      method: "GET",
      path: endpoint_path(auth_mode),
      request_intent: request_intent(auth_mode),
      connect_timeout_ms:
        normalize_positive_integer(
          Keyword.get(opts, :connect_timeout_ms),
          @default_connect_timeout_ms
        ),
      receive_timeout_ms:
        normalize_positive_integer(
          Keyword.get(opts, :receive_timeout_ms),
          @default_receive_timeout_ms
        ),
      retry_base_delay_ms:
        normalize_positive_integer(
          Keyword.get(opts, :retry_base_delay_ms),
          @default_retry_base_delay_ms
        ),
      per_page: normalize_page_size(Keyword.get(opts, :per_page), @default_per_page),
      max_retries: max_retries,
      attempt_count: max_retries + 1
    }
  end

  defp endpoint_path(:pat), do: "/user/repos"
  defp endpoint_path(:github_app), do: "/installation/repositories"

  defp request_intent(:pat), do: "github_pat_repository_listing"
  defp request_intent(:github_app), do: "github_app_repository_listing"

  defp handle_page_response(%Req.Response{status: status, body: body}, request_metadata)
       when status in 200..299 do
    with {:ok, repository_collection} <-
           repository_collection(request_metadata.auth_mode, body),
         {:ok, repositories} <-
           normalize_repository_options_from_collection(repository_collection) do
      {:ok, repositories, length(repository_collection)}
    else
      {:error, detail} ->
        {:error,
         %{
           error_type: "github_api_invalid_response",
           reason_type: :invalid_response,
           request_intent: request_metadata.request_intent,
           detail: detail,
           remediation: remediation_message(request_metadata.request_intent),
           method: request_metadata.method,
           path: request_metadata.path,
           status: status,
           attempt_count: request_metadata.attempt_count,
           max_retries: request_metadata.max_retries
         }}
    end
  end

  defp handle_page_response(%Req.Response{status: status} = response, request_metadata)
       when status in @retriable_statuses and request_metadata.max_retries > 0 do
    {:error, retry_exhausted_failure(response, request_metadata)}
  end

  defp handle_page_response(%Req.Response{status: 401} = response, request_metadata) do
    {:error,
     %{
       error_type: "github_api_authentication_failed",
       reason_type: :authentication,
       request_intent: request_metadata.request_intent,
       detail: response_detail(response, "GitHub API rejected credentials (401 Unauthorized)."),
       remediation: "Update GitHub credentials and retry repository validation.",
       method: request_metadata.method,
       path: request_metadata.path,
       status: response.status,
       attempt_count: 1,
       max_retries: request_metadata.max_retries
     }}
  end

  defp handle_page_response(%Req.Response{status: 403} = response, request_metadata) do
    reason_type =
      case Req.Response.get_header(response, "x-ratelimit-remaining") do
        ["0"] -> :retry_exhausted
        _other -> :forbidden
      end

    failure =
      if reason_type == :retry_exhausted and request_metadata.max_retries > 0 do
        retry_exhausted_failure(response, request_metadata)
      else
        %{
          error_type: "github_api_forbidden",
          reason_type: :forbidden,
          request_intent: request_metadata.request_intent,
          detail:
            response_detail(
              response,
              "GitHub API denied repository listing access (403 Forbidden)."
            ),
          remediation: "Grant required GitHub repository permissions for this credential and retry validation.",
          method: request_metadata.method,
          path: request_metadata.path,
          status: response.status,
          attempt_count: 1,
          max_retries: request_metadata.max_retries
        }
      end

    {:error, failure}
  end

  defp handle_page_response(%Req.Response{status: 404} = response, request_metadata) do
    {:error,
     %{
       error_type: "github_api_not_found",
       reason_type: :not_found,
       request_intent: request_metadata.request_intent,
       detail: response_detail(response, "GitHub API endpoint was not found."),
       remediation: "Verify GitHub API endpoint configuration and credential scope before retrying.",
       method: request_metadata.method,
       path: request_metadata.path,
       status: response.status,
       attempt_count: 1,
       max_retries: request_metadata.max_retries
     }}
  end

  defp handle_page_response(%Req.Response{status: status} = response, request_metadata)
       when status in [400, 422] do
    {:error,
     %{
       error_type: "github_api_invalid_request",
       reason_type: :invalid_request,
       request_intent: request_metadata.request_intent,
       detail:
         response_detail(
           response,
           "GitHub API rejected the repository listing request as invalid."
         ),
       remediation: "Review request parameters and credential context, then retry validation.",
       method: request_metadata.method,
       path: request_metadata.path,
       status: response.status,
       attempt_count: 1,
       max_retries: request_metadata.max_retries
     }}
  end

  defp handle_page_response(%Req.Response{status: status} = response, request_metadata) do
    {:error,
     %{
       error_type: "github_api_unexpected_status",
       reason_type: :unexpected_status,
       request_intent: request_metadata.request_intent,
       detail:
         response_detail(
           response,
           "GitHub API returned unexpected status #{status} for repository listing."
         ),
       remediation: remediation_message(request_metadata.request_intent),
       method: request_metadata.method,
       path: request_metadata.path,
       status: status,
       attempt_count: 1,
       max_retries: request_metadata.max_retries
     }}
  end

  defp map_transport_failure(exception, request_metadata) do
    reason =
      case exception do
        %Req.TransportError{reason: transport_reason} -> transport_reason
        _other -> exception
      end

    if retriable_transport_reason?(reason) and request_metadata.max_retries > 0 do
      %{
        error_type: "github_api_retry_exhausted",
        reason_type: :retry_exhausted,
        request_intent: request_metadata.request_intent,
        detail:
          "GitHub API request intent `#{request_metadata.request_intent}` exhausted retries after transport failure (#{format_reason(reason)}).",
        remediation: remediation_message(request_metadata.request_intent),
        method: request_metadata.method,
        path: request_metadata.path,
        status: nil,
        attempt_count: request_metadata.attempt_count,
        max_retries: request_metadata.max_retries
      }
    else
      %{
        error_type: "github_api_transport_error",
        reason_type: :transport,
        request_intent: request_metadata.request_intent,
        detail: "GitHub API request failed due to transport error (#{format_reason(reason)}).",
        remediation: remediation_message(request_metadata.request_intent),
        method: request_metadata.method,
        path: request_metadata.path,
        status: nil,
        attempt_count: 1,
        max_retries: request_metadata.max_retries
      }
    end
  end

  defp retry_exhausted_failure(response, request_metadata) do
    %{
      error_type: "github_api_retry_exhausted",
      reason_type: :retry_exhausted,
      request_intent: request_metadata.request_intent,
      detail:
        "GitHub API request intent `#{request_metadata.request_intent}` exhausted retries (last status #{response.status}).",
      remediation: remediation_message(request_metadata.request_intent),
      method: request_metadata.method,
      path: request_metadata.path,
      status: response.status,
      attempt_count: request_metadata.attempt_count,
      max_retries: request_metadata.max_retries
    }
  end

  defp invalid_response_failure(other, request_metadata) do
    %{
      error_type: "github_api_invalid_response",
      reason_type: :invalid_response,
      request_intent: request_metadata.request_intent,
      detail: "GitHub API request returned an invalid response shape: #{inspect(other)}.",
      remediation: remediation_message(request_metadata.request_intent),
      method: request_metadata.method,
      path: request_metadata.path,
      status: nil,
      attempt_count: 1,
      max_retries: request_metadata.max_retries
    }
  end

  defp missing_token_failure(auth_mode) do
    %{
      error_type: "github_api_invalid_credentials",
      reason_type: :invalid_request,
      request_intent: request_intent(auth_mode),
      detail: "GitHub API token is missing for repository listing.",
      remediation: "Configure valid GitHub credentials and retry repository validation.",
      method: "GET",
      path: endpoint_path(auth_mode),
      status: nil,
      attempt_count: 1,
      max_retries: 0
    }
  end

  defp repository_collection(:pat, repositories) when is_list(repositories), do: {:ok, repositories}

  defp repository_collection(:github_app, %{"repositories" => repositories})
       when is_list(repositories),
       do: {:ok, repositories}

  defp repository_collection(:github_app, %{repositories: repositories})
       when is_list(repositories),
       do: {:ok, repositories}

  defp repository_collection(_auth_mode, other) do
    {:error, "GitHub API response body is invalid for repository listing: #{inspect(other)}."}
  end

  defp normalize_repository_options_from_collection(repositories) do
    normalized_repositories =
      repositories
      |> Enum.map(&normalize_repository_option/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(fn repository -> repository.full_name end)
      |> Enum.sort_by(fn repository -> {repository.full_name, repository.id} end)

    {:ok, normalized_repositories}
  end

  defp finalize_repository_options(repositories) do
    repositories
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(fn repository -> repository.full_name end)
    |> Enum.sort_by(fn repository -> {repository.full_name, repository.id} end)
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
            |> map_get(:owner, "owner", %{})
            |> extract_owner_name()

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

        normalized_repository_id ->
          normalized_repository_id
      end

    build_repository_option(full_name, repository_id)
  end

  defp normalize_repository_option(_repository), do: nil

  defp build_repository_option(nil, _repository_id), do: nil

  defp build_repository_option(full_name, repository_id) do
    case String.split(full_name, "/", parts: 2) do
      [owner, name] when owner != "" and name != "" ->
        %{
          id: repository_id || "repo:#{full_name}",
          full_name: full_name,
          owner: owner,
          name: name
        }

      _other ->
        nil
    end
  end

  defp extract_owner_name(owner_payload) when is_map(owner_payload) do
    owner_payload
    |> map_get(:login, "login")
    |> normalize_optional_string()
  end

  defp extract_owner_name(_owner_payload), do: nil

  defp retry_request?(request, %Req.Response{status: status}) do
    request.method in [:get, :head] and status in @retriable_statuses
  end

  defp retry_request?(request, %Req.TransportError{}) do
    request.method in [:get, :head]
  end

  defp retry_request?(request, exception) when is_exception(exception) do
    request.method in [:get, :head]
  end

  defp retry_request?(_request, _response_or_exception), do: false

  defp retriable_transport_reason?(:timeout), do: true
  defp retriable_transport_reason?(:closed), do: true
  defp retriable_transport_reason?(:econnrefused), do: true
  defp retriable_transport_reason?(:nxdomain), do: true
  defp retriable_transport_reason?(:ehostunreach), do: true
  defp retriable_transport_reason?({:tls_alert, _alert}), do: true
  defp retriable_transport_reason?(_reason), do: false

  defp response_detail(response, fallback) do
    message =
      case response.body do
        %{"message" => response_message} when is_binary(response_message) -> response_message
        %{message: response_message} when is_binary(response_message) -> response_message
        _other -> nil
      end

    if is_binary(message) and message != "" do
      "#{fallback} GitHub message: #{message}"
    else
      fallback
    end
  end

  defp remediation_message(request_intent) do
    "Retry request intent `#{request_intent}` after confirming network reachability, GitHub API health, and credential scope."
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)

  defp normalize_page_size(value, default) when is_integer(value) and value > 0,
    do: min(value, default)

  defp normalize_page_size(_value, default), do: default

  defp normalize_positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp normalize_positive_integer(_value, default), do: default

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized_value -> normalized_value
    end
  end

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

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
