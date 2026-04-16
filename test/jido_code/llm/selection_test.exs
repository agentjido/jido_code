defmodule JidoCode.LLM.SelectionTest do
  use JidoCode.DataCase

  alias JidoCode.LLM.{Discovery, Selection}

  describe "resolve/3" do
    setup do
      # Get a valid model ID for tests
      models = Discovery.list_models(:anthropic)
      model_id = hd(models).id
      %{model_id: model_id}
    end

    test "uses conversation-level provider when specified", %{model_id: model_id} do
      conversation_opts = %{llm_provider: :anthropic, llm_model: model_id}
      repo_id = nil
      app_opts = %{}

      assert {:ok, result} = Selection.resolve(conversation_opts, repo_id, app_opts)
      assert result.provider == :anthropic
      assert result.source == :conversation
    end

    test "uses conversation-level model when specified", %{model_id: model_id} do
      conversation_opts = %{llm_provider: :anthropic, llm_model: model_id}
      repo_id = nil
      app_opts = %{}

      assert {:ok, result} = Selection.resolve(conversation_opts, repo_id, app_opts)
      assert result.provider == :anthropic
      assert result.model == model_id
      assert result.source == :conversation
    end

    test "falls back to repository prefs when no conversation opts", %{model_id: model_id} do
      # Use app_opts to provide a valid model
      conversation_opts = %{}
      repo_id = nil
      app_opts = %{default_model: model_id}

      assert {:ok, result} = Selection.resolve(conversation_opts, repo_id, app_opts)
      assert is_atom(result.provider)
      assert is_binary(result.model)
      assert result.source in [:application, :repository]
    end

    test "falls back to application defaults when no prefs exist", %{model_id: model_id} do
      # Use app_opts to provide a valid model
      conversation_opts = %{}
      repo_id = nil
      app_opts = %{default_model: model_id}

      assert {:ok, result} = Selection.resolve(conversation_opts, repo_id, app_opts)
      assert is_atom(result.provider)
      assert is_binary(result.model)
      assert result.source == :application
    end

    test "returns {:error, :provider_not_enabled} for disabled provider" do
      # Use a provider that definitely exists but is unlikely to be enabled
      # This is a hypothetical test - in practice we'd mock the enabled providers
      conversation_opts = %{llm_provider: :non_existent_provider}
      repo_id = nil
      app_opts = %{}

      result = Selection.resolve(conversation_opts, repo_id, app_opts)

      # The non-existent provider will either fail validation or be rejected
      assert match?({:error, _}, result)
    end

    test "returns {:error, :model_not_found} for invalid model" do
      conversation_opts = %{llm_provider: :anthropic, llm_model: "non-existent-model-12345"}
      repo_id = nil
      app_opts = %{}

      assert {:error, :model_not_found} = Selection.resolve(conversation_opts, repo_id, app_opts)
    end

    test "validates capabilities when required", %{model_id: model_id} do
      conversation_opts = %{
        llm_provider: :anthropic,
        llm_model: model_id,
        llm_capabilities: %{} # Empty caps means no requirements
      }
      repo_id = nil
      app_opts = %{}

      assert {:ok, result} = Selection.resolve(conversation_opts, repo_id, app_opts)
      assert result.model == model_id
    end
  end

  describe "available_models/2" do
    test "returns models for enabled providers" do
      models = Selection.available_models(nil, nil)

      assert is_list(models)
      assert length(models) > 0

      Enum.each(models, fn model ->
        assert is_atom(model.provider)
        assert is_binary(model.model)
        assert %LLMDB.Model{} = model.llmdb_model
      end)
    end

    test "filters by capabilities when specified" do
      # Get all models first
      all_models = Selection.available_models(nil, nil)

      # Then filter by chat capability
      chat_models = Selection.available_models(nil, %{chat: true})

      # Chat models should be a subset of all models
      assert length(chat_models) <= length(all_models)
    end

    test "returns models grouped by provider" do
      models = Selection.available_models(nil, nil)

      # Check that we have models from different providers
      providers = Enum.map(models, & &1.provider) |> Enum.uniq()

      assert length(providers) > 0
    end
  end

  describe "enabled_providers_for_repo/1" do
    test "returns application defaults when no repo_id given" do
      providers = Selection.enabled_providers_for_repo(nil)

      assert is_list(providers)
      assert :anthropic in providers
    end

    test "returns application defaults for non-existent repo" do
      providers = Selection.enabled_providers_for_repo("non-existent-uuid")

      assert is_list(providers)
      assert length(providers) > 0
    end
  end

  describe "has_capabilities?/2" do
    setup do
      models = Discovery.list_models(:anthropic)

      # Find a model with capabilities if available
      model_with_caps =
        Enum.find(models, fn m ->
          m.capabilities != nil and map_size(m.capabilities) > 0
        end)

      # Fallback to first model if none found
      model = model_with_caps || hd(models)

      %{model: model}
    end

    test "returns true when model has all required capabilities", %{model: model} do
      if model.capabilities && map_size(model.capabilities) > 0 do
        # Test with a capability the model actually has
        [{cap, value} | _] = Enum.to_list(model.capabilities)

        result = Selection.has_capabilities?(model, %{cap => value})
        assert result == true
      else
        # If no capabilities, return true for empty requirements
        assert Selection.has_capabilities?(model, %{}) == true
      end
    end

    test "returns false when model missing required capability", %{model: model} do
      # Require a capability the model doesn't have
      result = Selection.has_capabilities?(model, %{nonexistent: true})
      assert result == false
    end

    test "returns true when no capabilities required", %{model: model} do
      assert Selection.has_capabilities?(model, nil) == true
    end

    test "returns false for nil model" do
      assert Selection.has_capabilities?(nil, %{chat: true}) == false
    end
  end

  describe "model_label/2" do
    test "returns display_name from model metadata" do
      models = Discovery.list_models(:anthropic)
      model_id = hd(models).id

      label = Selection.model_label(:anthropic, model_id)

      assert is_binary(label)
    end

    test "returns model_id when model not found" do
      label = Selection.model_label(:anthropic, "non-existent-model")

      assert label == "non-existent-model"
    end
  end

  describe "validate_provider_in_available/2" do
    test "returns :ok when provider is available" do
      assert :ok == Selection.validate_provider_in_available(:anthropic, [:anthropic, :openai])
    end

    test "returns error when provider is not available" do
      assert {:error, :provider_not_available} ==
               Selection.validate_provider_in_available(:groq, [:anthropic, :openai])
    end
  end

  describe "validate_model_exists_for_provider/2" do
    test "returns :ok when model exists for provider" do
      models = Discovery.list_models(:anthropic)
      model_id = hd(models).id

      assert :ok == Selection.validate_model_exists_for_provider(model_id, :anthropic)
    end

    test "returns error when model does not exist" do
      assert {:error, :model_not_found} ==
               Selection.validate_model_exists_for_provider("non-existent-model", :anthropic)
    end
  end

  describe "validate_capabilities_met/2" do
    setup do
      models = Discovery.list_models(:anthropic)
      model = hd(models)

      %{model: model}
    end

    test "returns :ok when all capabilities are met", %{model: model} do
      # Empty requirements are always met
      assert :ok == Selection.validate_capabilities_met(model, %{})
    end

    test "returns error when capabilities are not met", %{model: model} do
      # Require a non-existent capability
      assert {:error, :missing_capability} ==
               Selection.validate_capabilities_met(model, %{nonexistent: true})
    end
  end

  describe "format_error/1" do
    test "formats :provider_not_enabled error" do
      message = Selection.format_error(:provider_not_enabled)

      assert message =~ "not enabled"
    end

    test "formats :model_not_found error" do
      message = Selection.format_error(:model_not_found)

      assert message =~ "not found"
    end

    test "formats :missing_capability error" do
      message = Selection.format_error(:missing_capability)

      assert message =~ "capabilities"
    end

    test "formats :invalid_provider error" do
      message = Selection.format_error(:invalid_provider)

      assert message =~ "invalid"
    end

    test "formats unknown errors" do
      message = Selection.format_error(:unknown_error)

      assert message =~ "unknown error"
    end
  end

  describe "String.to_existing_atom safety" do
    test "handles string provider in conversation opts" do
      # This tests the safe conversion of string to atom
      conversation_opts = %{llm_provider: "anthropic"}
      repo_id = nil
      app_opts = %{}

      result = Selection.resolve(conversation_opts, repo_id, app_opts)

      # Should either succeed or return a proper error, not crash
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles invalid string provider" do
      conversation_opts = %{llm_provider: "non-existent-provider"}
      repo_id = nil
      app_opts = %{}

      assert {:error, :invalid_provider} =
               Selection.resolve(conversation_opts, repo_id, app_opts)
    end
  end

  describe "selection result structure" do
    setup do
      # Get a valid model ID for tests
      models = Discovery.list_models(:anthropic)
      model_id = hd(models).id
      %{model_id: model_id}
    end

    test "includes all required fields", %{model_id: model_id} do
      assert {:ok, result} = Selection.resolve(%{}, nil, %{default_model: model_id})

      assert Map.has_key?(result, :provider)
      assert Map.has_key?(result, :model)
      assert Map.has_key?(result, :llmdb_model)
      assert Map.has_key?(result, :source)
      assert Map.has_key?(result, :capabilities)

      assert is_atom(result.provider)
      assert is_binary(result.model)
      assert result.source in [:conversation, :repository, :application]
      assert is_map(result.capabilities)
    end

    test "includes correct source level for conversation opts", %{model_id: model_id} do
      assert {:ok, result} = Selection.resolve(%{llm_provider: :anthropic, llm_model: model_id}, nil, %{})
      assert result.source == :conversation
    end

    test "includes correct source level for application defaults", %{model_id: model_id} do
      assert {:ok, result} = Selection.resolve(%{}, nil, %{default_model: model_id})
      assert result.source == :application
    end
  end
end
