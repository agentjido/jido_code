defmodule JidoCode.Conversations.Policy do
  # covers: architecture.policy_layers.policy_layers_interlock_without_collapsing
  # covers: architecture.policy_layers.repository_governance_policy_is_repo_control_layer
  # covers: architecture.policy_layers.ash_policy_is_first_class_data_plane_membrane
  # covers: architecture.conversation_driver.conversation_is_ingress_and_steering_surface
  @moduledoc """
  Applies product-side conversation policy before a runtime turn is admitted.

  This module keeps repo-governance policy and Ash-backed product truth distinct
  from the downstream runtime policy layer by deciding whether a conversation
  turn should create work, steer existing work, or halt before coding runtime
  execution begins.
  """

  alias JidoCode.Control.{Actor, RepoBridge}
  alias JidoCode.Governance.PolicyBridge
  alias JidoCode.Operations.WorkItem

  @type action :: :new_demand | :steer_existing_work | :halt

  @type decision :: %{
          action: action(),
          managed_repo_id: String.t() | nil,
          work_item_id: String.t() | nil,
          review_policy: map(),
          reason_code: String.t()
        }

  @spec decide(map()) :: {:ok, decision()} | {:error, term(), decision()}
  def decide(%{} = attrs) do
    managed_repo_id = resolved_managed_repo_id(attrs)
    explicit_work_item_id = get_string(attrs, :work_item_id)

    with managed_repo_id when is_binary(managed_repo_id) <- managed_repo_id || :missing_managed_repo_scope,
         {:ok, review_policy} <- policy_bridge_module().review_policy_for_managed_repo(managed_repo_id) do
      cond do
        is_binary(explicit_work_item_id) ->
          case open_work_item(managed_repo_id, explicit_work_item_id) do
            {:ok, %WorkItem{} = work_item} ->
              {:ok,
               %{
                 action: :steer_existing_work,
                 managed_repo_id: managed_repo_id,
                 work_item_id: work_item.id,
                 review_policy: review_policy,
                 reason_code: "explicit_target_work_item"
               }}

            :error ->
              {:error, :target_work_item_not_found,
               %{
                 action: :halt,
                 managed_repo_id: managed_repo_id,
                 work_item_id: explicit_work_item_id,
                 review_policy: review_policy,
                 reason_code: "target_work_item_not_found"
               }}
          end

        repo_policy_prefers_steering?(review_policy) ->
          case latest_open_work_item(managed_repo_id) do
            {:ok, %WorkItem{} = work_item} ->
              {:ok,
               %{
                 action: :steer_existing_work,
                 managed_repo_id: managed_repo_id,
                 work_item_id: work_item.id,
                 review_policy: review_policy,
                 reason_code: "repo_policy_prefers_steering"
               }}

            :error ->
              {:ok,
               %{
                 action: :new_demand,
                 managed_repo_id: managed_repo_id,
                 work_item_id: nil,
                 review_policy: review_policy,
                 reason_code: "repo_policy_no_open_work_to_steer"
               }}
          end

        true ->
          {:ok,
           %{
             action: :new_demand,
             managed_repo_id: managed_repo_id,
             work_item_id: nil,
             review_policy: review_policy,
             reason_code: "review_policy_requires_new_work"
           }}
      end
    else
      :missing_managed_repo_scope ->
        {:error, :missing_managed_repo_scope,
         %{
           action: :halt,
           managed_repo_id: nil,
           work_item_id: explicit_work_item_id,
           review_policy: policy_bridge_module().default_review_policy(),
           reason_code: "missing_managed_repo_scope"
         }}

      {:error, reason} ->
        {:error, reason,
         %{
           action: :halt,
           managed_repo_id: managed_repo_id,
           work_item_id: explicit_work_item_id,
           review_policy: policy_bridge_module().default_review_policy(),
           reason_code: "review_policy_lookup_failed"
         }}
    end
  end

  def decide(_attrs) do
    {:error, :invalid_conversation_policy_context,
     %{
       action: :halt,
       managed_repo_id: nil,
       work_item_id: nil,
       review_policy: policy_bridge_module().default_review_policy(),
       reason_code: "invalid_conversation_policy_context"
     }}
  end

  defp resolved_managed_repo_id(attrs) when is_map(attrs) do
    case get_string(attrs, :managed_repo_id) do
      managed_repo_id when is_binary(managed_repo_id) ->
        managed_repo_id

      nil ->
        case get_string(attrs, :project_id) do
          nil ->
            nil

          project_id ->
            case repo_bridge_module().managed_repo_for_project(project_id) do
              {:ok, managed_repo} -> get_string(managed_repo, :id)
              _other -> nil
            end
        end
    end
  end

  defp resolved_managed_repo_id(_attrs), do: nil

  defp repo_policy_prefers_steering?(review_policy) do
    review_policy
    |> normalize_map()
    |> Map.get("change_request_required", true)
    |> Kernel.not()
  end

  defp open_work_item(managed_repo_id, work_item_id) do
    case WorkItem.read(
           query: [filter: [id: work_item_id, managed_repo_id: managed_repo_id, status: :open], limit: 1],
           actor: Actor.operator_actor()
         ) do
      {:ok, [%WorkItem{} = work_item | _rest]} -> {:ok, work_item}
      _other -> :error
    end
  end

  defp latest_open_work_item(managed_repo_id) do
    case WorkItem.read(
           query: [
             filter: [managed_repo_id: managed_repo_id, status: :open],
             sort: [updated_at: :desc],
             limit: 1
           ],
           actor: Actor.operator_actor()
         ) do
      {:ok, [%WorkItem{} = work_item | _rest]} -> {:ok, work_item}
      _other -> :error
    end
  end

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

  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp get_string(attrs, key) when is_map(attrs) do
    attrs
    |> Map.get(key)
    |> case do
      nil -> Map.get(attrs, Atom.to_string(key))
      value -> value
    end
    |> normalize_optional_string()
  end

  defp get_string(_attrs, _key), do: nil

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

  defp repo_bridge_module do
    Application.get_env(:jido_code, :conversation_policy_repo_bridge_module, RepoBridge)
  end

  defp policy_bridge_module do
    Application.get_env(:jido_code, :conversation_policy_policy_bridge_module, PolicyBridge)
  end
end
