defmodule JidoCode.Control.LLMPreferences.Validation do
  @moduledoc """
  Validations for LLMPreferences resource.
  """

  require Ash.Query

  alias JidoCode.LLM.Discovery

  @doc """
  Validates that enabled_providers is a subset of available providers.
  """
  def providers_subset_of_available(changeset, _context) do
    case Ash.Changeset.fetch_change(changeset, :enabled_providers) do
      {:ok, enabled_providers} ->
        available_providers = get_available_providers()

        invalid_providers =
          Enum.filter(enabled_providers, fn provider ->
            provider not in available_providers
          end)

        if invalid_providers == [] do
          changeset
        else
          invalid_providers_str =
            invalid_providers
            |> Enum.map(&Atom.to_string/1)
            |> Enum.join(", ")

          Ash.Changeset.add_error(
            changeset,
            :enabled_providers,
            "contains providers not available in ReqLLM: #{invalid_providers_str}"
          )
        end

      :error ->
        changeset
    end
  end

  @doc """
  Validates that default_provider is in the enabled_providers list.
  """
  def default_provider_in_enabled(changeset, _context) do
    default_provider = Ash.Changeset.get_attribute(changeset, :default_provider)
    enabled_providers = Ash.Changeset.get_attribute(changeset, :enabled_providers)

    cond do
      is_nil(default_provider) ->
        changeset

      is_nil(enabled_providers) ->
        # Can't validate without enabled_providers
        changeset

      default_provider in enabled_providers ->
        changeset

      true ->
        providers_str =
          enabled_providers
          |> Enum.map(&Atom.to_string/1)
          |> Enum.join(", ")

        Ash.Changeset.add_error(
          changeset,
          :default_provider,
          "must be one of the enabled providers: #{providers_str}"
        )
    end
  end

  @doc """
  Validates that the default_model exists for the specified provider.
  """
  def default_model_exists_for_provider(changeset, _context) do
    provider = Ash.Changeset.get_attribute(changeset, :default_provider)
    model = Ash.Changeset.get_attribute(changeset, :default_model)

    cond do
      is_nil(provider) or is_nil(model) ->
        changeset

      true ->
        case Discovery.model_info(provider, model) do
          {:ok, _model_info} ->
            changeset

          :error ->
            Ash.Changeset.add_error(
              changeset,
              :default_model,
              "does not exist for provider #{Atom.to_string(provider)}"
            )
        end
    end
  end

  # Get the list of available providers from application config or Discovery
  defp get_available_providers do
    case Application.get_env(:jido_code, :llm)[:available_providers] do
      :all ->
        # All providers from ReqLLM are available
        Discovery.list_providers()
        |> Enum.map(& &1.id)

      providers when is_list(providers) ->
        providers

      _ ->
        # Default to anthropic and openai for backward compatibility
        [:anthropic, :openai]
    end
  end
end
