defmodule JidoCode.Setup.PrerequisiteChecksTest do
  use ExUnit.Case, async: false

  alias JidoCode.Setup.PrerequisiteChecks

  @managed_env_keys [:setup_prerequisite_checker]

  setup do
    original_env =
      Enum.map(@managed_env_keys, fn key ->
        {key, Application.get_env(:jido_code, key, :__missing__)}
      end)

    on_exit(fn ->
      Enum.each(original_env, fn {key, value} ->
        restore_env(key, value)
      end)
    end)

    :ok
  end

  test "run/1 returns a timeout report when the outer checker hangs" do
    Application.put_env(:jido_code, :setup_prerequisite_checker, fn _timeout_ms ->
      Process.sleep(200)

      %{
        checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
        status: :pass,
        checks: []
      }
    end)

    report = PrerequisiteChecks.run(25)

    assert report.status == :timeout

    assert [
             %{
               id: "prerequisite_checker",
               name: "Prerequisite checker",
               status: :timeout,
               detail: detail
             }
           ] = report.checks

    assert detail =~ "timed out after 25ms"
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
