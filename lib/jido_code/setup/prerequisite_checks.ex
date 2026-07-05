defmodule JidoCode.Setup.PrerequisiteChecks do
  @moduledoc """
  Validates setup prerequisites before step 1 can advance.
  """

  alias JidoCode.ControlPlane.StoreServer
  alias JidoCodeWeb.Endpoint

  @default_timeout_ms 3_000
  @default_runtime_remediation "Set the missing runtime value and restart JidoCode."
  @default_check_remediation "Resolve this prerequisite before continuing setup."

  @type status :: :pass | :fail | :timeout

  @type check_result :: %{
          id: String.t(),
          name: String.t(),
          status: status(),
          detail: String.t(),
          remediation: String.t(),
          checked_at: DateTime.t()
        }

  @type report :: %{
          checked_at: DateTime.t(),
          status: status(),
          checks: [check_result()]
        }

  @spec run() :: report()
  def run do
    timeout_ms = Application.get_env(:jido_code, :setup_prerequisite_timeout_ms, @default_timeout_ms)
    run(timeout_ms)
  end

  @spec run(term()) :: report()
  def run(timeout_ms) do
    timeout_ms = normalize_timeout(timeout_ms)

    checker =
      Application.get_env(
        :jido_code,
        :setup_prerequisite_checker,
        &__MODULE__.default_checker/1
      )

    checker
    |> safe_invoke_checker(timeout_ms)
    |> normalize_report(timeout_ms)
  end

  @spec blocked?(report()) :: boolean()
  def blocked?(%{status: :pass}), do: false
  def blocked?(%{status: _status}), do: true
  def blocked?(_), do: true

  @spec blocked_checks(report()) :: [check_result()]
  def blocked_checks(%{checks: checks}) when is_list(checks) do
    Enum.filter(checks, fn check -> Map.get(check, :status) != :pass end)
  end

  def blocked_checks(_), do: []

  @spec serialize_for_state(report()) :: map()
  def serialize_for_state(%{checked_at: checked_at, status: status, checks: checks}) when is_list(checks) do
    %{
      "checked_at" => DateTime.to_iso8601(checked_at),
      "status" => Atom.to_string(status),
      "checks" =>
        Enum.map(checks, fn check ->
          %{
            "id" => Map.get(check, :id, "unknown_check"),
            "name" => Map.get(check, :name, "Unknown check"),
            "status" => Atom.to_string(Map.get(check, :status, :fail)),
            "detail" => Map.get(check, :detail, ""),
            "remediation" => Map.get(check, :remediation, @default_check_remediation),
            "checked_at" =>
              check
              |> Map.get(:checked_at, checked_at)
              |> DateTime.to_iso8601()
          }
        end)
    }
  end

  def serialize_for_state(_), do: %{}

  @spec from_state(map() | nil) :: report() | nil
  def from_state(nil), do: nil

  def from_state(state) when is_map(state) do
    checked_at =
      state
      |> map_get(:checked_at, "checked_at")
      |> normalize_checked_at(DateTime.utc_now() |> DateTime.truncate(:second))

    checks =
      state
      |> map_get(:checks, "checks", [])
      |> normalize_checks(checked_at, @default_timeout_ms)

    if checks == [] do
      nil
    else
      %{
        checked_at: checked_at,
        checks: checks,
        status:
          state
          |> map_get(:status, "status", nil)
          |> normalize_status(overall_status(checks))
      }
    end
  end

  def from_state(_), do: nil

  @doc false
  def default_checker(timeout_ms) do
    checked_at = DateTime.utc_now() |> DateTime.truncate(:second)

    checks =
      [
        run_check(
          "control_plane_store",
          "Control-plane store",
          "Confirm the embedded control-plane store can open and bootstrap its ontology graph.",
          checked_at,
          timeout_ms,
          fn ->
            case StoreServer.health(StoreServer) do
              %{ready?: true, ontology_bootstrap: %{state: :ready}} ->
                {:ok, "Embedded control-plane store is ready."}

              %{ready?: true, ontology_bootstrap: bootstrap} ->
                {:error, "Control-plane ontology bootstrap is not ready: #{inspect(bootstrap)}"}

              health when is_map(health) ->
                {:error, "Control-plane store is not ready: #{inspect(health)}"}

              other ->
                {:error, "Control-plane store returned an unexpected health result: #{inspect(other)}"}
            end
          end
        )
      ] ++
        Enum.map(runtime_checks(), fn runtime_check ->
          run_check(
            runtime_check.id,
            runtime_check.name,
            runtime_check.remediation,
            checked_at,
            timeout_ms,
            fn ->
              if present_runtime_value?(runtime_check.fetch.()) do
                {:ok, "#{runtime_check.name} is configured."}
              else
                {:error, runtime_check.missing_detail}
              end
            end
          )
        end)

    %{
      checked_at: checked_at,
      status: overall_status(checks),
      checks: checks
    }
  end

  defp run_check(id, name, remediation, checked_at, timeout_ms, check_fun) do
    task = Task.async(check_fun)

    {status, detail} =
      case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
        {:ok, :ok} ->
          {:pass, "#{name} check passed."}

        {:ok, {:ok, detail}} ->
          {:pass, normalize_detail(detail, "#{name} check passed.")}

        {:ok, {:error, detail}} ->
          {:fail, normalize_detail(detail, "#{name} check failed.")}

        {:ok, {:timeout, detail}} ->
          {:timeout, normalize_detail(detail, "Check timed out after #{timeout_ms}ms.")}

        {:ok, other} ->
          {:fail, "Check returned an unexpected result: #{inspect(other)}"}

        nil ->
          {:timeout, "Check timed out after #{timeout_ms}ms."}
      end

    %{
      id: id,
      name: name,
      status: status,
      detail: detail,
      remediation: remediation,
      checked_at: checked_at
    }
  end

  defp safe_invoke_checker(checker, timeout_ms) when is_function(checker, 1) do
    task =
      Task.async(fn ->
        try do
          {:ok, checker.(timeout_ms)}
        rescue
          exception ->
            {:error, {:checker_exception, Exception.message(exception)}}
        catch
          kind, reason ->
            {:error, {:checker_throw, {kind, reason}}}
        end
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, result}} ->
        result

      {:ok, {:error, reason}} ->
        {:error, reason}

      nil ->
        {:error, {:checker_timeout, timeout_ms}}
    end
  end

  defp safe_invoke_checker(_checker, _timeout_ms), do: {:error, :invalid_checker}

  defp runtime_checks do
    [
      %{
        id: "runtime_token_signing_secret",
        name: "Runtime configuration: TOKEN_SIGNING_SECRET",
        remediation: "Set `TOKEN_SIGNING_SECRET` in runtime config (or env) and restart JidoCode.",
        fetch: fn -> Application.get_env(:jido_code, :token_signing_secret) end,
        missing_detail: "Required runtime value `TOKEN_SIGNING_SECRET` is missing."
      },
      %{
        id: "runtime_secret_key_base",
        name: "Runtime configuration: SECRET_KEY_BASE",
        remediation: "Set endpoint `secret_key_base` (or env `SECRET_KEY_BASE`) and restart JidoCode.",
        fetch: fn -> Endpoint.config(:secret_key_base) end,
        missing_detail: "Phoenix endpoint `secret_key_base` is missing."
      },
      %{
        id: "runtime_phx_host",
        name: "Runtime configuration: PHX_HOST",
        remediation: "Set endpoint URL host (or env `PHX_HOST`) and restart JidoCode.",
        fetch: fn ->
          Endpoint.config(:url)
          |> Keyword.get(:host)
        end,
        missing_detail: "Phoenix endpoint URL host is missing."
      }
    ]
  end

  defp normalize_report(%{checks: checks} = report, timeout_ms) when is_list(checks) do
    checked_at =
      report
      |> map_get(:checked_at, "checked_at")
      |> normalize_checked_at(DateTime.utc_now() |> DateTime.truncate(:second))

    normalized_checks = normalize_checks(checks, checked_at, timeout_ms)
    default_status = overall_status(normalized_checks)

    %{
      checked_at: checked_at,
      checks: normalized_checks,
      status:
        report
        |> map_get(:status, "status", nil)
        |> normalize_status(default_status)
    }
  end

  defp normalize_report({:error, {:checker_timeout, timeout_ms}}, _timeout_ms),
    do: checker_timeout_report(timeout_ms)

  defp normalize_report({:error, reason}, _timeout_ms), do: checker_error_report(reason)

  defp normalize_report(other, _timeout_ms), do: checker_error_report({:invalid_checker_result, other})

  defp checker_error_report(reason) do
    checked_at = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      checked_at: checked_at,
      status: :fail,
      checks: [
        %{
          id: "prerequisite_checker",
          name: "Prerequisite checker",
          status: :fail,
          detail: "Unable to run prerequisite checks: #{inspect(reason)}",
          remediation: "Verify setup prerequisite checker configuration and retry setup.",
          checked_at: checked_at
        }
      ]
    }
  end

  defp checker_timeout_report(timeout_ms) do
    checked_at = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      checked_at: checked_at,
      status: :timeout,
      checks: [
        %{
          id: "prerequisite_checker",
          name: "Prerequisite checker",
          status: :timeout,
          detail: "Prerequisite checks timed out after #{timeout_ms}ms.",
          remediation:
            "Retry setup. If the check still hangs, inspect the prerequisite checker configuration and runtime dependencies.",
          checked_at: checked_at
        }
      ]
    }
  end

  defp normalize_checks(checks, checked_at, timeout_ms) do
    checks
    |> Enum.with_index()
    |> Enum.map(fn {check, index} ->
      normalize_check(check, checked_at, timeout_ms, index)
    end)
  end

  defp normalize_check(check, default_checked_at, timeout_ms, index) when is_map(check) do
    fallback_name = "Prerequisite check #{index + 1}"

    %{
      id:
        check
        |> map_get(:id, "id", "prerequisite_check_#{index + 1}")
        |> normalize_text("prerequisite_check_#{index + 1}"),
      name:
        check
        |> map_get(:name, "name", fallback_name)
        |> normalize_text(fallback_name),
      status:
        check
        |> map_get(:status, "status", nil)
        |> normalize_status(:fail),
      detail:
        check
        |> map_get(:detail, "detail", nil)
        |> normalize_text("Check timed out after #{timeout_ms}ms."),
      remediation:
        check
        |> map_get(:remediation, "remediation", @default_runtime_remediation)
        |> normalize_text(@default_check_remediation),
      checked_at:
        check
        |> map_get(:checked_at, "checked_at")
        |> normalize_checked_at(default_checked_at)
    }
  end

  defp normalize_check(_check, default_checked_at, _timeout_ms, index) do
    %{
      id: "prerequisite_check_#{index + 1}",
      name: "Prerequisite check #{index + 1}",
      status: :fail,
      detail: "Check result was not a map.",
      remediation: @default_check_remediation,
      checked_at: default_checked_at
    }
  end

  defp normalize_timeout(timeout_ms) when is_integer(timeout_ms) and timeout_ms > 0, do: timeout_ms
  defp normalize_timeout(_), do: @default_timeout_ms

  defp normalize_status(:pass, _default), do: :pass
  defp normalize_status(:fail, _default), do: :fail
  defp normalize_status(:timeout, _default), do: :timeout
  defp normalize_status("pass", _default), do: :pass
  defp normalize_status("fail", _default), do: :fail
  defp normalize_status("timeout", _default), do: :timeout
  defp normalize_status(_, default), do: default

  defp normalize_checked_at(%DateTime{} = checked_at, _default), do: checked_at

  defp normalize_checked_at(checked_at, default) when is_binary(checked_at) do
    case DateTime.from_iso8601(checked_at) do
      {:ok, parsed_checked_at, _offset} -> parsed_checked_at
      {:error, _reason} -> default
    end
  end

  defp normalize_checked_at(_checked_at, default), do: default

  defp normalize_detail(detail, fallback), do: normalize_text(detail, fallback)

  defp normalize_text(value, _fallback) when is_binary(value) and byte_size(value) > 0 do
    String.trim(value)
  end

  defp normalize_text(_value, fallback), do: fallback

  defp map_get(map, atom_key, string_key) do
    map_get(map, atom_key, string_key, nil)
  end

  defp map_get(map, atom_key, string_key, default) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp present_runtime_value?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_runtime_value?(value) when is_list(value), do: value != []
  defp present_runtime_value?(value), do: not is_nil(value)

  defp overall_status(checks) do
    cond do
      Enum.any?(checks, fn check -> check.status == :timeout end) -> :timeout
      Enum.any?(checks, fn check -> check.status == :fail end) -> :fail
      true -> :pass
    end
  end
end
