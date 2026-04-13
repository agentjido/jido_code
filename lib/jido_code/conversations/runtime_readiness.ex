defmodule JidoCode.Conversations.RuntimeReadiness do
  # covers: architecture.conversation_orchestration.llm_readiness_and_failure_states_are_explicit
  @moduledoc """
  Resolves bounded runtime prerequisites for real conversation execution.

  Repo-detail conversations should fail explicitly when the repository workspace
  or provider prerequisites are unavailable instead of fabricating progress.
  """

  alias JidoCode.Setup.ProviderCredentialChecks
  alias JidoCode.Workbench.ProjectDetail

  @type readiness :: %{
          project_detail: map(),
          workspace_path: String.t()
        }

  @spec resolve(String.t()) :: {:ok, readiness()} | {:error, map()}
  def resolve(managed_repo_id) when is_binary(managed_repo_id) do
    with {:ok, project_detail} <- ProjectDetail.load(managed_repo_id),
         :ok <- execution_ready(project_detail),
         {:ok, workspace_path} <- workspace_path(project_detail),
         :ok <- provider_ready() do
      {:ok, %{project_detail: project_detail, workspace_path: workspace_path}}
    end
  end

  def resolve(_managed_repo_id), do: {:error, invalid_repo_scope_error()}

  defp execution_ready(project_detail) do
    if ProjectDetail.ready_for_execution?(project_detail) do
      :ok
    else
      execution_readiness =
        project_detail
        |> Map.get(:execution_readiness, %{})
        |> normalize_map()

      {:error,
       %{
         "error_type" =>
           Map.get(execution_readiness, "error_type", "conversation_runtime_not_ready"),
         "detail" =>
           Map.get(
             execution_readiness,
             "detail",
             "Repository execution prerequisites are not ready for real conversation runtime."
           ),
         "remediation" =>
           Map.get(
             execution_readiness,
             "remediation",
             "Repair repository workspace readiness and retry the conversation turn."
           )
       }}
    end
  end

  defp workspace_path(project_detail) do
    workspace_path =
      project_detail
      |> Map.get(:settings, %{})
      |> normalize_map()
      |> Map.get("workspace", %{})
      |> normalize_map()
      |> Map.get("workspace_path")
      |> normalize_optional_string()

    case workspace_path do
      nil ->
        {:error,
         %{
           "error_type" => "conversation_runtime_workspace_unavailable",
           "detail" => "Repository workspace path is missing for real conversation runtime.",
           "remediation" => "Repair repository workspace configuration and retry the conversation turn."
         }}

      path ->
        {:ok, Path.expand(path)}
    end
  end

  defp provider_ready do
    case Application.get_env(:jido_code_server, :llm_adapter, :jido_ai) do
      :deterministic ->
        :ok

      _adapter ->
        report = ProviderCredentialChecks.run()

        if ProviderCredentialChecks.blocked?(report) do
          blocked_credential =
            report
            |> ProviderCredentialChecks.blocked_credentials()
            |> List.first()

          {:error,
           %{
             "error_type" =>
               blocked_credential &&
                 blocked_credential.error_type || "conversation_runtime_provider_unavailable",
             "detail" =>
               blocked_credential &&
                 blocked_credential.detail ||
                 "LLM provider credentials are not ready for real conversation runtime.",
             "remediation" =>
               blocked_credential &&
                 blocked_credential.remediation ||
                 "Verify provider credentials and retry the conversation turn."
           }}
        else
          :ok
        end
    end
  end

  defp invalid_repo_scope_error do
    %{
      "error_type" => "conversation_runtime_repo_scope_invalid",
      "detail" => "Managed repository scope is missing for real conversation runtime.",
      "remediation" => "Open the conversation from a managed repository route and retry."
    }
  end

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      Map.put(acc, normalized_key, normalize_nested_value(nested_value))
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_optional_string()
  defp normalize_optional_string(_value), do: nil
end
