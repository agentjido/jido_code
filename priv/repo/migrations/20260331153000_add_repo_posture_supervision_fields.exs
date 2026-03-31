defmodule JidoCode.Repo.Migrations.AddRepoPostureSupervisionFields do
  @moduledoc """
  Adds supervision and escalation fields to repo posture records.
  """

  use Ecto.Migration

  def up do
    alter table(:repo_postures) do
      add :supervision_mode, :text, null: false, default: "guided"
      add :escalation_status, :text, null: false, default: "normal"
      add :algedonic_check_id, references(:posture_checks, type: :uuid, prefix: "public")
    end

    alter table(:posture_checks) do
      add :threat_level, :text, null: false, default: "none"
      add :escalation_mode, :text, null: false, default: "none"
    end

    create index(:repo_postures, [:algedonic_check_id], name: "repo_postures_algedonic_check_id_index")
  end

  def down do
    drop_if_exists index(:repo_postures, [:algedonic_check_id], name: "repo_postures_algedonic_check_id_index")

    alter table(:posture_checks) do
      remove :escalation_mode
      remove :threat_level
    end

    alter table(:repo_postures) do
      remove :algedonic_check_id
      remove :escalation_status
      remove :supervision_mode
    end
  end
end
