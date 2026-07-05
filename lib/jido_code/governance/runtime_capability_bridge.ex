defmodule JidoCode.Governance.RuntimeCapabilityBridge do
  @moduledoc """
  Materializes repository-scoped runtime capability posture into governed observations.
  """

  alias JidoCode.Control.Actor
  alias JidoCode.Operations.{Observation, RecordStore}

  @observer Actor.factory_system_actor(%{
              "id" => "system:runtime-capability-bridge",
              "email" => "runtime-capability-bridge@system.local"
            })
  @source "runtime_capability"
  @category "runtime_capability_state"
  @available_service_keys MapSet.new(["coding_assistance_service", "source_code_graph_service"])

  @type capability_signal :: %{
          observation: Observation.t(),
          capability_posture: map()
        }

  @spec source() :: String.t()
  def source, do: @source

  @spec category() :: String.t()
  def category, do: @category

  @spec sync_managed_repo(map()) :: {:ok, capability_signal()} | {:error, term()}
  def sync_managed_repo(managed_repo)

  def sync_managed_repo(%{} = managed_repo) do
    managed_repo_id = map_get(managed_repo, :id, "id")

    with true <- is_binary(managed_repo_id) or {:error, :missing_managed_repo_id},
         capability_posture = capability_posture(managed_repo),
         {:ok, observation} <- sync_observation(managed_repo_id, capability_posture) do
      {:ok, %{observation: observation, capability_posture: capability_posture}}
    else
      false -> {:error, :missing_managed_repo_id}
      {:error, reason} -> {:error, reason}
    end
  end

  def sync_managed_repo(_managed_repo), do: {:error, :invalid_managed_repo}

  @spec latest_signal_snapshot(term()) :: {:ok, map()}
  def latest_signal_snapshot(managed_repo_id) when is_binary(managed_repo_id) do
    {:ok,
     case latest_observation(managed_repo_id) do
       %Observation{} = observation -> normalize_map(observation.payload)
       _other -> absent_capability_posture()
     end}
  end

  def latest_signal_snapshot(_managed_repo_id), do: {:ok, absent_capability_posture()}

  @spec operator_summary(map() | nil) :: String.t()
  def operator_summary(%{} = capability_posture) do
    Map.get(capability_posture, "summary") || absent_capability_posture()["summary"]
  end

  def operator_summary(_capability_posture), do: absent_capability_posture()["summary"]

  defp capability_posture(managed_repo) do
    required_services = required_services(managed_repo)

    services =
      Enum.map(required_services, fn service_key ->
        available? = MapSet.member?(@available_service_keys, service_key)

        %{
          "service_key" => service_key,
          "required" => true,
          "status" => if(available?, do: "available", else: "blocked"),
          "availability" => if(available?, do: "available", else: "missing")
        }
      end)

    available_service_count = Enum.count(services, &(&1["status"] == "available"))
    blocked_service_count = Enum.count(services, &(&1["status"] == "blocked"))

    status =
      cond do
        blocked_service_count > 0 -> "blocked"
        available_service_count > 0 -> "ready"
        true -> "absent"
      end

    %{
      "status" => status,
      "summary" => capability_summary(status, services),
      "required_service_count" => length(services),
      "available_service_count" => available_service_count,
      "blocked_service_count" => blocked_service_count,
      "services" => services
    }
  end

  defp absent_capability_posture do
    %{
      "status" => "absent",
      "summary" => "No repository runtime capabilities are currently required.",
      "required_service_count" => 0,
      "available_service_count" => 0,
      "blocked_service_count" => 0,
      "services" => []
    }
  end

  defp capability_summary("blocked", services) do
    missing =
      services
      |> Enum.filter(&(&1["status"] == "blocked"))
      |> Enum.map(& &1["service_key"])
      |> Enum.join(", ")

    "Runtime capabilities are blocked because required services are unavailable: #{missing}"
  end

  defp capability_summary("ready", services) do
    available =
      services
      |> Enum.filter(&(&1["status"] == "available"))
      |> Enum.map(& &1["service_key"])
      |> Enum.join(", ")

    "Runtime capabilities are available for this repository: #{available}"
  end

  defp capability_summary(_status, _services), do: absent_capability_posture()["summary"]

  defp required_services(managed_repo) do
    integration_settings =
      managed_repo
      |> map_get(:integration_settings, "integration_settings", %{})
      |> normalize_map()

    integration_settings
    |> Map.get("runtime_capabilities", %{})
    |> normalize_map()
    |> Map.get("required_services", integration_settings["required_services"] || [])
    |> normalize_string_list()
  end

  defp sync_observation(managed_repo_id, capability_posture) do
    digest = digest(capability_posture)

    case latest_observation(managed_repo_id) do
      %Observation{} = observation ->
        if get_in(observation.source_metadata || %{}, ["digest"]) == digest do
          {:ok, observation}
        else
          create_observation(managed_repo_id, capability_posture, digest)
        end

      _other ->
        create_observation(managed_repo_id, capability_posture, digest)
    end
  end

  defp create_observation(managed_repo_id, capability_posture, digest) do
    RecordStore.create(
      :observation,
      %{
        managed_repo_id: managed_repo_id,
        source: @source,
        category: @category,
        summary: capability_posture["summary"],
        payload: capability_posture,
        source_metadata: %{
          "digest" => digest,
          "rollout_source" => "repo_local_compatibility_surface"
        },
        captured_by: @observer,
        observed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      },
      actor: @observer
    )
  end

  defp latest_observation(managed_repo_id) do
    case RecordStore.list(:observation, %{managed_repo_id: managed_repo_id, source: @source, category: @category},
           actor: @observer
         ) do
      {:ok, observations} -> latest_by(observations, :observed_at)
      _other -> nil
    end
  end

  defp latest_by(records, field) when is_list(records) do
    records
    |> Enum.reject(&(Map.get(&1, field) == nil))
    |> Enum.sort_by(&(Map.get(&1, field) |> DateTime.to_unix(:microsecond)), :desc)
    |> List.first()
  rescue
    _error -> nil
  end

  defp digest(payload) do
    payload
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp normalize_string_list(value) when is_list(value) do
    value
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_string_list(_value), do: []

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      Map.put(acc, normalized_key, nested_value)
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil

  defp map_get(value, atom_key, string_key, default \\ nil)

  defp map_get(value, atom_key, string_key, default) when is_map(value) do
    Map.get(value, atom_key) || Map.get(value, string_key) || default
  end

  defp map_get(_value, _atom_key, _string_key, default), do: default
end
