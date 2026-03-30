defmodule JidoCode.Governance.PolicyBridge do
  @moduledoc """
  Derives the default governance policy set from transitional managed-repo state.
  """

  alias JidoCode.Control.Actor
  alias JidoCode.Governance.PolicySet

  @approval_mode_auto_post "auto_post"
  @approval_mode_approval_required "approval_required"
  @legacy_approval_mode_source "support_agent_config.github_issue_bot.approval_mode"
  @default_policy_source "policy_set.review_policy.default"

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
        source: @legacy_approval_mode_source
      }
    else
      %{
        mode: @approval_mode_approval_required,
        requires_human_approval: true,
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
end
