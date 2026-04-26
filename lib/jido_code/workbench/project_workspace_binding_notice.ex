defmodule JidoCode.Workbench.ProjectWorkspaceBindingNotice do
  @moduledoc false

  @type notice :: %{
          error_type: String.t(),
          detail: String.t(),
          remediation: String.t()
        }

  @type status_hint :: %{
          managed_repo_id: String.t() | nil,
          state: :blocked,
          label: String.t(),
          detail: String.t(),
          remediation: String.t(),
          recovery: %{available?: true, label: String.t()},
          error_type: String.t()
        }

  @spec blocked_notice(map() | nil, keyword()) :: notice()
  def blocked_notice(workspace_binding, opts \\ []) when is_list(opts) do
    error_type = normalize_error_type(Keyword.get(opts, :error_type))
    surface = normalize_surface(Keyword.get(opts, :surface))
    retry_action = normalize_retry_action(Keyword.get(opts, :retry_action))

    %{
      error_type: error_type,
      detail: blocked_detail(workspace_binding, surface),
      remediation: blocked_remediation(retry_action)
    }
  end

  @spec status_hint(String.t() | nil, map() | nil, keyword()) :: status_hint()
  def status_hint(managed_repo_id, workspace_binding, opts \\ []) when is_list(opts) do
    notice = blocked_notice(workspace_binding, opts)

    %{
      managed_repo_id: normalize_optional_string(managed_repo_id),
      state: :blocked,
      label: "Workspace binding needed",
      detail: notice.detail,
      remediation: "Open repo detail to repair workspace binding.",
      recovery: %{available?: true, label: "Repair workspace binding"},
      error_type: notice.error_type
    }
  end

  @spec missing_path_label() :: String.t()
  def missing_path_label, do: "No repo-scoped local workspace path saved"

  @spec workspace_binding_error?(map() | nil) :: boolean()
  def workspace_binding_error?(%{} = state) do
    state
    |> Map.get(:error_type, Map.get(state, "error_type"))
    |> normalize_optional_string()
    |> case do
      "managed_repo_workspace_binding_missing" -> true
      "managed_repo_workspace_binding_unavailable" -> true
      "conversation_runtime_workspace_binding_missing" -> true
      "conversation_runtime_workspace_binding_unavailable" -> true
      "semantic_workspace_binding_unavailable" -> true
      "memory_workspace_binding_unavailable" -> true
      _other -> false
    end
  end

  def workspace_binding_error?(_state), do: false

  defp blocked_detail(%{local?: true}, surface) do
    "This repository is configured for local runtime, but no repo-scoped local workspace path is saved for #{surface}."
  end

  defp blocked_detail(_workspace_binding, surface) do
    "This repository has no repo-scoped local workspace path bound for #{surface}."
  end

  defp blocked_remediation(retry_action) do
    "Open Overview, save a local workspace path for this repository, and #{retry_action}."
  end

  defp normalize_error_type(error_type) when is_binary(error_type) do
    case String.trim(error_type) do
      "" -> "managed_repo_workspace_binding_unavailable"
      normalized -> normalized
    end
  end

  defp normalize_error_type(_error_type), do: "managed_repo_workspace_binding_unavailable"

  defp normalize_surface(surface) when is_binary(surface) do
    case String.trim(surface) do
      "" -> "runtime execution"
      normalized -> normalized
    end
  end

  defp normalize_surface(_surface), do: "runtime execution"

  defp normalize_retry_action(retry_action) when is_binary(retry_action) do
    case String.trim(retry_action) do
      "" -> "retry this action"
      normalized -> normalized
    end
  end

  defp normalize_retry_action(_retry_action), do: "retry this action"

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil
end
