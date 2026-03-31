defmodule JidoCode.Governance.PolicyBridge do
  # covers: architecture.run_governance.review_policy_controls_change_request_creation
  # covers: architecture.policy_layers.repository_governance_policy_is_repo_control_layer
  # covers: architecture.policy_layers.policy_layers_interlock_without_collapsing
  # covers: architecture.policy_layers.repo_posture_can_shape_effective_review_policy
  # covers: architecture.repo_posture.supervision_modes_are_explicit_and_reversible
  # covers: architecture.repo_posture.algedonic_escalation_is_typed_and_evidence_rich
  @moduledoc """
  Derives the default governance policy set from transitional managed-repo state.
  """

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.{PolicySet, RepoPosture}

  @approval_mode_auto_post "auto_post"
  @approval_mode_approval_required "approval_required"
  @review_threshold_auto_post "auto_post"
  @review_threshold_human_approval "human_approval"
  @required_stage_approval "approval"
  @legacy_approval_mode_source "support_agent_config.github_issue_bot.approval_mode"
  @default_policy_source "policy_set.review_policy.default"
  @supervision_mode_guided "guided"
  @supervision_mode_directed "directed"
  @supervision_mode_autonomous "autonomous"
  @escalation_status_normal "normal"

  @spec sync_managed_repo(struct() | map()) :: {:ok, PolicySet.t()} | {:error, term()}
  def sync_managed_repo(%{} = managed_repo) do
    PolicySet.upsert_default_for_managed_repo(
      %{
        managed_repo_id: map_get(managed_repo, :id, "id"),
        review_policy: review_policy_from_repo(managed_repo),
        policy_metadata: %{
          "legacy_project_id" => map_get(managed_repo, :legacy_project_id, "legacy_project_id"),
          "source" => "managed_repo_projection"
        }
      },
      actor: Actor.factory_system_actor()
    )
  end

  def sync_managed_repo(_managed_repo), do: {:error, :invalid_managed_repo}

  @spec review_policy_for_managed_repo(term()) :: {:ok, map()}
  def review_policy_for_managed_repo(managed_repo_id) when is_binary(managed_repo_id) do
    with {:ok, configured_review_policy} <- configured_review_policy_for_managed_repo(managed_repo_id) do
      {:ok, effective_review_policy(managed_repo_id, configured_review_policy)}
    end
  end

  def review_policy_for_managed_repo(_managed_repo_id), do: {:ok, default_review_policy()}

  @spec configured_review_policy_for_managed_repo(term()) :: {:ok, map()}
  def configured_review_policy_for_managed_repo(managed_repo_id) when is_binary(managed_repo_id) do
    case PolicySet.get_by_managed_repo_name(managed_repo_id, "default", actor: Actor.factory_system_actor()) do
      {:ok, policy_set} ->
        {:ok, normalize_review_policy(policy_set.review_policy)}

      {:error, _reason} ->
        {:ok, default_review_policy()}
    end
  end

  def configured_review_policy_for_managed_repo(_managed_repo_id), do: {:ok, default_review_policy()}

  @spec review_policy_for_project(term()) :: {:ok, map()}
  def review_policy_for_project(project_id) when is_binary(project_id) do
    with {:ok, managed_repo} <- ManagedRepo.get_by_legacy_project_id(project_id, actor: Actor.factory_system_actor()) do
      review_policy_for_managed_repo(managed_repo.id)
    else
      _other -> {:ok, default_review_policy()}
    end
  end

  def review_policy_for_project(_project_id), do: {:ok, default_review_policy()}

  @spec approval_policy_for_managed_repo(term()) :: {:ok, map()}
  def approval_policy_for_managed_repo(managed_repo_id) do
    with {:ok, review_policy} <- review_policy_for_managed_repo(managed_repo_id) do
      {:ok, approval_policy_from_review_policy(review_policy)}
    end
  end

  @spec approval_policy_for_project(term()) :: {:ok, map()}
  def approval_policy_for_project(project_id) do
    with {:ok, review_policy} <- review_policy_for_project(project_id) do
      {:ok, approval_policy_from_review_policy(review_policy)}
    end
  end

  @spec approval_policy_from_review_policy(map()) :: map()
  def approval_policy_from_review_policy(review_policy) when is_map(review_policy) do
    normalized_review_policy = normalize_review_policy(review_policy)
    mode = Map.get(normalized_review_policy, "mode", @approval_mode_approval_required)

    if mode == @approval_mode_auto_post do
      %{
        "mode" => @approval_mode_auto_post,
        "post_behavior" => @approval_mode_auto_post,
        "auto_post" => true,
        "requires_approval" => false,
        "change_request_required" => false,
        "review_threshold" => @review_threshold_auto_post,
        "required_stage" => @required_stage_approval,
        "source" => Map.get(normalized_review_policy, "source", @default_policy_source),
        "supervision_mode" => Map.get(normalized_review_policy, "supervision_mode", @supervision_mode_guided),
        "escalation_status" => Map.get(normalized_review_policy, "escalation_status", @escalation_status_normal),
        "posture_override" => Map.get(normalized_review_policy, "posture_override", false)
      }
    else
      %{
        "mode" => @approval_mode_approval_required,
        "post_behavior" => @approval_mode_approval_required,
        "auto_post" => false,
        "requires_approval" => true,
        "change_request_required" => Map.get(normalized_review_policy, "change_request_required", true),
        "review_threshold" => Map.get(normalized_review_policy, "review_threshold", @review_threshold_human_approval),
        "required_stage" => Map.get(normalized_review_policy, "required_stage", @required_stage_approval),
        "source" => Map.get(normalized_review_policy, "source", @default_policy_source),
        "supervision_mode" => Map.get(normalized_review_policy, "supervision_mode", @supervision_mode_guided),
        "escalation_status" => Map.get(normalized_review_policy, "escalation_status", @escalation_status_normal),
        "posture_override" => Map.get(normalized_review_policy, "posture_override", false)
      }
    end
  end

  def approval_policy_from_review_policy(_review_policy),
    do: approval_policy_from_review_policy(default_review_policy())

  @spec default_review_policy() :: map()
  def default_review_policy do
    %{
      "mode" => @approval_mode_approval_required,
      "requires_human_approval" => true,
      "change_request_required" => true,
      "review_threshold" => @review_threshold_human_approval,
      "required_stage" => @required_stage_approval,
      "source" => @default_policy_source
    }
  end

  defp review_policy_from_repo(managed_repo) do
    integration_settings =
      managed_repo
      |> map_get(:integration_settings, "integration_settings", %{})
      |> normalize_map()

    approval_mode =
      integration_settings
      |> Map.get("support_agent_config", %{})
      |> normalize_map()
      |> Map.get("github_issue_bot", %{})
      |> normalize_map()
      |> Map.get("approval_mode")
      |> normalize_approval_mode()

    if approval_mode == @approval_mode_auto_post do
      %{
        mode: @approval_mode_auto_post,
        requires_human_approval: false,
        change_request_required: false,
        review_threshold: @review_threshold_auto_post,
        required_stage: @required_stage_approval,
        source: @legacy_approval_mode_source
      }
    else
      %{
        mode: @approval_mode_approval_required,
        requires_human_approval: true,
        change_request_required: true,
        review_threshold: @review_threshold_human_approval,
        required_stage: @required_stage_approval,
        source:
          if(approval_mode == @approval_mode_approval_required,
            do: @legacy_approval_mode_source,
            else: @default_policy_source
          )
      }
    end
  end

  defp normalize_approval_mode(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "auto_post" -> @approval_mode_auto_post
      "auto-post" -> @approval_mode_auto_post
      "auto" -> @approval_mode_auto_post
      "approval_required" -> @approval_mode_approval_required
      "approval-required" -> @approval_mode_approval_required
      "manual" -> @approval_mode_approval_required
      _other -> nil
    end
  end

  defp normalize_approval_mode(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_approval_mode()
  end

  defp normalize_approval_mode(_value), do: nil

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

  defp normalize_review_policy(review_policy) when is_map(review_policy) do
    normalized_review_policy = normalize_map(review_policy)

    normalized_review_policy
    |> Map.put_new(
      "change_request_required",
      map_get(review_policy, :change_request_required, "change_request_required", true)
    )
    |> Map.put_new(
      "review_threshold",
      map_get(review_policy, :review_threshold, "review_threshold", @review_threshold_human_approval)
    )
    |> Map.put_new(
      "required_stage",
      map_get(review_policy, :required_stage, "required_stage", @required_stage_approval)
    )
    |> Map.put_new("mode", map_get(review_policy, :mode, "mode", @approval_mode_approval_required))
    |> Map.put_new(
      "requires_human_approval",
      map_get(review_policy, :requires_human_approval, "requires_human_approval", true)
    )
    |> Map.put_new("source", map_get(review_policy, :source, "source", @default_policy_source))
  end

  defp normalize_review_policy(_review_policy), do: default_review_policy()

  defp effective_review_policy(managed_repo_id, configured_review_policy) do
    normalized_review_policy = normalize_review_policy(configured_review_policy)
    repo_posture = repo_posture(managed_repo_id)
    supervision_mode = (repo_posture && repo_posture.supervision_mode) || @supervision_mode_guided
    escalation_status = (repo_posture && repo_posture.escalation_status) || @escalation_status_normal

    base_policy =
      normalized_review_policy
      |> Map.put("configured_source", Map.get(normalized_review_policy, "source", @default_policy_source))
      |> Map.put("supervision_mode", supervision_mode)
      |> Map.put("escalation_status", escalation_status)
      |> Map.put("posture_override", false)

    case supervision_mode do
      mode when mode in [@supervision_mode_directed, @supervision_mode_guided] ->
        base_policy
        |> Map.put("mode", @approval_mode_approval_required)
        |> Map.put("requires_human_approval", true)
        |> Map.put("change_request_required", true)
        |> Map.put("review_threshold", @review_threshold_human_approval)
        |> Map.put("required_stage", @required_stage_approval)
        |> Map.put("source", "repo_posture.#{mode}")
        |> Map.put("posture_override", true)

      @supervision_mode_autonomous when escalation_status == @escalation_status_normal ->
        base_policy
        |> Map.put("mode", @approval_mode_auto_post)
        |> Map.put("requires_human_approval", false)
        |> Map.put("change_request_required", false)
        |> Map.put("review_threshold", @review_threshold_auto_post)
        |> Map.put("required_stage", @required_stage_approval)
        |> Map.put("source", "repo_posture.autonomous")
        |> Map.put("posture_override", true)

      _other ->
        base_policy
    end
  end

  defp repo_posture(managed_repo_id) do
    case RepoPosture.get_by_managed_repo_id(managed_repo_id, actor: Actor.factory_system_actor()) do
      {:ok, repo_posture} -> repo_posture
      _other -> nil
    end
  end
end
