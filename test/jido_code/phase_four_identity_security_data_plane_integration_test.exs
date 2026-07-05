defmodule JidoCode.PhaseFourIdentitySecurityDataPlaneIntegrationTest do
  use ExUnit.Case, async: false

  alias JidoCode.Accounts.{SessionTokens, UserIdentityStore}
  alias JidoCode.AuthProviders.{ProviderConfigStore, ProviderLogin}
  alias JidoCode.ControlPlane.{GraphTopology, StoreServer}
  alias JidoCode.GitHub.ServiceCredentials
  alias JidoCode.Security.{SecretRefStore, SecretRefs}
  alias JidoCode.Setup.{BootstrapStatus, BootstrapToken, OnboardingReset, OwnerBootstrap, OwnerStore}
  alias JidoCode.Setup.{SystemConfig, SystemConfigPersistence}

  @valid_test_encryption_key "MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE="
  @github_app_env_keys [:github_app_id, :github_app_private_key, :github_webhook_secret, :github_pat]
  @github_system_env_keys ["GITHUB_APP_ID", "GITHUB_APP_PRIVATE_KEY", "GITHUB_WEBHOOK_SECRET", "GITHUB_PAT"]

  setup do
    store_name = :"phase_four_data_plane_store_#{System.unique_integer([:positive])}"
    store_path = Path.join(System.tmp_dir!(), "jido_code_phase_four_data_plane/#{store_name}")

    start_supervised!({StoreServer, name: store_name, id: store_name, path: store_path, reset_policy: :reset_on_start})

    original_env = snapshot_app_env([:control_plane_product_store_server, :system_config_loader, :system_config_saver])
    original_secret_key = Application.get_env(:jido_code, :secret_ref_encryption_key, :__missing__)
    original_github_app_env = snapshot_app_env(@github_app_env_keys)
    original_github_system_env = snapshot_system_env(@github_system_env_keys)

    Application.put_env(:jido_code, :control_plane_product_store_server, store_name)
    Application.put_env(:jido_code, :system_config_loader, &SystemConfigPersistence.load/0)
    Application.put_env(:jido_code, :system_config_saver, &SystemConfigPersistence.save/1)
    Application.put_env(:jido_code, :secret_ref_encryption_key, @valid_test_encryption_key)

    Enum.each(@github_app_env_keys, &Application.delete_env(:jido_code, &1))
    Enum.each(@github_system_env_keys, &System.delete_env/1)

    on_exit(fn ->
      restore_app_env(original_env)
      restore_env(:secret_ref_encryption_key, original_secret_key)
      restore_app_env(original_github_app_env)
      restore_system_env(original_github_system_env)
      File.rm_rf!(store_path)
    end)

    %{store: store_name}
  end

  test "empty embedded store bootstraps owner, issues sessions, links provider identity, and resets cleanly" do
    assert %{state: :bootstrap_required, user_count: 0} = BootstrapStatus.current()

    assert {:ok, bootstrap} =
             OwnerBootstrap.bootstrap(%{
               "email" => "Owner@Example.com",
               "password" => "owner-password-123",
               "password_confirmation" => "owner-password-123"
             })

    assert bootstrap.owner.email == "owner@example.com"
    assert bootstrap.owner.is_admin
    assert {:ok, %{"email" => "owner@example.com"}} = BootstrapToken.verify(bootstrap.token)

    assert {:ok, owner} = OwnerStore.get_by_email("owner@example.com")
    assert {:ok, session_token} = SessionTokens.issue(owner)
    assert {:ok, session_owner} = SessionTokens.verify(session_token)
    assert session_owner.id == owner.id

    assert {:ok, _config} =
             ProviderConfigStore.upsert(%{
               provider: :github,
               provider_host: "github.com",
               enabled: true,
               login_enabled: true,
               allowlist_mode: :none
             })

    assert {:ok, provider_login} =
             ProviderLogin.sign_in(%{
               provider: :github,
               provider_host: "github.com",
               provider_subject: "github-user-123",
               provider_login: "owner",
               provider_email: "owner@example.com",
               email_verified: true
             })

    assert provider_login.resolution == :linked_by_email
    assert {:ok, provider_session_owner} = SessionTokens.verify(provider_login.token)
    assert provider_session_owner.id == owner.id

    assert {:ok, identity} =
             UserIdentityStore.get_by_provider_subject(:github, "github.com", "github-user-123")

    assert identity.user_id == owner.id

    assert {:ok, _config} =
             SystemConfig.save(%SystemConfig{
               onboarding_completed: true,
               onboarding_step: 8,
               onboarding_state: %{"2" => %{"owner_email" => "owner@example.com"}},
               default_environment: :sprite,
               workspace_root: nil
             })

    assert %{state: :ready, primary_user_email: "owner@example.com"} = BootstrapStatus.current()

    assert {:ok, reset} = OnboardingReset.reset(:full)
    assert reset.cleared_owner_count == 1

    assert {:ok, []} = OwnerStore.list_users()
    assert %{state: :bootstrap_required, user_count: 0} = BootstrapStatus.current()
  end

  test "security records are queryable while plaintext and ciphertext stay out of security triples", %{store: store} do
    assert {:ok, provider_config} =
             ProviderConfigStore.upsert(%{
               provider: :github,
               provider_host: "github.com",
               enabled: true,
               login_enabled: false,
               allowlist_mode: :none,
               broker_issuer: "https://broker.example.com"
             })

    initial_value = "ghp-phase-four-initial-#{System.unique_integer([:positive])}"
    rotated_value = "ghp-phase-four-rotated-#{System.unique_integer([:positive])}"
    secret_name = ServiceCredentials.service_secret_ref_name(:pat)

    assert {:ok, created} =
             SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: secret_name,
               value: initial_value,
               source: :onboarding
             })

    assert {:ok, rotated} =
             SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: secret_name,
               value: rotated_value,
               source: :rotation
             })

    assert rotated.id == created.id
    assert rotated.key_version == 2

    assert {:ok, persisted_config} = ProviderConfigStore.get_by_provider_host(:github, "github.com")
    assert persisted_config.id == provider_config.id
    assert persisted_config.broker_issuer == "https://broker.example.com"

    assert {:ok, ^rotated_value, diagnostics} = ServiceCredentials.resolve(:pat)
    assert diagnostics.selected_source == :secret_ref
    assert diagnostics.secret_ref_key_version == 2

    assert {:ok, metadata_rows} = SecretRefs.list_secret_metadata()
    assert %{id: secret_id, key_version: 2, source: :rotation} = Enum.find(metadata_rows, &(&1.name == secret_name))

    assert {:ok, secret_ref} = SecretRefStore.get_by_scope_name(:integration, secret_name)
    assert secret_ref.id == secret_id
    assert is_binary(secret_ref.ciphertext)
    refute secret_ref.ciphertext in [initial_value, rotated_value]

    assert {:ok, audits} = SecretRefs.list_secret_lifecycle_audits()
    assert Enum.any?(audits, &(&1.secret_ref_id == secret_id and &1.action_type == :create))
    assert Enum.any?(audits, &(&1.secret_ref_id == secret_id and &1.action_type == :rotate))

    refute_security_graph_literals_include(store, [initial_value, rotated_value, secret_ref.ciphertext])

    assert {:ok, revoked} = SecretRefs.revoke_operational_secret(%{id: secret_id})
    assert revoked.id == secret_id

    assert {:ok, audits_after_revoke} = SecretRefs.list_secret_lifecycle_audits()
    assert Enum.any?(audits_after_revoke, &(&1.secret_ref_id == secret_id and &1.action_type == :revoke))
    refute_security_graph_literals_include(store, [initial_value, rotated_value, secret_ref.ciphertext])
  end

  defp refute_security_graph_literals_include(store, forbidden_values) do
    literals = security_graph_literals(store)

    Enum.each(forbidden_values, fn forbidden_value ->
      refute forbidden_value in literals
    end)
  end

  defp security_graph_literals(store) do
    {:ok, graph_resource} = GraphTopology.graph_resource(:security)

    {:ok, literals} =
      StoreServer.with_store(store, fn opened_store ->
        with {:ok, graph_id} <- TripleStore.Adapter.lookup_term_id(opened_store.db, graph_resource) do
          opened_store.db
          |> TripleStore.QuadOperations.lookup_quads({:var, :var, :var, :bound}, %{g: graph_id})
          |> Enum.flat_map(&literal_value(opened_store, &1))
        else
          _other -> []
        end
      end)

    literals
  end

  defp literal_value(opened_store, {_subject_id, _predicate_id, object_id, _graph_id}) do
    case TripleStore.Adapter.id_to_term(opened_store.db, object_id) do
      {:ok, %RDF.Literal{} = literal} -> [to_string(RDF.Literal.value(literal))]
      _other -> []
    end
  end

  defp snapshot_app_env(keys) do
    Map.new(keys, fn key -> {key, Application.get_env(:jido_code, key, :__missing__)} end)
  end

  defp restore_app_env(snapshot) when is_map(snapshot) do
    Enum.each(snapshot, fn {key, value} -> restore_env(key, value) end)
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)

  defp snapshot_system_env(keys) do
    Map.new(keys, fn key -> {key, System.get_env(key) || :__missing__} end)
  end

  defp restore_system_env(snapshot) do
    Enum.each(snapshot, fn
      {key, :__missing__} -> System.delete_env(key)
      {key, value} -> System.put_env(key, value)
    end)
  end
end
