defmodule JidoCode.Setup.OnboardingReset do
  # covers: setup.onboarding.reset_mix_task
  @moduledoc """
  Resets onboarding state either to first-run bootstrap or back to the signed-in setup surface.
  """

  require Ash.Query

  alias JidoCode.Accounts
  alias JidoCode.Accounts.User
  alias JidoCode.GitHub.ServiceCredentials
  alias JidoCode.Repo
  alias JidoCode.Security
  alias JidoCode.Security.SecretRef
  alias JidoCode.Setup.{BootstrapStatus, SystemConfig}

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
    with {:ok, users} <- Ash.read(User, domain: Accounts, authorize?: false),
         {:ok, _result} <-
           Ecto.Adapters.SQL.query(Repo, "TRUNCATE TABLE users RESTART IDENTITY CASCADE", []) do
      {:ok, length(users)}
    end
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
    with {:ok, cleared_managed_repo_count} <- managed_repo_count(),
         {:ok, _result} <-
           Ecto.Adapters.SQL.query(
             Repo,
             "TRUNCATE TABLE source_repos, agent_os_kernel_snapshots RESTART IDENTITY CASCADE",
             []
           ) do
      {:ok, cleared_managed_repo_count}
    end
  end

  defp clear_onboarding_github_pat_secret do
    with {:ok, secret_ref} <- onboarding_github_pat_secret_ref() do
      case secret_ref do
        %SecretRef{} = secret_ref ->
          case Ash.destroy(secret_ref, domain: Security, authorize?: false) do
            :ok -> {:ok, true}
            {:error, reason} -> {:error, reason}
          end

        nil ->
          {:ok, false}
      end
    end
  end

  defp onboarding_github_pat_secret_ref do
    pat_secret_ref_name = ServiceCredentials.service_secret_ref_name(:pat)

    query =
      SecretRef
      |> Ash.Query.filter(scope == :integration and name == ^pat_secret_ref_name)
      |> Ash.Query.limit(1)

    case Ash.read(query, domain: Security, authorize?: false) do
      {:ok, [%SecretRef{source: :onboarding} = secret_ref]} -> {:ok, secret_ref}
      {:ok, [_other_secret_ref]} -> {:ok, nil}
      {:ok, []} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp managed_repo_count do
    case Ecto.Adapters.SQL.query(Repo, "SELECT COUNT(*) FROM managed_repos", []) do
      {:ok, %{rows: [[count]]}} when is_integer(count) and count >= 0 -> {:ok, count}
      {:ok, _result} -> {:error, :invalid_managed_repo_count_result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp owner_email(nil), do: nil
  defp owner_email(%User{} = owner), do: to_string(owner.email)
end
