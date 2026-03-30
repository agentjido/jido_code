defmodule JidoCode.Operations.Ingress do
  # covers: architecture.demand_ingress.external_object_tracks_repo_external_entities
  # covers: architecture.demand_ingress.observation_captures_repo_and_system_facts
  # covers: architecture.demand_ingress.intake_captures_operator_and_trusted_requests
  # covers: architecture.demand_ingress.normalized_ingress_preserves_attribution_and_correlation
  @moduledoc """
  Normalizes inbound external and operator demand into durable control-plane ingress records.
  """

  alias JidoCode.Control.{Actor, ManagedRepo, RepoBridge}
  alias JidoCode.Operations.{ExternalObject, Intake, Observation}
  alias JidoCode.Projects.Project

  @github_provider :github
  @github_issue_type :github_issue
  @github_pull_request_type :github_pull_request
  @github_repository_type :github_repository
  @webhook_source "github_webhook"
  @external_event_category "external_event"

  @spec record_github_webhook_delivery(map()) ::
          {:ok, %{external_object: ExternalObject.t() | nil, observation: Observation.t()}}
          | {:error, term()}
  def record_github_webhook_delivery(%{} = delivery) do
    payload =
      delivery
      |> Map.get(:payload, %{})
      |> normalize_map()

    actor = external_ingress_actor(delivery)
    repo_context = repo_context_for_repo_full_name(extract_repo_full_name(payload))

    with {:ok, external_object} <-
           maybe_record_external_object(repo_context, payload, delivery, actor),
         {:ok, observation} <-
           Observation.create(
             %{
               managed_repo_id: repo_context.managed_repo_id,
               external_object_id: external_object_id(external_object),
               source: @webhook_source,
               category: @external_event_category,
               summary: delivery_summary(delivery, payload, repo_context.repo_full_name, external_object),
               payload: payload,
               source_metadata: webhook_source_metadata(delivery, repo_context),
               captured_by: actor
             },
             actor: actor
           ) do
      {:ok, %{external_object: external_object, observation: observation}}
    end
  end

  def record_github_webhook_delivery(_delivery), do: {:error, :invalid_delivery}

  @spec record_operator_intake(map()) :: {:ok, Intake.t()} | {:error, term()}
  def record_operator_intake(%{} = attrs) do
    with {:ok, channel} <- fetch_required_string(attrs, :channel),
         {:ok, intent} <- fetch_required_string(attrs, :intent),
         actor <- normalize_operator_actor(Map.get(attrs, :actor) || Map.get(attrs, "actor")),
         payload <- normalize_map(Map.get(attrs, :payload) || Map.get(attrs, "payload", %{})),
         source_metadata <-
           normalize_map(Map.get(attrs, :source_metadata) || Map.get(attrs, "source_metadata", %{})) do
      Intake.create(
        %{
          managed_repo_id:
            resolve_managed_repo_id(
              Map.get(attrs, :managed_repo_id) || Map.get(attrs, "managed_repo_id"),
              Map.get(attrs, :project_id) || Map.get(attrs, "project_id")
            ),
          channel: channel,
          intent: intent,
          payload: payload,
          source_metadata: source_metadata,
          requested_by: actor
        },
        actor: actor
      )
    end
  end

  def record_operator_intake(_attrs), do: {:error, :invalid_intake}

  defp maybe_record_external_object(repo_context, payload, delivery, actor) do
    case external_object_attrs(repo_context, payload, delivery) do
      nil ->
        {:ok, nil}

      attrs ->
        ExternalObject.upsert_observed(attrs, actor: actor)
    end
  end

  defp external_object_attrs(repo_context, payload, delivery) when is_map(payload) do
    repo_full_name = repo_context.repo_full_name

    cond do
      is_map(payload["issue"]) ->
        issue = normalize_map(payload["issue"])
        issue_number = normalize_optional_string(issue["number"]) || normalize_optional_string(issue["id"])
        issue_id = normalize_optional_string(issue["id"]) || issue_number

        if issue_id && issue_number do
          %{
            managed_repo_id: repo_context.managed_repo_id,
            provider: @github_provider,
            object_type: @github_issue_type,
            external_id: issue_id,
            canonical_key: canonical_key(@github_issue_type, repo_full_name, issue_id),
            canonical_reference: "#{repo_full_name}##{issue_number}",
            title: normalize_optional_string(issue["title"]),
            url: normalize_optional_string(issue["html_url"]),
            status: normalize_optional_string(issue["state"]),
            payload: issue,
            source_metadata: webhook_source_metadata(delivery, repo_context)
          }
        end

      is_map(payload["pull_request"]) ->
        pull_request = normalize_map(payload["pull_request"])

        pull_request_number =
          normalize_optional_string(pull_request["number"]) || normalize_optional_string(payload["number"])

        pull_request_id =
          normalize_optional_string(pull_request["id"]) || pull_request_number

        if pull_request_id && pull_request_number do
          %{
            managed_repo_id: repo_context.managed_repo_id,
            provider: @github_provider,
            object_type: @github_pull_request_type,
            external_id: pull_request_id,
            canonical_key: canonical_key(@github_pull_request_type, repo_full_name, pull_request_id),
            canonical_reference: "#{repo_full_name}/pull/#{pull_request_number}",
            title: normalize_optional_string(pull_request["title"]),
            url: normalize_optional_string(pull_request["html_url"]),
            status: normalize_optional_string(pull_request["state"]),
            payload: pull_request,
            source_metadata: webhook_source_metadata(delivery, repo_context)
          }
        end

      is_binary(repo_full_name) ->
        repository = payload["repository"] |> normalize_map()
        repository_id = normalize_optional_string(repository["id"]) || repo_full_name

        %{
          managed_repo_id: repo_context.managed_repo_id,
          provider: @github_provider,
          object_type: @github_repository_type,
          external_id: repository_id,
          canonical_key: canonical_key(@github_repository_type, repo_full_name, repository_id),
          canonical_reference: repo_full_name,
          title: normalize_optional_string(repository["name"]) || repo_full_name,
          url: normalize_optional_string(repository["html_url"]),
          status: normalize_optional_string(repository["visibility"]),
          payload: repository,
          source_metadata: webhook_source_metadata(delivery, repo_context)
        }

      true ->
        nil
    end
  end

  defp delivery_summary(delivery, payload, repo_full_name, %ExternalObject{} = external_object) do
    event = normalize_optional_string(Map.get(delivery, :event))
    action = normalize_optional_string(payload["action"])
    reference = normalize_optional_string(external_object.canonical_reference)

    [event, action, reference || repo_full_name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> case do
      "" -> "Observed verified GitHub webhook delivery."
      summary -> "Observed #{summary}."
    end
  end

  defp delivery_summary(delivery, payload, repo_full_name, nil) do
    event = normalize_optional_string(Map.get(delivery, :event))
    action = normalize_optional_string(payload["action"])

    [event, action, repo_full_name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> case do
      "" -> "Observed verified GitHub webhook delivery."
      summary -> "Observed #{summary}."
    end
  end

  defp webhook_source_metadata(delivery, repo_context) do
    %{
      "delivery_id" => normalize_optional_string(Map.get(delivery, :delivery_id)),
      "event" => normalize_optional_string(Map.get(delivery, :event)),
      "repo_full_name" => repo_context.repo_full_name,
      "project_id" => repo_context.project_id,
      "managed_repo_id" => repo_context.managed_repo_id
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp repo_context_for_repo_full_name(nil) do
    %{repo_full_name: nil, project_id: nil, managed_repo_id: nil}
  end

  defp repo_context_for_repo_full_name(repo_full_name) when is_binary(repo_full_name) do
    case Project.read(
           query: [filter: [github_full_name: repo_full_name], limit: 1],
           authorize?: false
         ) do
      {:ok, [%Project{} = project | _rest]} ->
        project_id = normalize_optional_string(project.id)

        managed_repo_id =
          case RepoBridge.managed_repo_for_project(project_id) do
            {:ok, %ManagedRepo{} = managed_repo} -> normalize_optional_string(managed_repo.id)
            _other -> nil
          end

        %{repo_full_name: repo_full_name, project_id: project_id, managed_repo_id: managed_repo_id}

      _other ->
        %{repo_full_name: repo_full_name, project_id: nil, managed_repo_id: nil}
    end
  end

  defp resolve_managed_repo_id(managed_repo_id, _project_id) when is_binary(managed_repo_id),
    do: normalize_optional_string(managed_repo_id)

  defp resolve_managed_repo_id(nil, project_id) when is_binary(project_id) do
    case RepoBridge.managed_repo_for_project(project_id) do
      {:ok, %ManagedRepo{} = managed_repo} -> normalize_optional_string(managed_repo.id)
      _other -> nil
    end
  end

  defp resolve_managed_repo_id(_managed_repo_id, _project_id), do: nil

  defp normalize_operator_actor(%{} = actor_attrs) do
    Actor.operator_actor(%{
      "id" =>
        actor_attrs
        |> map_get(:id, "id")
        |> normalize_optional_string(),
      "email" =>
        actor_attrs
        |> map_get(:email, "email")
        |> normalize_optional_string()
    })
  end

  defp normalize_operator_actor(_actor_attrs), do: Actor.operator_actor()

  defp external_ingress_actor(delivery) do
    delivery_id = normalize_optional_string(Map.get(delivery, :delivery_id))

    Actor.external_ingress_actor(%{
      "id" => delivery_id && "github-webhook:#{delivery_id}",
      "delivery_id" => delivery_id
    })
  end

  defp external_object_id(%ExternalObject{} = external_object), do: external_object.id
  defp external_object_id(_external_object), do: nil

  defp canonical_key(object_type, repo_full_name, external_id) do
    [@github_provider, object_type, repo_full_name || "unknown-repo", external_id]
    |> Enum.map(&to_string/1)
    |> Enum.join(":")
  end

  defp extract_repo_full_name(payload) when is_map(payload) do
    payload
    |> map_get("repository", :repository, %{})
    |> normalize_map()
    |> map_get("full_name", :full_name)
    |> normalize_optional_string() ||
      first_repository_full_name(payload)
  end

  defp extract_repo_full_name(_payload), do: nil

  defp first_repository_full_name(payload) when is_map(payload) do
    payload
    |> map_get("repositories", :repositories, [])
    |> case do
      [first | _rest] when is_map(first) ->
        first
        |> normalize_map()
        |> map_get("full_name", :full_name)
        |> normalize_optional_string()

      _other ->
        nil
    end
  end

  defp first_repository_full_name(_payload), do: nil

  defp fetch_required_string(attrs, key) do
    value =
      case key do
        atom when is_atom(atom) -> Map.get(attrs, atom) || Map.get(attrs, Atom.to_string(atom))
      end

    case normalize_optional_string(value) do
      nil -> {:error, {:missing_required_field, key}}
      normalized -> {:ok, normalized}
    end
  end

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(%{} = map, atom_key, string_key, default) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      Map.put(acc, normalized_key, normalize_nested_value(nested_value))
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_boolean(value), do: nil
  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil
end
