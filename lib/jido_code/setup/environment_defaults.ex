defmodule JidoCode.Setup.EnvironmentDefaults do
  # covers: setup.runtime_environment_defaults.cloud_selection_maps_to_sprite_default
  # covers: setup.runtime_environment_defaults.local_selection_requires_valid_workspace_root
  # covers: setup.onboarding.runtime_environment_selection_persisted_metadata
  @moduledoc """
  Validates setup step 5 environment defaults before onboarding can advance.
  """

  @local_workspace_remediation """
  Provide an absolute workspace root path that exists on disk so local execution can prepare workspaces safely.
  """
  @cloud_default_remediation "Cloud mode always uses Sprite execution defaults."

  @type mode :: :cloud | :local
  @type status :: :ready | :blocked
  @type check_status :: :ready | :failed

  @type check_result :: %{
          id: String.t(),
          name: String.t(),
          status: check_status(),
          detail: String.t(),
          remediation: String.t(),
          checked_at: DateTime.t()
        }

  @type report :: %{
          checked_at: DateTime.t(),
          status: status(),
          mode: mode(),
          default_environment: :sprite | :local,
          workspace_root: String.t() | nil,
          checks: [check_result()]
        }

  @spec run(map() | nil) :: report()
  def run(selection \\ %{})

  def run(selection) when is_map(selection) do
    checked_at = DateTime.utc_now() |> DateTime.truncate(:second)
    mode = selection |> map_get(:mode, "mode", :cloud) |> normalize_mode(:cloud)

    workspace_root =
      selection |> map_get(:workspace_root, "workspace_root") |> normalize_workspace_root()

    checks = build_checks(mode, workspace_root, checked_at)

    %{
      checked_at: checked_at,
      status: overall_status(checks),
      mode: mode,
      default_environment: default_environment(mode),
      workspace_root: normalize_workspace_root_for_state(mode, workspace_root),
      checks: checks
    }
  end

  def run(_selection), do: run(%{})

  @spec blocked?(report()) :: boolean()
  def blocked?(%{status: :ready}), do: false
  def blocked?(%{status: _status}), do: true
  def blocked?(_), do: true

  @spec blocked_checks(report()) :: [check_result()]
  def blocked_checks(%{checks: checks}) when is_list(checks) do
    Enum.filter(checks, fn check -> Map.get(check, :status) != :ready end)
  end

  def blocked_checks(_), do: []

  @spec serialize_for_state(report()) :: map()
  def serialize_for_state(%{
        checked_at: checked_at,
        status: status,
        mode: mode,
        default_environment: default_environment,
        workspace_root: workspace_root,
        checks: checks
      })
      when is_list(checks) do
    %{
      "checked_at" => DateTime.to_iso8601(checked_at),
      "status" => Atom.to_string(status),
      "mode" => Atom.to_string(mode),
      "default_environment" => Atom.to_string(default_environment),
      "workspace_root" => workspace_root,
      "checks" =>
        Enum.map(checks, fn check ->
          %{
            "id" => Map.get(check, :id, "unknown_check"),
            "name" => Map.get(check, :name, "Unknown check"),
            "status" => Atom.to_string(Map.get(check, :status, :failed)),
            "detail" => Map.get(check, :detail, ""),
            "remediation" => Map.get(check, :remediation, @local_workspace_remediation),
            "checked_at" =>
              check
              |> Map.get(:checked_at, checked_at)
              |> DateTime.to_iso8601()
          }
        end)
    }
  end

  def serialize_for_state(_), do: %{}

  @spec system_config_updates(report()) :: %{
          default_environment: :sprite | :local,
          workspace_root: String.t() | nil
        }
  def system_config_updates(%{mode: :local, workspace_root: workspace_root})
      when is_binary(workspace_root) and workspace_root != "" do
    %{default_environment: :local, workspace_root: Path.expand(workspace_root)}
  end

  def system_config_updates(%{mode: :cloud}) do
    %{default_environment: :sprite, workspace_root: nil}
  end

  def system_config_updates(_report), do: %{default_environment: :sprite, workspace_root: nil}

  defp build_checks(:cloud, _workspace_root, checked_at) do
    [
      %{
        id: "cloud_sprite_default",
        name: "Cloud default environment",
        status: :ready,
        detail: "Cloud mode enforces Sprite as the default execution environment.",
        remediation: @cloud_default_remediation,
        checked_at: checked_at
      }
    ]
  end

  defp build_checks(:local, workspace_root, checked_at) do
    [
      local_workspace_root_check(workspace_root, checked_at)
    ]
  end

  defp local_workspace_root_check(nil, checked_at) do
    %{
      id: "local_workspace_root",
      name: "Local workspace root",
      status: :failed,
      detail: "Local mode requires a workspace root.",
      remediation: @local_workspace_remediation,
      checked_at: checked_at
    }
  end

  defp local_workspace_root_check(workspace_root, checked_at) do
    cond do
      Path.type(workspace_root) != :absolute ->
        %{
          id: "local_workspace_root",
          name: "Local workspace root",
          status: :failed,
          detail: "Workspace root must be an absolute path.",
          remediation: @local_workspace_remediation,
          checked_at: checked_at
        }

      not File.dir?(workspace_root) ->
        %{
          id: "local_workspace_root",
          name: "Local workspace root",
          status: :failed,
          detail: "Workspace root directory does not exist.",
          remediation: @local_workspace_remediation,
          checked_at: checked_at
        }

      true ->
        %{
          id: "local_workspace_root",
          name: "Local workspace root",
          status: :ready,
          detail: "Workspace root is valid for local execution.",
          remediation: "Local workspace root is ready.",
          checked_at: checked_at
        }
    end
  end

  defp normalize_mode(:cloud, _default), do: :cloud
  defp normalize_mode(:local, _default), do: :local
  defp normalize_mode("cloud", _default), do: :cloud
  defp normalize_mode("local", _default), do: :local
  defp normalize_mode(_mode, default), do: default

  defp normalize_workspace_root(workspace_root) when is_binary(workspace_root) do
    workspace_root
    |> String.trim()
    |> case do
      "" -> nil
      normalized_workspace_root -> normalized_workspace_root
    end
  end

  defp normalize_workspace_root(_workspace_root), do: nil

  defp normalize_workspace_root_for_state(:cloud, _workspace_root), do: nil
  defp normalize_workspace_root_for_state(:local, nil), do: nil
  defp normalize_workspace_root_for_state(:local, workspace_root), do: workspace_root

  defp default_environment(:cloud), do: :sprite
  defp default_environment(:local), do: :local

  defp overall_status(checks) do
    if Enum.all?(checks, fn check -> check.status == :ready end), do: :ready, else: :blocked
  end

  defp map_get(map, atom_key, string_key, default \\ nil) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end
end
