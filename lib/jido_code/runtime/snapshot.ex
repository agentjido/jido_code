defmodule JidoCode.Runtime.Snapshot do
  @moduledoc """
  Durable, product-owned repository runtime snapshot.

  The snapshot is intentionally JSON-shaped and small. It captures enough
  runtime topology to restart or explain repository runtime state without
  treating pids, registry names, or private node identifiers as product truth.
  """

  @kind "repository_runtime_snapshot"
  @version 1

  @metadata_snapshot_keys MapSet.new([
                            :managed_repo_id,
                            "managed_repo_id",
                            :workspace_path,
                            "workspace_path",
                            :work_item_id,
                            "work_item_id",
                            :runtime_status,
                            "runtime_status",
                            :coding_pod_id,
                            "coding_pod_id",
                            :latest_analysis_status,
                            "latest_analysis_status",
                            :latest_import_status,
                            "latest_import_status",
                            :source_graph_refresh,
                            "source_graph_refresh",
                            :latest_validation_status,
                            "latest_validation_status",
                            :latest_record_status,
                            "latest_record_status",
                            :latest_query_status,
                            "latest_query_status",
                            :context_management_status,
                            "context_management_status",
                            :latest_monitor_decision,
                            "latest_monitor_decision",
                            :latest_compaction,
                            "latest_compaction",
                            :last_observation,
                            "last_observation",
                            :graph_store_path,
                            "graph_store_path",
                            :store_path,
                            "store_path"
                          ])

  @private_keys MapSet.new([
                  :__struct__,
                  "__struct__",
                  :pid,
                  "pid",
                  :runtime_pid,
                  "runtime_pid",
                  :kernel_name,
                  "kernel_name",
                  :registry_name,
                  "registry_name",
                  :registry_process_name,
                  "registry_process_name",
                  :runtime_private_node_id,
                  "runtime_private_node_id",
                  :node_id,
                  "node_id",
                  :nodes,
                  "nodes",
                  :monitors,
                  "monitors",
                  :monitor_ref,
                  "monitor_ref"
                ])

  defstruct kind: @kind,
            version: @version,
            managed_repo_id: nil,
            workspace_path: nil,
            lifecycle: nil,
            capacity: %{},
            active_work_items: [],
            pods: [],
            diagnostics: [],
            graph_summaries: %{},
            context_summaries: %{},
            captured_at: nil

  @type t :: %__MODULE__{
          kind: String.t(),
          version: pos_integer(),
          managed_repo_id: String.t(),
          workspace_path: String.t() | nil,
          lifecycle: String.t() | nil,
          capacity: map(),
          active_work_items: [map()],
          pods: [map()],
          diagnostics: [map()],
          graph_summaries: map(),
          context_summaries: map(),
          captured_at: String.t()
        }

  @spec kind() :: String.t()
  def kind, do: @kind

  @spec version() :: pos_integer()
  def version, do: @version

  @spec from_status(map(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_status(status, opts \\ [])

  def from_status(status, opts) when is_map(status) do
    with managed_repo_id when is_binary(managed_repo_id) <- value(status, :managed_repo_id) do
      pods = pods(status)

      {:ok,
       %__MODULE__{
         managed_repo_id: managed_repo_id,
         workspace_path: value(status, :workspace_path),
         lifecycle: encode_scalar(value(status, :lifecycle)),
         capacity: sanitize_payload(value(status, :capacity) || %{}),
         active_work_items: active_work_items(status),
         pods: pods,
         diagnostics: sanitize_payload(value(status, :diagnostics) || []),
         graph_summaries: graph_summaries(pods),
         context_summaries: context_summaries(pods),
         captured_at: captured_at(opts)
       }}
    else
      _other -> {:error, %{type: :invalid_runtime_snapshot_status}}
    end
  end

  def from_status(_status, _opts), do: {:error, %{type: :invalid_runtime_snapshot_status}}

  @spec from_record(map()) :: {:ok, t()} | {:error, term()}
  def from_record(record) when is_map(record) do
    with kind when kind == @kind <- value(record, :kind),
         version when version == @version <- value(record, :version),
         managed_repo_id when is_binary(managed_repo_id) <- value(record, :managed_repo_id) do
      {:ok,
       %__MODULE__{
         managed_repo_id: managed_repo_id,
         workspace_path: value(record, :workspace_path),
         lifecycle: value(record, :lifecycle),
         capacity: value(record, :capacity) || %{},
         active_work_items: value(record, :active_work_items) || [],
         pods: value(record, :pods) || [],
         diagnostics: value(record, :diagnostics) || [],
         graph_summaries: value(record, :graph_summaries) || %{},
         context_summaries: value(record, :context_summaries) || %{},
         captured_at: value(record, :captured_at)
       }}
    else
      _other -> {:error, %{type: :invalid_runtime_snapshot_record}}
    end
  end

  def from_record(_record), do: {:error, %{type: :invalid_runtime_snapshot_record}}

  @spec to_record(t()) :: map()
  def to_record(%__MODULE__{} = snapshot) do
    %{
      "kind" => snapshot.kind,
      "version" => snapshot.version,
      "managed_repo_id" => snapshot.managed_repo_id,
      "workspace_path" => snapshot.workspace_path,
      "lifecycle" => snapshot.lifecycle,
      "capacity" => snapshot.capacity,
      "active_work_items" => snapshot.active_work_items,
      "pods" => snapshot.pods,
      "diagnostics" => snapshot.diagnostics,
      "graph_summaries" => snapshot.graph_summaries,
      "context_summaries" => snapshot.context_summaries,
      "captured_at" => snapshot.captured_at
    }
  end

  @spec checkpoint_id(String.t()) :: String.t()
  def checkpoint_id(managed_repo_id) when is_binary(managed_repo_id),
    do: "repository-runtime:#{managed_repo_id}"

  defp active_work_items(status) do
    status
    |> value(:active_work_items)
    |> case do
      active_work_items when is_map(active_work_items) -> Map.values(active_work_items)
      active_work_items when is_list(active_work_items) -> active_work_items
      _other -> []
    end
    |> Enum.map(&work_item_snapshot/1)
    |> Enum.sort_by(&Map.get(&1, "work_item_id", ""))
  end

  defp work_item_snapshot(work_item) when is_map(work_item) do
    %{
      "work_item_id" => value(work_item, :work_item_id),
      "workspace_path" => value(work_item, :workspace_path),
      "admitted_at" => encode_scalar(value(work_item, :admitted_at)),
      "lifecycle" => encode_scalar(value(work_item, :lifecycle)),
      "coding_pod" => encode_key(value(work_item, :coding_pod)),
      "context_management_pod" => encode_key(value(work_item, :context_management_pod)),
      "diagnostics" => sanitize_payload(value(work_item, :diagnostics) || [])
    }
  end

  defp work_item_snapshot(_work_item), do: %{}

  defp pods(status) do
    status
    |> value(:active_pods)
    |> case do
      active_pods when is_map(active_pods) -> Map.values(active_pods)
      active_pods when is_list(active_pods) -> active_pods
      _other -> []
    end
    |> Enum.map(&pod_snapshot/1)
    |> Enum.sort_by(&Map.get(&1, "pod_id", ""))
  end

  defp pod_snapshot(pod) when is_map(pod) do
    metadata = pod |> value(:metadata) |> bounded_metadata()

    %{
      "pod_id" => value(pod, :pod_id),
      "kind" => encode_scalar(value(pod, :kind)),
      "key" => encode_key(value(pod, :key)),
      "scope" => encode_scalar(value(pod, :scope)),
      "module" => encode_module(value(pod, :module)),
      "metadata" => metadata,
      "lifecycle" => encode_scalar(value(pod, :lifecycle)),
      "diagnostics" => sanitize_payload(value(pod, :diagnostics) || []),
      "registered_at" => encode_scalar(value(pod, :registered_at)),
      "started_at" => encode_scalar(value(pod, :started_at)),
      "last_activity_at" => encode_scalar(value(pod, :last_activity_at))
    }
  end

  defp pod_snapshot(_pod), do: %{}

  defp graph_summaries(pods) do
    pods
    |> Enum.filter(&(Map.get(&1, "kind") in ["source_code_graph", "memory_graph"]))
    |> Map.new(fn pod ->
      {Map.fetch!(pod, "kind"),
       %{
         "pod_id" => Map.get(pod, "pod_id"),
         "workspace_path" => get_in(pod, ["metadata", "workspace_path"]),
         "runtime_status" => get_in(pod, ["metadata", "runtime_status"]),
         "latest_analysis_status" => get_in(pod, ["metadata", "latest_analysis_status"]),
         "latest_import_status" => get_in(pod, ["metadata", "latest_import_status"]),
         "source_graph_refresh" => get_in(pod, ["metadata", "source_graph_refresh"]),
         "latest_validation_status" => get_in(pod, ["metadata", "latest_validation_status"]),
         "latest_record_status" => get_in(pod, ["metadata", "latest_record_status"]),
         "latest_query_status" => get_in(pod, ["metadata", "latest_query_status"])
       }
       |> Enum.reject(fn {_key, value} -> is_nil(value) end)
       |> Map.new()}
    end)
  end

  defp context_summaries(pods) do
    pods
    |> Enum.filter(&(Map.get(&1, "kind") == "context_management"))
    |> Map.new(fn pod ->
      work_item_id = get_in(pod, ["metadata", "work_item_id"])

      {work_item_id || Map.get(pod, "pod_id"),
       %{
         "pod_id" => Map.get(pod, "pod_id"),
         "work_item_id" => work_item_id,
         "workspace_path" => get_in(pod, ["metadata", "workspace_path"]),
         "runtime_status" => get_in(pod, ["metadata", "runtime_status"]),
         "context_management_status" => get_in(pod, ["metadata", "context_management_status"]),
         "latest_monitor_decision" => get_in(pod, ["metadata", "latest_monitor_decision"]),
         "latest_compaction" => get_in(pod, ["metadata", "latest_compaction"])
       }
       |> Enum.reject(fn {_key, value} -> is_nil(value) end)
       |> Map.new()}
    end)
  end

  defp bounded_metadata(metadata) when is_map(metadata) do
    metadata
    |> Enum.filter(fn {key, _value} -> MapSet.member?(@metadata_snapshot_keys, key) end)
    |> Map.new(fn {key, nested_value} -> {to_string(key), sanitize_payload(nested_value)} end)
  end

  defp bounded_metadata(_metadata), do: %{}

  defp sanitize_payload(value) when is_map(value) do
    value
    |> Enum.reject(fn {key, _value} -> MapSet.member?(@private_keys, key) end)
    |> Map.new(fn {key, nested_value} -> {to_string(key), sanitize_payload(nested_value)} end)
  end

  defp sanitize_payload(value) when is_list(value), do: Enum.map(value, &sanitize_payload/1)
  defp sanitize_payload(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp sanitize_payload(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp sanitize_payload(value) when is_atom(value), do: encode_scalar(value)
  defp sanitize_payload(value) when is_pid(value) or is_reference(value) or is_port(value), do: nil
  defp sanitize_payload(value) when is_function(value), do: nil
  defp sanitize_payload(value), do: value

  defp encode_key(nil), do: nil

  defp encode_key(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.map(&encode_scalar/1)
  end

  defp encode_key(value) when is_list(value), do: Enum.map(value, &encode_scalar/1)
  defp encode_key(value), do: encode_scalar(value)

  defp encode_module(module) when is_atom(module), do: Atom.to_string(module)
  defp encode_module(module) when is_binary(module), do: module
  defp encode_module(_module), do: nil

  defp encode_scalar(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp encode_scalar(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp encode_scalar(value) when is_atom(value), do: Atom.to_string(value)
  defp encode_scalar(value), do: value

  defp captured_at(opts) do
    opts
    |> Keyword.get(:captured_at, DateTime.utc_now())
    |> encode_scalar()
  end

  defp value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
