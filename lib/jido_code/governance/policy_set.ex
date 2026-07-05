defmodule JidoCode.Governance.PolicySet do
  # covers: architecture.run_governance.policy_sets_attach_to_managed_repo
  @moduledoc false

  use JidoCode.ControlPlane.RecordStruct

  alias JidoCode.Control.Actor
  alias JidoCode.Governance.RecordStore

  @write_actor_classes [:admin, :operator, :factory_system, :managed_repo_orchestrator]

  @spec get_by_managed_repo_name(String.t(), String.t(), keyword()) :: {:ok, t() | nil} | {:error, term()}
  def get_by_managed_repo_name(managed_repo_id, name, opts \\ []),
    do: RecordStore.get_policy_set_by_managed_repo_name(managed_repo_id, name, opts)

  @spec upsert_default_for_managed_repo(map(), keyword()) :: {:ok, t()} | {:error, term()}
  def upsert_default_for_managed_repo(attrs, opts \\ []) when is_map(attrs) do
    if Actor.allowed?(Keyword.get(opts, :actor), @write_actor_classes) do
      attrs
      |> Map.put_new(:name, "default")
      |> RecordStore.upsert_policy_set(opts)
    else
      {:error, forbidden_error()}
    end
  end

  defp forbidden_error do
    %{
      type: :forbidden,
      reason: :missing_allowed_actor,
      message: "policy-set mutation requires an allowed actor"
    }
  end
end
