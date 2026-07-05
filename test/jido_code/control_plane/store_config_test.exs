defmodule JidoCode.ControlPlane.StoreConfigTest do
  use ExUnit.Case, async: true

  alias JidoCode.ControlPlane.StoreConfig
  alias JidoCode.SourceCodeGraph

  test "explicit store path wins and is expanded" do
    relative_path = "tmp/control-plane-store-config-test"

    assert StoreConfig.store_path(path: relative_path) == Path.expand(relative_path)
  end

  test "test store paths are partitioned and separate from repository-local semantic stores" do
    test_path = StoreConfig.test_store_path(self())
    source_graph_path = SourceCodeGraph.graph_store_path("/workspace/example")

    assert test_path =~ "jido_code_control_plane_store"
    refute test_path == source_graph_path
    refute String.contains?(test_path, ".jido_code/source_code_graph/triple_store")
  end

  test "reset policy and timeout have conservative defaults" do
    assert StoreConfig.reset_policy([]) in [:bootstrap_if_empty, :reset_on_start]
    assert StoreConfig.reset_policy(reset_policy: :preserve) == :preserve
    assert StoreConfig.open_timeout_ms(open_timeout_ms: 250) == 250
    assert StoreConfig.open_timeout_ms(open_timeout_ms: -1) == 5_000
  end
end
