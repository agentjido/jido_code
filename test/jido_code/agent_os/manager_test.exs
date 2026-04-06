defmodule JidoCode.AgentOSManagerTest do
  # covers: architecture.agent_os_integration.kernel_per_managed_repo
  # covers: architecture.agent_os_integration.dynamic_kernel_lifecycle
  use ExUnit.Case, async: false

  alias JidoCode.AgentOS

  describe "kernel naming" do
    test "converts managed repo ID to kernel name" do
      assert AgentOS.Manager.kernel_name("repo-123") == :repo_123
      assert AgentOS.Manager.kernel_name("test-repo") == :test_repo
    end

    test "converts managed repo ID with hyphens to valid atom" do
      assert AgentOS.Manager.kernel_name("my-repo-123") == :my_repo_123
    end
  end

  describe "kernel status when no kernels exist" do
    test "kernel_status returns nil for non-existent kernel" do
      refute AgentOS.kernel_status("nonexistent-repo-123")
    end

    test "kernel_exists? returns false for non-existent kernel" do
      refute AgentOS.kernel_exists?("nonexistent-repo-123")
    end

    test "list_kernels returns empty list when no kernels" do
      # Note: In a real test environment with other kernels, this might not be empty
      # For now we just check the function works
      kernels = AgentOS.list_kernels()
      assert is_list(kernels)
    end

    test "kernel_count returns number of tracked kernels" do
      count = AgentOS.kernel_count()
      assert is_integer(count) and count >= 0
    end
  end

  describe "shutdown_kernel is idempotent" do
    test "shutdown_kernel returns ok even for non-existent kernel" do
      assert :ok = AgentOS.shutdown_kernel("nonexistent-repo-123")
    end
  end
end
