defmodule JidoCode.Operations.RepoNativeState do
  # covers: architecture.factory_control_plane.repo_native_state_layers_inform_control_plane
  # covers: architecture.event_assessment_synthesis.repo_native_state_informs_assessment_inputs
  # covers: architecture.repo_posture.repo_native_observations_capture_current_truth_signals
  @moduledoc """
  Observes repo-native state layers such as `.spec/` and optional Beadwork files
  as durable control-plane observations without replacing product truth.
  """

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Operations.{Observation, RecordStore}

  @observer Actor.factory_system_actor(%{
              "id" => "system:repo-native-state",
              "email" => "repo-native-state@system.local"
            })
  @source "repo_native"
  @spec_category "spec_led_state"
  @beadwork_category "beadwork_state"
  @max_listed_paths 20
  @max_scanned_paths 50

  @type signal_snapshot :: map()

  @spec sync_managed_repo(ManagedRepo.t() | map()) ::
          {:ok, %{observations: [Observation.t()], signals: signal_snapshot()}} | {:error, term()}
  def sync_managed_repo(%{} = managed_repo) do
    managed_repo_id = map_get(managed_repo, :id, "id")

    cond do
      not is_binary(managed_repo_id) ->
        {:error, :missing_managed_repo_id}

      true ->
        workspace_path = workspace_path(managed_repo)
        spec_signal = read_spec_signal(workspace_path)
        beadwork_signal = read_beadwork_signal(workspace_path, managed_repo_id)

        with {:ok, observations} <- sync_signals(managed_repo_id, [spec_signal, beadwork_signal]) do
          {:ok,
           %{
             observations: observations,
             signals: signal_snapshot_from_observations(spec_signal, beadwork_signal, observations)
           }}
        end
    end
  end

  def sync_managed_repo(_managed_repo), do: {:error, :invalid_managed_repo}

  @spec latest_signal_snapshot(term()) :: {:ok, signal_snapshot()}
  def latest_signal_snapshot(managed_repo_id) when is_binary(managed_repo_id) do
    {:ok,
     %{
       "spec_led" => latest_signal_payload(managed_repo_id, @spec_category) || absent_spec_signal(),
       "beadwork" => latest_signal_payload(managed_repo_id, @beadwork_category) || absent_beadwork_signal()
     }}
  end

  def latest_signal_snapshot(_managed_repo_id) do
    {:ok,
     %{
       "spec_led" => absent_spec_signal(),
       "beadwork" => absent_beadwork_signal()
     }}
  end

  defp sync_signals(managed_repo_id, signals) do
    signals
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce_while({:ok, []}, fn signal, {:ok, acc} ->
      case sync_signal_observation(managed_repo_id, signal) do
        {:ok, nil} -> {:cont, {:ok, acc}}
        {:ok, observation} -> {:cont, {:ok, [observation | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, observations} -> {:ok, Enum.reverse(observations)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp sync_signal_observation(managed_repo_id, signal) do
    latest =
      latest_observation(managed_repo_id, signal.category)

    if latest && latest.source_metadata["digest"] == signal.digest do
      {:ok, latest}
    else
      RecordStore.create(
        :observation,
        %{
          managed_repo_id: managed_repo_id,
          source: @source,
          category: signal.category,
          summary: signal.summary,
          payload: signal.payload,
          source_metadata:
            signal.metadata
            |> Map.put("digest", signal.digest),
          captured_by: @observer,
          observed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        },
        actor: @observer
      )
    end
  end

  defp latest_observation(managed_repo_id, category) do
    case RecordStore.list(
           :observation,
           %{managed_repo_id: managed_repo_id, source: @source, category: category},
           actor: @observer
         ) do
      {:ok, observations} -> latest_by_observed_at(observations)
      _other -> nil
    end
  end

  defp latest_signal_payload(managed_repo_id, category) do
    case latest_observation(managed_repo_id, category) do
      %Observation{} = observation -> normalize_map(observation.payload)
      _other -> nil
    end
  end

  defp signal_snapshot_from_observations(spec_signal, beadwork_signal, _observations) do
    %{
      "spec_led" => (spec_signal && spec_signal.payload) || absent_spec_signal(),
      "beadwork" => (beadwork_signal && beadwork_signal.payload) || absent_beadwork_signal()
    }
  end

  defp read_spec_signal(nil), do: nil

  defp read_spec_signal(workspace_path) when is_binary(workspace_path) do
    spec_dir = Path.join(workspace_path, ".spec")

    if File.dir?(spec_dir) do
      state_path = Path.join(spec_dir, "state.json")
      specs_dir = Path.join(spec_dir, "specs")
      decisions_dir = Path.join(spec_dir, "decisions")
      spec_count = count_spec_files(specs_dir)
      decision_count = count_decision_files(decisions_dir)

      case decode_json_file(state_path) do
        {:ok, state} ->
          summary = normalize_map(Map.get(state, "summary", %{}))
          verification = normalize_map(Map.get(state, "verification", %{}))
          threshold_failures = normalize_non_negative_integer(Map.get(verification, "threshold_failures")) || 0
          findings_count = normalize_non_negative_integer(Map.get(summary, "findings")) || 0

          payload = %{
            "signal_type" => "spec_led",
            "present" => true,
            "status" => spec_status(threshold_failures, findings_count),
            "verification_confidence" => verification_confidence(threshold_failures, findings_count),
            "workspace_relative_root" => ".spec",
            "state_path" => ".spec/state.json",
            "spec_count" =>
              normalize_non_negative_integer(Map.get(summary, "subjects")) ||
                normalize_non_negative_integer(
                  Map.get(state |> normalize_map() |> Map.get("workspace", %{}), "spec_count")
                ) ||
                spec_count,
            "decision_count" =>
              normalize_non_negative_integer(Map.get(summary, "decisions")) ||
                normalize_non_negative_integer(
                  Map.get(state |> normalize_map() |> Map.get("workspace", %{}), "decision_count")
                ) ||
                decision_count,
            "requirements_count" => normalize_non_negative_integer(Map.get(summary, "requirements")) || 0,
            "scenario_count" => normalize_non_negative_integer(Map.get(summary, "scenarios")) || 0,
            "findings_count" => findings_count,
            "threshold_failures" => threshold_failures,
            "verification_claims_count" =>
              state |> normalize_map() |> get_in(["verification", "claims"]) |> normalize_list_length(),
            "strength_summary" =>
              verification
              |> Map.get("strength_summary", %{})
              |> normalize_map()
          }

          build_signal(
            @spec_category,
            spec_summary(payload),
            payload,
            %{
              "workspace_path" => workspace_path,
              "relative_paths" => [".spec", ".spec/state.json"],
              "source_layer" => "repo_native"
            }
          )

        {:error, _reason} ->
          payload = %{
            "signal_type" => "spec_led",
            "present" => true,
            "status" => "state_missing",
            "verification_confidence" => "low",
            "workspace_relative_root" => ".spec",
            "state_path" => ".spec/state.json",
            "spec_count" => spec_count,
            "decision_count" => decision_count,
            "requirements_count" => 0,
            "scenario_count" => 0,
            "findings_count" => 1,
            "threshold_failures" => 1,
            "verification_claims_count" => 0,
            "strength_summary" => %{}
          }

          build_signal(
            @spec_category,
            "Observed .spec workspace without generated state; repo-native current truth needs verification refresh.",
            payload,
            %{
              "workspace_path" => workspace_path,
              "relative_paths" => [".spec"],
              "source_layer" => "repo_native"
            }
          )
      end
    end
  end

  defp read_spec_signal(_workspace_path), do: nil

  defp read_beadwork_signal(nil, _managed_repo_id), do: nil

  defp read_beadwork_signal(workspace_path, managed_repo_id)
       when is_binary(workspace_path) and is_binary(managed_repo_id) do
    candidate_paths = beadwork_paths(workspace_path)

    if candidate_paths == [] do
      nil
    else
      referenced_work_item_ids = referenced_work_item_ids(workspace_path, candidate_paths)
      open_work_item_ids = open_work_item_ids(managed_repo_id)
      aligned_work_item_ids = Enum.filter(referenced_work_item_ids, &(&1 in open_work_item_ids))
      unaligned_work_item_ids = referenced_work_item_ids -- aligned_work_item_ids

      payload = %{
        "signal_type" => "beadwork",
        "present" => true,
        "status" => beadwork_status(referenced_work_item_ids, aligned_work_item_ids, unaligned_work_item_ids),
        "tracked_file_count" => length(candidate_paths),
        "tracked_paths" => candidate_paths |> Enum.take(@max_listed_paths),
        "referenced_work_item_ids" => referenced_work_item_ids,
        "aligned_open_work_item_ids" => aligned_work_item_ids,
        "unaligned_work_item_ids" => unaligned_work_item_ids,
        "open_work_item_count" => length(open_work_item_ids)
      }

      build_signal(
        @beadwork_category,
        beadwork_summary(payload),
        payload,
        %{
          "workspace_path" => workspace_path,
          "relative_paths" => candidate_paths |> Enum.take(@max_listed_paths),
          "source_layer" => "repo_native"
        }
      )
    end
  end

  defp read_beadwork_signal(_workspace_path, _managed_repo_id), do: nil

  defp build_signal(category, summary, payload, metadata) do
    normalized_payload = normalize_map(payload)

    %{
      category: category,
      summary: summary,
      payload: normalized_payload,
      metadata: normalize_map(metadata),
      digest: signal_digest(category, normalized_payload)
    }
  end

  defp beadwork_paths(workspace_path) do
    beadwork_dir = Path.join(workspace_path, ".beadwork")
    memory_path = Path.join(workspace_path, "memory.md")

    paths =
      []
      |> maybe_add_path(memory_path)
      |> Kernel.++(
        if File.dir?(beadwork_dir) do
          beadwork_dir
          |> Path.join("**/*")
          |> Path.wildcard(match_dot: true)
          |> Enum.filter(&File.regular?/1)
          |> Enum.take(@max_scanned_paths)
        else
          []
        end
      )
      |> Enum.map(&Path.relative_to(&1, workspace_path))
      |> Enum.uniq()
      |> Enum.sort()

    paths
  end

  defp referenced_work_item_ids(workspace_path, relative_paths) do
    relative_paths
    |> Enum.flat_map(fn relative_path ->
      workspace_path
      |> Path.join(relative_path)
      |> File.read()
      |> case do
        {:ok, contents} -> Regex.scan(~r/work_item_id\s*[:=]\s*([0-9a-fA-F-]{36})/, contents, capture: :all_but_first)
        _other -> []
      end
    end)
    |> List.flatten()
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp open_work_item_ids(managed_repo_id) do
    case RecordStore.list(:work_item, %{managed_repo_id: managed_repo_id, status: :open}, actor: @observer) do
      {:ok, work_items} -> Enum.map(work_items, & &1.id)
      _other -> []
    end
  end

  defp latest_by_observed_at([]), do: nil

  defp latest_by_observed_at(observations) do
    Enum.max_by(observations, &datetime_sort_key(&1.observed_at), fn -> nil end)
  end

  defp datetime_sort_key(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :microsecond)
  defp datetime_sort_key(_datetime), do: -1

  defp signal_digest(category, payload) do
    digest_source = Jason.encode!(%{"category" => category, "payload" => payload})
    :crypto.hash(:sha256, digest_source) |> Base.encode16(case: :lower)
  end

  defp spec_status(0, 0), do: "verified"
  defp spec_status(0, findings_count) when findings_count > 0, do: "drift"
  defp spec_status(_threshold_failures, _findings_count), do: "blocked"

  defp verification_confidence(0, 0), do: "high"
  defp verification_confidence(0, _findings_count), do: "medium"
  defp verification_confidence(_threshold_failures, _findings_count), do: "low"

  defp spec_summary(payload) do
    status = Map.get(payload, "status")
    spec_count = Map.get(payload, "spec_count", 0)
    findings_count = Map.get(payload, "findings_count", 0)
    threshold_failures = Map.get(payload, "threshold_failures", 0)

    case status do
      "verified" ->
        "Observed verified .spec workspace with #{spec_count} authored subjects and no outstanding drift findings."

      "drift" ->
        "Observed .spec workspace drift with #{findings_count} finding(s); posture should remain cautious until repo-native state is reconciled."

      _other ->
        "Observed .spec workspace in a blocked state with #{threshold_failures} verification threshold failure(s)."
    end
  end

  defp beadwork_status([], _aligned, _unaligned), do: "present"
  defp beadwork_status(_refs, aligned, []) when aligned != [], do: "aligned"
  defp beadwork_status(_refs, _aligned, _unaligned), do: "needs_alignment"

  defp beadwork_summary(payload) do
    tracked_file_count = Map.get(payload, "tracked_file_count", 0)
    aligned_count = payload |> Map.get("aligned_open_work_item_ids", []) |> length()
    referenced_count = payload |> Map.get("referenced_work_item_ids", []) |> length()

    case Map.get(payload, "status") do
      "aligned" ->
        "Observed optional Beadwork state across #{tracked_file_count} file(s) aligned to #{aligned_count} open work item(s)."

      "needs_alignment" ->
        "Observed optional Beadwork state across #{tracked_file_count} file(s) with #{referenced_count} work reference(s) needing alignment review."

      _other ->
        "Observed optional Beadwork state across #{tracked_file_count} file(s) with no durable work-item references yet."
    end
  end

  defp absent_spec_signal do
    %{
      "signal_type" => "spec_led",
      "present" => false,
      "status" => "absent",
      "verification_confidence" => "low"
    }
  end

  defp absent_beadwork_signal do
    %{
      "signal_type" => "beadwork",
      "present" => false,
      "status" => "absent",
      "tracked_file_count" => 0,
      "tracked_paths" => [],
      "referenced_work_item_ids" => [],
      "aligned_open_work_item_ids" => [],
      "unaligned_work_item_ids" => []
    }
  end

  defp workspace_path(managed_repo) do
    managed_repo
    |> map_get(:workspace_settings, "workspace_settings", %{})
    |> normalize_map()
    |> Map.get("workspace_path")
    |> normalize_optional_string()
  end

  defp count_spec_files(path) do
    path
    |> Path.join("*.spec.md")
    |> Path.wildcard()
    |> length()
  end

  defp count_decision_files(path) do
    path
    |> Path.join("*.md")
    |> Path.wildcard()
    |> Enum.reject(&(Path.basename(&1) == "README.md"))
    |> length()
  end

  defp decode_json_file(path) do
    with true <- File.regular?(path),
         {:ok, contents} <- File.read(path),
         {:ok, decoded} <- Jason.decode(contents) do
      {:ok, normalize_map(decoded)}
    else
      _other -> {:error, :invalid_json}
    end
  end

  defp maybe_add_path(paths, path) do
    if File.regular?(path), do: [path | paths], else: paths
  end

  defp normalize_list_length(list) when is_list(list), do: length(list)
  defp normalize_list_length(_value), do: 0

  defp normalize_non_negative_integer(value) when is_integer(value) and value >= 0, do: value

  defp normalize_non_negative_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> parsed
      _other -> nil
    end
  end

  defp normalize_non_negative_integer(_value), do: nil

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(%{} = map, atom_key, string_key, default) do
    case Map.fetch(map, atom_key) do
      {:ok, value} -> value
      :error -> Map.get(map, string_key, default)
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp normalize_map(%_{} = value) do
    value
    |> Map.from_struct()
    |> Map.delete(:__meta__)
    |> normalize_map()
  end

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

  defp normalize_nested_value(%_{} = value) do
    value
    |> Map.from_struct()
    |> Map.delete(:__meta__)
    |> normalize_map()
  end

  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil
end
