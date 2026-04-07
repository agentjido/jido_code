defmodule JidoCode.KG.OntologyHelperTest do
  use ExUnit.Case, async: true

  alias JidoCode.KG.OntologyHelper

  describe "available?/0" do
    test "returns false when elixir_ontologies is not installed" do
      # The Ontologies module should not be available by default
      refute OntologyHelper.available?()
    end
  end

  describe "enabled?/0" do
    test "returns false when ontology is not configured" do
      refute OntologyHelper.enabled?()
    end

    test "returns false when configured but module not available" do
      # Even if enabled in config, without the module it returns false
      Application.put_env(:jido_code, :ontology_enabled, true)

      refute OntologyHelper.available?()
      refute OntologyHelper.enabled?()

      on_exit(fn ->
        Application.delete_env(:jido_code, :ontology_enabled)
      end)
    end
  end

  describe "generate/1" do
    test "returns error when ontology not available" do
      assert {:error, :not_available} = OntologyHelper.generate()
    end
  end

  describe "generate_and_load/1" do
    test "returns error when ontology not available" do
      assert {:error, :not_available} = OntologyHelper.generate_and_load()
    end
  end
end
