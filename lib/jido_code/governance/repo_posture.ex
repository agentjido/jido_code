defmodule JidoCode.Governance.RepoPosture do
  # covers: architecture.repo_posture.repo_posture_summary_tracks_supervision_signals
  @moduledoc false

  use JidoCode.ControlPlane.RecordStruct

  alias JidoCode.Governance.RecordStore

  @spec get_by_managed_repo_id(String.t(), keyword()) :: {:ok, t() | nil} | {:error, term()}
  def get_by_managed_repo_id(managed_repo_id, opts \\ []) do
    RecordStore.get_repo_posture_by_managed_repo_id(managed_repo_id, opts)
  end
end
