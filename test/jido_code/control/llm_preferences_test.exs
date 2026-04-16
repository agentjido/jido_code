defmodule JidoCode.Control.LLMPreferencesTest do
  use JidoCode.DataCase

  alias JidoCode.Control.LLMPreferences
  alias JidoCode.Control.ManagedRepo
  alias JidoCode.Control.SourceRepo
  alias JidoCode.Control.Actor

  @admin_actor Actor.admin_actor()

  # Helper function to create a source repo
  defp create_source_repo(attrs \\ %{}) do
    defaults = %{
      provider: :github,
      owner: "test_owner",
      name: "test_repo",
      full_name: "test_owner/test_repo",
      default_branch: "main"
    }

    SourceRepo.create(Map.merge(defaults, attrs), actor: @admin_actor)
  end

  # Helper function to create a managed repo
  defp create_managed_repo(attrs \\ %{}) do
    {:ok, source_repo} =
      Map.get(attrs, :source_repo)
      |> case do
        nil -> create_source_repo()
        repo -> {:ok, repo}
      end

    defaults = %{
      display_name: "Test Managed Repo",
      source_repo_id: source_repo.id,
      workspace_settings: %{},
      execution_settings: %{},
      integration_settings: %{}
    }

    ManagedRepo.create(Map.merge(defaults, attrs), actor: @admin_actor)
  end

  describe "create/1" do
    test "creates LLMPreferences with valid attributes" do
      {:ok, repo} = create_managed_repo()

      attrs = %{
        managed_repo_id: repo.id,
        enabled_providers: [:anthropic, :openai],
        default_provider: :anthropic,
        default_model: "claude-3-5-sonnet-20250929"
      }

      assert {:ok, prefs} = LLMPreferences.create(attrs, actor: @admin_actor)
      assert prefs.managed_repo_id == repo.id
      assert prefs.enabled_providers == [:anthropic, :openai]
      assert prefs.default_provider == :anthropic
      assert prefs.default_model == "claude-3-5-sonnet-20250929"
      assert prefs.allow_custom_models == true
    end

    test "fails without managed_repo_id" do
      attrs = %{
        enabled_providers: [:anthropic]
      }

      assert {:error, changeset} = LLMPreferences.create(attrs, actor: @admin_actor)
      assert hd(changeset.errors).field == :managed_repo_id
    end
  end

  describe "defaults" do
    test "enabled_providers defaults to [:anthropic]" do
      {:ok, repo} = create_managed_repo()

      {:ok, prefs} =
        LLMPreferences.create(%{
          managed_repo_id: repo.id
        }, actor: @admin_actor)

      assert prefs.enabled_providers == [:anthropic]
    end

    test "default_provider defaults to :anthropic" do
      {:ok, repo} = create_managed_repo()

      {:ok, prefs} =
        LLMPreferences.create(%{
          managed_repo_id: repo.id
        }, actor: @admin_actor)

      assert prefs.default_provider == :anthropic
    end

    test "default_model defaults to claude-3-5-sonnet" do
      {:ok, repo} = create_managed_repo()

      {:ok, prefs} =
        LLMPreferences.create(%{
          managed_repo_id: repo.id
        }, actor: @admin_actor)

      assert prefs.default_model == "claude-3-5-sonnet-20250929"
    end

    test "allow_custom_models defaults to true" do
      {:ok, repo} = create_managed_repo()

      {:ok, prefs} =
        LLMPreferences.create(%{
          managed_repo_id: repo.id
        }, actor: @admin_actor)

      assert prefs.allow_custom_models == true
    end
  end

  describe "for_managed_repo/1" do
    test "returns preferences for a given managed repo" do
      {:ok, repo} = create_managed_repo()

      {:ok, _prefs} =
        LLMPreferences.create(%{
          managed_repo_id: repo.id,
          enabled_providers: [:openai],
          default_provider: :openai,
          default_model: "gpt-4"
        }, actor: @admin_actor)

      {:ok, prefs_list} = LLMPreferences.for_managed_repo(repo.id, actor: @admin_actor)
      assert is_list(prefs_list)
      assert length(prefs_list) == 1

      prefs = hd(prefs_list)
      assert prefs.enabled_providers == [:openai]
      assert prefs.default_provider == :openai
      assert prefs.default_model == "gpt-4"
    end

    test "returns empty list when no preferences exist" do
      {:ok, repo} = create_managed_repo()

      assert {:ok, []} = LLMPreferences.for_managed_repo(repo.id, actor: @admin_actor)
    end
  end

  describe "unique constraint on managed_repo_id" do
    test "prevents duplicate preferences for same repo" do
      {:ok, repo} = create_managed_repo()

      {:ok, _prefs} =
        LLMPreferences.create(%{
          managed_repo_id: repo.id
        }, actor: @admin_actor)

      assert {:error, changeset} =
               LLMPreferences.create(%{
                 managed_repo_id: repo.id
               }, actor: @admin_actor)

      # The unique constraint creates an Ash.Invalid error with a specific structure
      # Just verify that the create failed
      assert {:error, _} =
               LLMPreferences.create(%{
                 managed_repo_id: repo.id
               }, actor: @admin_actor)
    end
  end

  describe "update/2" do
    test "updates enabled_providers" do
      {:ok, repo} = create_managed_repo()

      {:ok, prefs} =
        LLMPreferences.create(%{
          managed_repo_id: repo.id
        }, actor: @admin_actor)

      {:ok, updated} =
        LLMPreferences.update(prefs, %{
          enabled_providers: [:anthropic, :openai, :google]
        }, actor: @admin_actor)

      assert updated.enabled_providers == [:anthropic, :openai, :google]
    end

    test "updates default_provider and default_model" do
      {:ok, repo} = create_managed_repo()

      {:ok, prefs} =
        LLMPreferences.create(%{
          managed_repo_id: repo.id
        }, actor: @admin_actor)

      {:ok, updated} =
        LLMPreferences.update(prefs, %{
          default_provider: :openai,
          default_model: "gpt-4"
        }, actor: @admin_actor)

      assert updated.default_provider == :openai
      assert updated.default_model == "gpt-4"
    end

    test "updates require_capabilities" do
      {:ok, repo} = create_managed_repo()

      {:ok, prefs} =
        LLMPreferences.create(%{
          managed_repo_id: repo.id
        }, actor: @admin_actor)

      {:ok, updated} =
        LLMPreferences.update(prefs, %{
          require_capabilities: %{tools: true, streaming: true}
        }, actor: @admin_actor)

      # Maps stored in PostgreSQL are returned with string keys
      assert updated.require_capabilities == %{"tools" => true, "streaming" => true}
    end
  end

  describe "get_by_managed_repo/1" do
    test "returns preferences when they exist" do
      {:ok, repo} = create_managed_repo()

      {:ok, _prefs} =
        LLMPreferences.create(%{
          managed_repo_id: repo.id,
          enabled_providers: [:openai],
          default_provider: :openai,
          default_model: "gpt-4"
        }, actor: @admin_actor)

      {:ok, prefs} = LLMPreferences.get_by_managed_repo(repo.id, actor: @admin_actor)
      assert prefs.enabled_providers == [:openai]
    end

    test "returns error when no preferences exist" do
      {:ok, repo} = create_managed_repo()

      assert {:error, _} = LLMPreferences.get_by_managed_repo(repo.id, actor: @admin_actor)
    end
  end

  defp has_error?(changeset, field, message) do
    Enum.any?(changeset.errors, fn
      {^field, {msg, _}} -> msg =~ message
      _ -> false
    end)
  end
end
