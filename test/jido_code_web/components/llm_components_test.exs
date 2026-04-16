defmodule JidoCodeWeb.LLMComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import Phoenix.Component

  alias JidoCodeWeb.LLMComponents

  # Helper module to use components in tests
  defmodule Harness do
    use Phoenix.Component

    import JidoCodeWeb.LLMComponents

    def test_provider_card(assigns) do
      ~H"""
      <.provider_card
        id={@id}
        provider={@provider}
        name={@name}
        env_key={@env_key}
        configured={@configured}
        description={Map.get(assigns, :description)}
      />
      """
    end

    def test_model_picker(assigns) do
      ~H"""
      <.model_picker
        id={@id}
        repo_id={Map.get(assigns, :repo_id)}
        selected={@selected}
        available_models={@available_models}
      />
      """
    end

    def test_model_badges(assigns) do
      ~H"""
      <.model_badges model={@model} />
      """
    end

    def test_llm_error(assigns) do
      ~H"""
      <.llm_error error={@error} />
      """
    end

    def test_credential_status(assigns) do
      ~H"""
      <.credential_status configured={@configured} />
      """
    end
  end

  describe "provider_card/1" do
    test "renders provider card with credential status" do
      html =
        render_component(&Harness.test_provider_card/1, %{
          id: "anthropic-card",
          provider: :anthropic,
          name: "Anthropic",
          env_key: "ANTHROPIC_API_KEY",
          configured: true
        })

      assert html =~ "Anthropic"
      assert html =~ "ANTHROPIC_API_KEY"
      assert html =~ "Configured"
    end

    test "shows 'Not configured' when credentials are not configured" do
      html =
        render_component(&Harness.test_provider_card/1, %{
          id: "openai-card",
          provider: :openai,
          name: "OpenAI",
          env_key: "OPENAI_API_KEY",
          configured: false
        })

      assert html =~ "OpenAI"
      assert html =~ "Not configured"
    end

    test "renders description when provided" do
      html =
        render_component(&Harness.test_provider_card/1, %{
          id: "provider-card",
          provider: :anthropic,
          name: "Anthropic",
          description: "Advanced AI assistant",
          env_key: "ANTHROPIC_API_KEY",
          configured: true
        })

      assert html =~ "Advanced AI assistant"
    end
  end

  describe "credential_status/1" do
    test "shows Configured badge when configured is true" do
      html =
        render_component(&Harness.test_credential_status/1, %{configured: true})

      assert html =~ "Configured"
    end

    test "shows Not configured badge when configured is false" do
      html =
        render_component(&Harness.test_credential_status/1, %{configured: false})

      assert html =~ "Not configured"
    end
  end

  describe "model_badges/1" do
    test "renders capability badges for model" do
      model = %{
        provider: :anthropic,
        model: "test-model",
        llmdb_model: %LLMDB.Model{
          id: "test-model",
          provider: :anthropic,
          capabilities: %{chat: true, tools: true, streaming: false}
        }
      }

      html =
        render_component(&Harness.test_model_badges/1, %{model: model})

      assert html =~ "Chat"
      assert html =~ "Tools"
      refute html =~ "Streaming"
    end

    test "renders no badges when capabilities are nil" do
      model = %{
        provider: :anthropic,
        model: "test-model",
        llmdb_model: nil
      }

      html =
        render_component(&Harness.test_model_badges/1, %{model: model})

      # Should not contain any capability labels
      refute html =~ "Chat"
    end
  end

  describe "llm_error/1" do
    test "renders error for :provider_not_enabled" do
      html =
        render_component(&Harness.test_llm_error/1, %{error: :provider_not_enabled})

      assert html =~ "not enabled"
    end

    test "renders error for :model_not_found" do
      html =
        render_component(&Harness.test_llm_error/1, %{error: :model_not_found})

      assert html =~ "not found"
    end

    test "renders error for {:missing_capability, capability}" do
      html =
        render_component(&Harness.test_llm_error/1, %{error: {:missing_capability, :tools}})

      assert html =~ "tools"
    end

    test "renders error for {:credential_missing, provider}" do
      html =
        render_component(&Harness.test_llm_error/1, %{error: {:credential_missing, :anthropic}})

      assert html =~ "credentials"
      assert html =~ "anthropic"
    end
  end

  describe "model_picker/1" do
    test "renders picker dropdown with available models" do
      models = [
        %{
          provider: :anthropic,
          model: "claude-3-5-sonnet-20250929",
          llmdb_model: %LLMDB.Model{id: "claude-3-5-sonnet-20250929", provider: :anthropic}
        },
        %{
          provider: :openai,
          model: "gpt-4",
          llmdb_model: %LLMDB.Model{id: "gpt-4", provider: :openai}
        }
      ]

      html =
        render_component(&Harness.test_model_picker/1, %{
          id: "model-picker",
          selected: nil,
          available_models: models
        })

      assert html =~ "Select Model"
      assert html =~ "claude-3-5-sonnet-20250929"
      assert html =~ "gpt-4"
    end

    test "shows selected model name when model is selected" do
      models = [
        %{
          provider: :anthropic,
          model: "claude-3-5-sonnet-20250929",
          llmdb_model: %LLMDB.Model{
            id: "claude-3-5-sonnet-20250929",
            provider: :anthropic,
            name: "Claude 3.5 Sonnet"
          }
        }
      ]

      html =
        render_component(&Harness.test_model_picker/1, %{
          id: "model-picker",
          selected: "claude-3-5-sonnet-20250929",
          available_models: models
        })

      assert html =~ "Claude 3.5 Sonnet"
    end
  end
end
