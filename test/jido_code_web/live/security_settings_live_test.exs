defmodule JidoCodeWeb.SecuritySettingsLiveTest do
  use JidoCodeWeb.ConnCase, async: false

  require Ash.Query

  import Phoenix.LiveViewTest

  alias AshAuthentication.{Info, Jwt, Strategy}
  alias AshAuthentication.TokenResource.Actions
  alias JidoCode.Accounts
  alias JidoCode.Accounts.ApiKey
  alias JidoCode.Accounts.Token
  alias JidoCode.Accounts.User
  alias JidoCode.GitHub.Repo
  alias JidoCode.Security.SecretRefs

  test "security tab exposes expiry metadata and revocation controls that invalidate bearer and api key auth",
       %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, session_token, owner} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    %{api_key: api_key, api_key_record: api_key_record} = issue_api_key(owner)

    {:ok, %{"jti" => session_jti}} = Jwt.peek(session_token)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/settings/security", on_error: :warn)

    assert has_element?(view, "#settings-security-token-expires-at-#{session_jti}")
    assert has_element?(view, "#settings-security-api-key-expires-at-#{api_key_record.id}")

    view
    |> element("#settings-security-revoke-token-#{session_jti}")
    |> render_click()

    assert has_element?(view, "#settings-security-token-status-#{session_jti}", "Revoked")
    refute has_element?(view, "#settings-security-token-revoked-at-#{session_jti}", "Not revoked")

    refute Actions.valid_jti?(Token, session_jti)

    view
    |> element("#settings-security-revoke-api-key-#{api_key_record.id}")
    |> render_click()

    assert has_element?(view, "#settings-security-api-key-status-#{api_key_record.id}", "Revoked")

    refute has_element?(
             view,
             "#settings-security-api-key-revoked-at-#{api_key_record.id}",
             "Not revoked"
           )

    api_key_strategy = Info.strategy!(User, :api_key)

    assert {:error, _reason} =
             Strategy.action(
               api_key_strategy,
               :sign_in,
               %{"api_key" => api_key}
             )

    assert has_element?(view, "#settings-security-audit-log", "revoked at")
  end

  test "failed revocation keeps state unchanged and returns typed recovery instructions", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token, owner} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    %{api_key: api_key, api_key_record: api_key_record} = issue_api_key(owner)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/settings/security", on_error: :warn)

    view
    |> element("#settings-security-revoke-api-key-#{api_key_record.id}")
    |> render_click()

    revoked_api_key = read_api_key!(api_key_record.id)
    assert %DateTime{} = revoked_api_key.revoked_at

    view
    |> element("#settings-security-revoke-api-key-#{api_key_record.id}")
    |> render_click()

    assert has_element?(
             view,
             "#settings-security-revocation-error-type",
             "api_key_already_revoked"
           )

    assert has_element?(view, "#settings-security-revocation-recovery", "already revoked")

    unchanged_api_key = read_api_key!(api_key_record.id)
    assert DateTime.compare(unchanged_api_key.revoked_at, revoked_api_key.revoked_at) == :eq

    api_key_strategy = Info.strategy!(User, :api_key)

    assert {:error, _reason} =
             Strategy.action(
               api_key_strategy,
               :sign_in,
               %{"api_key" => api_key}
             )
  end

  test "security tab persists encrypted SecretRef metadata and never renders plaintext values", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token, _owner} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/settings/security", on_error: :warn)

    secret_name = "github/webhook_secret_#{System.unique_integer([:positive])}"
    plaintext_value = "very-secret-value-#{System.unique_integer([:positive])}"

    view
    |> form("#settings-security-secret-form", %{
      "security_secret" => %{
        "scope" => "integration",
        "name" => secret_name,
        "value" => plaintext_value
      }
    })
    |> render_submit()

    assert has_element?(view, "#settings-security-secret-metadata", secret_name)
    assert has_element?(view, "#settings-security-secret-metadata", "integration")
    refute has_element?(view, "#settings-security-secret-metadata", plaintext_value)
    refute has_element?(view, "#settings-security-secret-value[value='#{plaintext_value}']")

    assert {:ok, metadata_rows} = SecretRefs.list_secret_metadata()
    secret_id = metadata_rows |> Enum.find(&(&1.name == secret_name)) |> Map.fetch!(:id)

    assert has_element?(view, "#settings-security-secret-key-version-#{secret_id}", "1")
    assert has_element?(view, "#settings-security-secret-rotated-at-#{secret_id}")
    assert has_element?(view, "#settings-security-secret-audit-log", "CREATE")
    assert has_element?(view, "#settings-security-secret-audit-log", "outcome=succeeded")
    assert has_element?(view, "#settings-security-secret-audit-log", "owner@example.com")

    rotated_plaintext_value = "rotated-secret-value-#{System.unique_integer([:positive])}"

    view
    |> form("#settings-security-secret-form", %{
      "security_secret" => %{
        "scope" => "integration",
        "name" => secret_name,
        "value" => rotated_plaintext_value
      }
    })
    |> render_submit()

    assert has_element?(view, "#settings-security-secret-key-version-#{secret_id}", "2")
    assert has_element?(view, "#settings-security-secret-source-value-#{secret_id}", "rotation")
    assert has_element?(view, "#settings-security-secret-audit-log", "ROTATE")
    refute has_element?(view, "#settings-security-secret-metadata", rotated_plaintext_value)

    view
    |> element("#settings-security-secret-revoke-#{secret_id}")
    |> render_click()

    refute has_element?(view, "#settings-security-secret-metadata", secret_name)
    assert has_element?(view, "#settings-security-secret-audit-log", "REVOKE")
  end

  test "security tab rotates provider credentials with before and after verification status", %{
    conn: _conn
  } do
    original_validator =
      Application.get_env(:jido_code, :provider_credential_rotation_validator, :__missing__)

    on_exit(fn ->
      restore_env(:provider_credential_rotation_validator, original_validator)
    end)

    Application.put_env(:jido_code, :provider_credential_rotation_validator, fn
      %{stage: :before} ->
        {:ok, "Pre-rotation validation passed."}

      %{stage: :after} ->
        {:ok, "Post-rotation validation passed."}
    end)

    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token, _owner} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    provider_secret_name = SecretRefs.provider_secret_ref_name(:anthropic)

    assert {:ok, _metadata} =
             SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: provider_secret_name,
               value: "sk-ant-initial-#{System.unique_integer([:positive])}",
               source: :onboarding
             })

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/settings/security", on_error: :warn)

    view
    |> form("#settings-security-provider-rotation-form", %{
      "security_provider_rotation" => %{
        "provider" => "anthropic",
        "value" => "sk-ant-rotated-#{System.unique_integer([:positive])}"
      }
    })
    |> render_submit()

    assert has_element?(view, "#settings-security-provider-rotation-before-status", "Passed")
    assert has_element?(view, "#settings-security-provider-rotation-after-status", "Passed")
    assert has_element?(view, "#settings-security-provider-rotation-rollback-status", "No")
    assert has_element?(view, "#settings-security-provider-rotation-continuity-alarm", "None")

    assert {:ok, provider_context} = SecretRefs.provider_credential_context(:anthropic)
    assert provider_context.key_version == 2
  end

  test "security tab rolls provider credential references back when post-rotation validation fails", %{
    conn: _conn
  } do
    original_validator =
      Application.get_env(:jido_code, :provider_credential_rotation_validator, :__missing__)

    on_exit(fn ->
      restore_env(:provider_credential_rotation_validator, original_validator)
    end)

    Application.put_env(:jido_code, :provider_credential_rotation_validator, fn
      %{stage: :before} ->
        {:ok, "Pre-rotation validation passed."}

      %{stage: :after} ->
        {:error, :provider_unreachable}
    end)

    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token, _owner} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    provider_secret_name = SecretRefs.provider_secret_ref_name(:openai)

    assert {:ok, _metadata} =
             SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: provider_secret_name,
               value: "sk-initial-#{System.unique_integer([:positive])}",
               source: :onboarding
             })

    assert {:ok, context_before_rotation} = SecretRefs.provider_credential_context(:openai)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/settings/security", on_error: :warn)

    view
    |> form("#settings-security-provider-rotation-form", %{
      "security_provider_rotation" => %{
        "provider" => "openai",
        "value" => "sk-rotated-#{System.unique_integer([:positive])}"
      }
    })
    |> render_submit()

    assert has_element?(
             view,
             "#settings-security-provider-rotation-error-type",
             "provider_rotation_validation_failed"
           )

    assert has_element?(view, "#settings-security-provider-rotation-before-status", "Passed")
    assert has_element?(view, "#settings-security-provider-rotation-after-status", "Failed")
    assert has_element?(view, "#settings-security-provider-rotation-rollback-status", "Yes")
    assert has_element?(view, "#settings-security-provider-rotation-continuity-alarm", "None")

    assert {:ok, context_after_rotation} = SecretRefs.provider_credential_context(:openai)
    assert context_after_rotation.key_version == context_before_rotation.key_version
    assert context_after_rotation.ciphertext == context_before_rotation.ciphertext
  end

  test "security tab blocks secret persistence with typed remediation when encryption config is missing",
       %{conn: _conn} do
    original_key = Application.get_env(:jido_code, :secret_ref_encryption_key, :__missing__)

    on_exit(fn ->
      restore_env(:secret_ref_encryption_key, original_key)
    end)

    Application.delete_env(:jido_code, :secret_ref_encryption_key)

    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token, _owner} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/settings/security", on_error: :warn)

    secret_name = "missing/encryption_#{System.unique_integer([:positive])}"

    view
    |> form("#settings-security-secret-form", %{
      "security_secret" => %{
        "scope" => "integration",
        "name" => secret_name,
        "value" => "plaintext-that-must-not-persist"
      }
    })
    |> render_submit()

    assert has_element?(
             view,
             "#settings-security-secret-error-type",
             "secret_encryption_unavailable"
           )

    assert has_element?(
             view,
             "#settings-security-secret-error-recovery",
             "JIDO_CODE_SECRET_REF_ENCRYPTION_KEY"
           )

    refute has_element?(view, "#settings-security-secret-metadata", secret_name)
  end

  test "security tab treats secret save as failed when lifecycle audit persistence fails", %{conn: _conn} do
    original_audit_persister =
      Application.get_env(:jido_code, :secret_lifecycle_audit_persister, :__missing__)

    on_exit(fn ->
      restore_env(:secret_lifecycle_audit_persister, original_audit_persister)
    end)

    Application.put_env(:jido_code, :secret_lifecycle_audit_persister, fn _attributes ->
      {:error, :forced_audit_failure}
    end)

    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token, _owner} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/settings/security", on_error: :warn)

    secret_name = "audit/failure_#{System.unique_integer([:positive])}"

    view
    |> form("#settings-security-secret-form", %{
      "security_secret" => %{
        "scope" => "integration",
        "name" => secret_name,
        "value" => "must-not-persist-#{System.unique_integer([:positive])}"
      }
    })
    |> render_submit()

    assert has_element?(
             view,
             "#settings-security-secret-error-type",
             "secret_audit_persistence_failed"
           )

    refute has_element?(view, "#settings-security-secret-metadata", secret_name)
    assert has_element?(view, "#settings-security-secret-audit-log", "No secret lifecycle events recorded yet.")
  end

  test "github settings render masked placeholders for known secret patterns", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token, _owner} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    unique = System.unique_integer([:positive])
    secret = "sk-test-0123456789abcdef"

    {:ok, repo} =
      Repo.create(%{
        owner: "owner-#{unique}",
        name: "repo-#{unique}",
        settings: %{"Authorization: Bearer #{secret}" => true}
      })

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/settings/github", on_error: :warn)

    assert has_element?(view, "#settings-github-repo-settings-#{repo.id}", "[REDACTED")
    refute has_element?(view, "#settings-github-repo-settings-#{repo.id}", secret)
    refute has_element?(view, "#settings-github-repo-security-alert-#{repo.id}")
  end

  test "github settings suppress unsafe post-render values and raise security alert", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token, _owner} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    unique = System.unique_integer([:positive])
    leaked_token = "xoxb-12345678901234567890"

    {:ok, repo} =
      Repo.create(%{
        owner: "owner-alert-#{unique}",
        name: "repo-alert-#{unique}",
        settings: %{"#{leaked_token}" => "enabled"}
      })

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/settings/github", on_error: :warn)

    assert has_element?(view, "#settings-github-repo-settings-#{repo.id}", "[SENSITIVE CONTENT SUPPRESSED]")
    assert has_element?(view, "#settings-github-repo-security-alert-#{repo.id}", "Security alert")
    refute has_element?(view, "#settings-github-repo-settings-#{repo.id}", leaked_token)
  end

  defp register_owner(email, password) do
    strategy = Info.strategy!(User, :password)

    {:ok, _owner} =
      Strategy.action(
        strategy,
        :register,
        %{
          "email" => email,
          "password" => password,
          "password_confirmation" => password
        },
        context: %{token_type: :sign_in}
      )

    :ok
  end

  defp authenticate_owner_conn(email, password) do
    strategy = Info.strategy!(User, :password)

    {:ok, owner} =
      Strategy.action(
        strategy,
        :sign_in,
        %{"email" => email, "password" => password},
        context: %{token_type: :sign_in}
      )

    token =
      owner
      |> Map.get(:__metadata__, %{})
      |> Map.fetch!(:token)

    auth_response = build_conn() |> get(owner_sign_in_with_token_path(strategy, token))
    assert redirected_to(auth_response, 302) == "/"
    session_token = get_session(auth_response, "user_token")
    assert is_binary(session_token)
    {recycle(auth_response), session_token, owner}
  end

  defp issue_api_key(owner) do
    expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

    {:ok, api_key_record} =
      Ash.create(
        ApiKey,
        %{user_id: owner.id, expires_at: expires_at},
        domain: Accounts,
        authorize?: false
      )

    api_key =
      api_key_record
      |> Map.get(:__metadata__, %{})
      |> Map.fetch!(:plaintext_api_key)

    %{api_key: api_key, api_key_record: api_key_record}
  end

  defp read_api_key!(api_key_id) do
    query =
      ApiKey
      |> Ash.Query.filter(id == ^api_key_id)
      |> Ash.Query.limit(1)

    {:ok, [api_key]} = Ash.read(query, domain: Accounts, authorize?: false)

    api_key
  end

  defp owner_sign_in_with_token_path(strategy, token) do
    strategy_path =
      strategy
      |> Strategy.routes()
      |> Enum.find_value(fn
        {path, :sign_in_with_token} -> path
        _other -> nil
      end)

    path =
      Path.join(
        "/auth",
        String.trim_leading(strategy_path || "/user/password/sign_in_with_token", "/")
      )

    query = URI.encode_query(%{"token" => token})
    "#{path}?#{query}"
  end

  defp restore_env(key, :__missing__) do
    Application.delete_env(:jido_code, key)
  end

  defp restore_env(key, value) do
    Application.put_env(:jido_code, key, value)
  end
end
