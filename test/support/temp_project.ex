defmodule Jido.Code.Server.TestSupport.TempProject do
  @moduledoc """
  Helpers for creating temporary project roots with `.jido` layout during tests.
  """

  alias Jido.Code.Server.Project.Layout

  @spec create!(keyword()) :: String.t()
  def create!(opts \\ []) do
    root = Path.join(System.tmp_dir!(), "jido_code_server_#{System.unique_integer([:positive])}")
    data_dir = Keyword.get(opts, :data_dir, ".jido")

    layout = Layout.ensure_layout!(root, data_dir)

    Keyword.get(opts, :with_seed_files, false)
    |> maybe_seed(layout)

    root
  end

  @spec copy_fixture!(String.t(), keyword()) :: String.t()
  def copy_fixture!(fixture_name, opts \\ []) do
    root =
      Path.join(
        System.tmp_dir!(),
        "jido_code_server_fixture_#{System.unique_integer([:positive])}"
      )

    fixture_root = fixture_root(fixture_name)

    File.cp_r!(fixture_root, root)

    if Keyword.get(opts, :ensure_layout, true) do
      _ = Layout.ensure_layout!(root, ".jido")
    end

    root
  end

  @spec cleanup(String.t()) :: :ok
  def cleanup(path) do
    File.rm_rf(path)
    :ok
  end

  defp maybe_seed(false, _layout), do: :ok

  defp maybe_seed(true, layout) do
    File.write!(Path.join(layout.skills, "example_skill.md"), "# Example Skill\n")
    File.write!(Path.join(layout.commands, "example_command.md"), "# Example Command\n")
    File.write!(Path.join(layout.workflows, "example_workflow.md"), "# Example Workflow\n")
    File.write!(Path.join(layout.skill_graph, "index.md"), "# Example Graph\n")
  end

  defp fixture_root(fixture_name) do
    Path.expand("../fixtures/#{fixture_name}", __DIR__)
  end
end
