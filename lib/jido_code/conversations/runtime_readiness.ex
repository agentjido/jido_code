defmodule JidoCode.Conversations.RuntimeReadiness do
  # covers: architecture.conversation_orchestration.llm_readiness_and_failure_states_are_explicit
  @moduledoc """
  Resolves bounded runtime prerequisites for real conversation execution.

  Repo-detail conversations should fail explicitly when the repository workspace
  or provider prerequisites are unavailable instead of fabricating progress.
  """

  alias JidoCode.LLMSelection
  alias JidoCode.Workbench.{ProjectDetail, ProjectWorkspaceBindingNotice}

  @type readiness :: %{
          project_detail: map(),
          workspace_path: String.t(),
          llm_selection: map()
        }

  @spec resolve(String.t(), keyword()) :: {:ok, readiness()} | {:error, map()}
  def resolve(managed_repo_id, opts \\ [])

  def resolve(managed_repo_id, opts) when is_binary(managed_repo_id) and is_list(opts) do
    with {:ok, project_detail} <- ProjectDetail.load(managed_repo_id),
         :ok <- execution_ready(project_detail),
         {:ok, workspace_path} <- workspace_path(project_detail),
         {:ok, llm_selection} <- llm_selection(project_detail, opts) do
      {:ok, %{project_detail: project_detail, workspace_path: workspace_path, llm_selection: llm_selection}}
    end
  end

  def resolve(_managed_repo_id, _opts), do: {:error, invalid_repo_scope_error()}

  defp execution_ready(project_detail) do
    if ProjectDetail.ready_for_execution?(project_detail) do
      :ok
    else
      execution_readiness =
        project_detail
        |> Map.get(:execution_readiness, %{})
        |> normalize_map()

      {:error, execution_readiness_notice(execution_readiness, project_detail)}
    end
  end

  defp workspace_path(project_detail) do
    workspace_path =
      project_detail
      |> ProjectDetail.workspace_path()
      |> normalize_optional_string()

    case workspace_path do
      nil ->
        notice =
          ProjectWorkspaceBindingNotice.blocked_notice(
            ProjectDetail.workspace_binding(project_detail),
            error_type: "conversation_runtime_workspace_binding_unavailable",
            surface: "conversation runtime",
            retry_action: "retry the conversation turn"
          )

        {:error, stringify_notice(notice)}

      path ->
        {:ok, Path.expand(path)}
    end
  end

  defp execution_readiness_notice(execution_readiness, project_detail) do
    error_type =
      Map.get(execution_readiness, "error_type", "conversation_runtime_not_ready")

    case error_type do
      "managed_repo_workspace_binding_missing" ->
        ProjectWorkspaceBindingNotice.blocked_notice(
          ProjectDetail.workspace_binding(project_detail),
          error_type: "conversation_runtime_workspace_binding_missing",
          surface: "conversation runtime",
          retry_action: "retry the conversation turn"
        )
        |> stringify_notice()

      "managed_repo_workspace_binding_unavailable" ->
        ProjectWorkspaceBindingNotice.blocked_notice(
          ProjectDetail.workspace_binding(project_detail),
          error_type: "conversation_runtime_workspace_binding_unavailable",
          surface: "conversation runtime",
          retry_action: "retry the conversation turn"
        )
        |> stringify_notice()

      _other ->
        %{
          "error_type" => error_type,
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
        }
    end
  end

  defp llm_selection(project_detail, opts) do
    opts =
      Keyword.put_new(
        opts,
        :conversation_metadata,
        Keyword.get(opts, :conversation_metadata, %{})
      )

    LLMSelection.resolve_from_project_detail(project_detail, opts)
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

  defp stringify_notice(notice) when is_map(notice) do
    %{
      "error_type" => Map.get(notice, :error_type) || Map.get(notice, "error_type"),
      "detail" => Map.get(notice, :detail) || Map.get(notice, "detail"),
      "remediation" => Map.get(notice, :remediation) || Map.get(notice, "remediation")
    }
  end
end
