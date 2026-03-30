defmodule JidoCode.Projects.Project do
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Projects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource]

  alias JidoCode.Control.RepoBridge

  postgres do
    table "projects"
    repo JidoCode.Repo
  end

  typescript do
    type_name "Project"
  end

  code_interface do
    define :create
    define :read
    define :get_by_github_full_name, action: :read, get_by: [:github_full_name]
    define :update
  end

  actions do
    defaults [:destroy]

    create :create do
      primary? true
      accept [:name, :github_full_name, :default_branch, :settings]

      change after_action(fn _changeset, project, _context ->
               case RepoBridge.sync_project(project) do
                 {:ok, _managed_repo} -> {:ok, project}
                 {:error, reason} -> {:error, reason}
               end
             end)
    end

    read :read do
      primary? true
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:name, :default_branch, :settings]

      change after_action(fn _changeset, project, _context ->
               case RepoBridge.sync_project(project) do
                 {:ok, _managed_repo} -> {:ok, project}
                 {:error, reason} -> {:error, reason}
               end
             end)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type(:update) do
      authorize_if always()
    end

    policy action_type(:destroy) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :github_full_name, :string do
      allow_nil? false
      constraints min_length: 3, max_length: 255, trim?: true
      public? true
    end

    attribute :default_branch, :string do
      allow_nil? false
      default "main"
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :settings, :map do
      allow_nil? false
      default %{}
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_github_full_name, [:github_full_name]
  end
end
