defmodule JidoCode.Config.RuntimeEnvTest do
  # covers: developer.workflow.local_dotenv_bootstrap
  use ExUnit.Case, async: true

  alias JidoCode.Config.RuntimeEnv

  test "bootstraps missing dev env vars from ignored repo-root dotenv files with local precedence" do
    root = make_tmp_dir!("runtime-env-dev")
    File.write!(Path.join(root, ".env"), "FIRST=from-dotenv\nSHARED=from-dotenv\n")
    File.write!(Path.join(root, ".env.local"), "SHARED=from-local\nSECOND=from-local\n")
    File.write!(Path.join(root, ".env.dev.local"), "SECOND=from-dev-local\nTHIRD=from-dev-local\n")

    {:ok, additions} =
      RuntimeEnv.bootstrap(:dev,
        root: root,
        system_env: %{"PRESENT" => "from-shell"},
        put_env: fn _vars -> :ok end
      )

    assert additions == %{
             "FIRST" => "from-dotenv",
             "SHARED" => "from-local",
             "SECOND" => "from-dev-local",
             "THIRD" => "from-dev-local"
           }
  end

  test "does not override explicit shell env vars" do
    root = make_tmp_dir!("runtime-env-shell-precedence")
    File.write!(Path.join(root, ".env"), "SHARED=from-dotenv\nADDED=from-dotenv\n")

    {:ok, additions} =
      RuntimeEnv.bootstrap(:dev,
        root: root,
        system_env: %{"SHARED" => "from-shell"},
        put_env: fn _vars -> :ok end
      )

    assert additions == %{"ADDED" => "from-dotenv"}
  end

  test "supports interpolation from existing shell env vars while keeping shell env final" do
    root = make_tmp_dir!("runtime-env-interpolation")
    File.write!(Path.join(root, ".env"), "CACHE_DIR=${HOME}/cache\nHOME=/tmp/dotenv-home\n")

    {:ok, additions} =
      RuntimeEnv.bootstrap(:dev,
        root: root,
        system_env: %{"HOME" => "/tmp/shell-home"},
        put_env: fn _vars -> :ok end
      )

    assert additions == %{"CACHE_DIR" => "/tmp/shell-home/cache"}
  end

  test "does nothing outside dev" do
    root = make_tmp_dir!("runtime-env-non-dev")
    File.write!(Path.join(root, ".env"), "FIRST=from-dotenv\n")

    assert {:ok, %{}} =
             RuntimeEnv.bootstrap(:test,
               root: root,
               system_env: %{},
               put_env: fn _vars -> flunk("put_env should not run outside dev") end
             )
  end

  test "rejects dotenv command substitution during local bootstrap" do
    root = make_tmp_dir!("runtime-env-command-substitution")
    File.write!(Path.join(root, ".env"), "SECRET=$(whoami)\n")

    assert_raise RuntimeError, ~r/Dotenv command substitution is disabled/, fn ->
      RuntimeEnv.bootstrap(:dev,
        root: root,
        system_env: %{},
        put_env: fn _vars -> :ok end
      )
    end
  end

  defp make_tmp_dir!(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end
end
