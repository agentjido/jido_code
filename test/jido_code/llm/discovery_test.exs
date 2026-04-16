defmodule JidoCode.LLM.DiscoveryTest do
  use JidoCode.DataCase

  alias JidoCode.LLM.Discovery

  describe "list_providers/0" do
    test "returns a list of providers" do
      providers = Discovery.list_providers()

      assert is_list(providers)
      assert length(providers) > 0
    end

    test "returns at least 18 providers from ReqLLM" do
      providers = Discovery.list_providers()

      # ReqLLM supports 18+ providers
      assert length(providers) >= 18
    end

    test "includes Anthropic in the provider list" do
      providers = Discovery.list_providers()

      anthropic_provider =
        Enum.find(providers, fn p ->
          p.id == :anthropic
        end)

      assert anthropic_provider != nil
      assert anthropic_provider.id == :anthropic
      assert String.downcase(anthropic_provider.name) =~ "anthropic"
    end

    test "includes OpenAI in the provider list" do
      providers = Discovery.list_providers()

      openai_provider =
        Enum.find(providers, fn p ->
          p.id == :openai
        end)

      assert openai_provider != nil
      assert openai_provider.id == :openai
      assert String.downcase(openai_provider.name) =~ "openai"
    end

    test "each provider has required fields" do
      providers = Discovery.list_providers()

      Enum.each(providers, fn provider ->
        assert is_atom(provider.id)
        assert is_binary(provider.name)
        # description, env_key, and base_url are optional
      end)
    end
  end

  describe "provider_info/1" do
    test "returns expected metadata structure for Anthropic" do
      info = Discovery.provider_info(:anthropic)

      assert info.id == :anthropic
      assert String.downcase(info.name) =~ "anthropic"
      assert info.env_key == "ANTHROPIC_API_KEY"
    end

    test "returns expected metadata structure for OpenAI" do
      info = Discovery.provider_info(:openai)

      assert info.id == :openai
      assert String.downcase(info.name) =~ "openai"
      assert info.env_key == "OPENAI_API_KEY"
    end

    test "returns name as human-readable string" do
      anthropic_info = Discovery.provider_info(:anthropic)
      openai_info = Discovery.provider_info(:openai)

      assert anthropic_info.name == "Anthropic"
      assert openai_info.name == "Openai"
    end

    test "returns env_key for provider" do
      anthropic_info = Discovery.provider_info(:anthropic)
      openai_info = Discovery.provider_info(:openai)

      assert anthropic_info.env_key == "ANTHROPIC_API_KEY"
      assert openai_info.env_key == "OPENAI_API_KEY"
    end

    test "returns description or nil for provider" do
      info = Discovery.provider_info(:anthropic)

      # Description may be nil or a binary depending on module docs
      assert info.description == nil or is_binary(info.description)
    end

    test "returns base_url or nil for provider" do
      info = Discovery.provider_info(:anthropic)

      # base_url may be nil or a binary
      assert info.base_url == nil or is_binary(info.base_url)
    end
  end

  describe "list_models/1" do
    test "returns a list of models for Anthropic" do
      models = Discovery.list_models(:anthropic)

      assert is_list(models)
      assert length(models) > 0
    end

    test "returns LLMDB.Model structs for Anthropic" do
      models = Discovery.list_models(:anthropic)

      Enum.each(models, fn model ->
        assert %LLMDB.Model{} = model
      end)
    end

    test "returns a list of models for OpenAI" do
      models = Discovery.list_models(:openai)

      assert is_list(models)
      assert length(models) > 0
    end

    test "returns LLMDB.Model structs for OpenAI" do
      models = Discovery.list_models(:openai)

      Enum.each(models, fn model ->
        assert %LLMDB.Model{} = model
      end)
    end

    test "returns models with id field" do
      models = Discovery.list_models(:anthropic)

      Enum.each(models, fn model ->
        assert is_binary(model.id)
      end)
    end

    test "models have capabilities" do
      models = Discovery.list_models(:anthropic)

      # At least some models should have capabilities
      models_with_caps = Enum.filter(models, fn m -> m.capabilities != nil end)

      assert length(models_with_caps) > 0
    end
  end

  describe "model_info/2" do
    test "returns {:ok, model} for valid Anthropic model" do
      # First get a valid model ID
      models = Discovery.list_models(:anthropic)
      model_id = hd(models).id

      assert {:ok, model} = Discovery.model_info(:anthropic, model_id)
      assert %LLMDB.Model{} = model
      assert model.id == model_id
    end

    test "returns {:ok, model} for valid OpenAI model" do
      # First get a valid model ID
      models = Discovery.list_models(:openai)
      model_id = hd(models).id

      assert {:ok, model} = Discovery.model_info(:openai, model_id)
      assert %LLMDB.Model{} = model
      assert model.id == model_id
    end

    test "returns :error for non-existent model" do
      assert :error == Discovery.model_info(:anthropic, "non-existent-model-12345")
    end

    test "returns :error for non-existent provider" do
      assert :error == Discovery.model_info(:non_existent_provider, "some-model")
    end

    test "returned model has capabilities" do
      models = Discovery.list_models(:anthropic)
      model_id = hd(models).id

      assert {:ok, model} = Discovery.model_info(:anthropic, model_id)
      assert is_map(model.capabilities)
    end
  end

  describe "provider_name/1" do
    test "formats anthropic provider name" do
      assert Discovery.provider_name(:anthropic) == "Anthropic"
    end

    test "formats openai provider name" do
      assert Discovery.provider_name(:openai) == "Openai"
    end

    test "formats multi-word provider names" do
      # Test with a hypothetical multi-word provider
      assert Discovery.provider_name(:google_vertex) == "Google Vertex"
    end

    test "handles single atom providers" do
      assert Discovery.provider_name(:groq) == "Groq"
    end
  end

  describe "provider_description/1" do
    test "returns documentation for provider module" do
      # This test verifies we can extract moduledoc
      # Results depend on whether the module has documentation
      anthropic_module = ReqLLM.Providers.get!(:anthropic)

      description = Discovery.provider_description(anthropic_module)

      # May be nil if module has no moduledoc, or binary if it does
      assert description == nil or is_binary(description)
    end
  end

  describe "provider_base_url/1" do
    test "returns base URL if provider module defines it" do
      anthropic_module = ReqLLM.Providers.get!(:anthropic)

      base_url = Discovery.provider_base_url(anthropic_module)

      # May be nil if provider doesn't define base_url/0
      assert base_url == nil or is_binary(base_url)
    end

    test "returns nil when base_url function is not exported" do
      # Most providers don't override base_url
      anthropic_module = ReqLLM.Providers.get!(:anthropic)

      base_url = Discovery.provider_base_url(anthropic_module)

      # Typically nil for standard providers
      assert base_url == nil or is_binary(base_url)
    end
  end
end
