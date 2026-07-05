defmodule JidoCode.Setup.OnboardingReset do
  # covers: setup.onboarding.reset_mix_task
  @moduledoc """
  Resets onboarding state either to first-run bootstrap or back to the signed-in setup surface.
  """

  alias JidoCode.Accounts.User
  alias JidoCode.ControlPlane.Codecs.Registry
  alias JidoCode.ControlPlane.ProductStore
  alias JidoCode.ControlPlane.Store.Errors.NotFoundError
  alias JidoCode.GitHub.ServiceCredentials
  alias JidoCode.Setup.{BootstrapStatus, OwnerStore, SystemConfig}

  @type mode :: :full | :keep_owner

  @type result :: %{
          mode: mode(),
          config: SystemConfig.t(),
          owner_email: String.t() | nil,
          cleared_owner_count: non_neg_integer(),
          cleared_managed_repo_count: non_neg_integer(),
          cleared_onboarding_pat?: boolean()
        }

  @full_reset_config %SystemConfig{
    onboarding_completed: false,
    onboarding_step: 1,
    onboarding_state: %{},
    default_environment: :sprite,
    workspace_root: nil
  }

  @prerequisite_validated_note "System prerequisites verified (welcome flow)."
  @owner_confirmed_note "Owner account confirmed."

  @doc """
  Resets onboarding according to the selected mode.
  """
  @spec reset(mode()) :: {:ok, result()} | {:error, term()}
  def reset(mode) when mode in [:full, :keep_owner] do
    with {:ok, owner} <- owner_for_mode(mode),
         {:ok, cleared_onboarding_pat?} <- clear_onboarding_github_pat_secret(),
         {:ok, cleared_owner_count} <- maybe_clear_users(mode),
         {:ok, cleared_managed_repo_count} <- clear_managed_repo_inventory(),
         {:ok, config} <- persist_reset_config(mode, owner) do
      {:ok,
       %{
         mode: mode,
         config: config,
         owner_email: owner_email(owner),
         cleared_owner_count: cleared_owner_count,
         cleared_managed_repo_count: cleared_managed_repo_count,
         cleared_onboarding_pat?: cleared_onboarding_pat?
       }}
    end
  end

  def reset(_mode), do: {:error, {:invalid_mode, "Reset mode must be :full or :keep_owner."}}

  defp owner_for_mode(:full), do: {:ok, nil}

  defp owner_for_mode(:keep_owner) do
    case BootstrapStatus.current() do
      %{primary_user: %User{} = owner} ->
        {:ok, owner}

      %{state: :bootstrap_required} ->
        {:error, {:keep_owner_unavailable, "No bootstrap owner exists to preserve for setup reset."}}

      %{diagnostic: diagnostic} when is_binary(diagnostic) and diagnostic != "" ->
        {:error, {:keep_owner_unavailable, diagnostic}}

      _other ->
        {:error, {:keep_owner_unavailable, "Unable to determine a single bootstrap owner to preserve for setup reset."}}
    end
  end

  defp maybe_clear_users(:keep_owner), do: {:ok, 0}

  defp maybe_clear_users(:full) do
    OwnerStore.delete_all_users()
  end

  defp persist_reset_config(:full, _owner) do
    SystemConfig.save(@full_reset_config)
  end

  defp persist_reset_config(:keep_owner, %User{} = owner) do
    SystemConfig.save(%SystemConfig{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{
        "1" => %{"validated_note" => @prerequisite_validated_note},
        "2" => %{
          "validated_note" => @owner_confirmed_note,
          "owner_email" => owner_email(owner),
          "owner_mode" => "confirmed",
          "registration_actions_disabled" => true
        }
      },
      default_environment: :sprite,
      workspace_root: nil
    })
  end

  defp clear_managed_repo_inventory do
    clear_record_type(:managed_repo)
  end

  defp clear_onboarding_github_pat_secret do
    with {:ok, secret_ref} <- onboarding_github_pat_secret_ref() do
      case secret_ref do
        %{subject_iri: subject_iri} when is_binary(subject_iri) ->
          case ProductStore.dispatch(:delete, :secret_ref, subject_iri: subject_iri) do
            {:ok, _outcome} -> {:ok, true}
            {:error, %NotFoundError{}} -> {:ok, false}
            {:error, reason} -> {:error, reason}
          end

        nil ->
          {:ok, false}
      end
    end
  end

  defp onboarding_github_pat_secret_ref do
    pat_secret_ref_name = ServiceCredentials.service_secret_ref_name(:pat)

    case ProductStore.dispatch(:list, :secret_ref, query: %{limit: 500, offset: 0}) do
      {:ok, %{projections: projections}} ->
        projections
        |> Enum.map(&decode_projection(:secret_ref, &1))
        |> Enum.find(fn
          {:ok, record} ->
            record_scope(record) == "integration" and record_name(record) == pat_secret_ref_name and
              onboarding_secret_ref?(record)

          _other ->
            false
        end)
        |> case do
          {:ok, record} -> {:ok, record}
          nil -> {:ok, nil}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp clear_record_type(record_type) do
    case ProductStore.dispatch(:list, record_type, query: %{limit: 500, offset: 0}) do
      {:ok, %{projections: projections}} ->
        projections
        |> Enum.reduce_while({:ok, 0}, fn projection, {:ok, count} ->
          subject_iri = Map.get(projection, :subject_iri) || Map.get(projection, "subject_iri")

          case ProductStore.dispatch(:delete, record_type, subject_iri: subject_iri) do
            {:ok, _outcome} -> {:cont, {:ok, count + 1}}
            {:error, %NotFoundError{}} -> {:cont, {:ok, count}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp owner_email(nil), do: nil
  defp owner_email(%User{} = owner), do: to_string(owner.email)

  defp decode_projection(record_type, projection) do
    with {:ok, record} <- Registry.decode(record_type, projection) do
      {:ok, record}
    end
  end

  defp record_scope(record), do: record |> map_get(:scope) |> to_string()
  defp record_name(record), do: record |> map_get(:name) |> to_string()

  defp onboarding_secret_ref?(record) do
    metadata =
      record
      |> map_get(:metadata, %{})
      |> decode_json_map()

    Map.get(metadata, "source") in [nil, "onboarding"]
  end

  defp decode_json_map(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _other -> %{}
    end
  end

  defp decode_json_map(value) when is_map(value), do: value
  defp decode_json_map(_value), do: %{}

  defp map_get(map, key, default \\ nil)
  defp map_get(map, key, default) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  defp map_get(_map, _key, default), do: default
end
