defmodule JidoCodeWeb.UIResetPolicyTest do
  use ExUnit.Case, async: true

  @policy_path ".planning/ui-reset-policy.md"

  test "policy forbids compatibility layers for deleted UI chrome" do
    policy = File.read!(@policy_path)

    assert policy =~ "No DaisyUI compatibility layer remains after the cutover phase."
    assert policy =~ "deleted or rewritten, not hidden behind"
    assert policy =~ "not direct `SaladUI.*` imports"
    assert policy =~ "not direct LiveVue mount targets"
  end

  test "policy preserves product-owned server boundaries" do
    policy = File.read!(@policy_path)

    assert policy =~ "LiveView remains the routed host shell"
    assert policy =~ "`JidoCodeWeb.LiveVueComponents.vue_surface/1`"
    assert policy =~ "Product service contracts, test fixtures, auth/session behavior"
    assert policy =~ "LiveVue fallback behavior are preserved"
  end

  test "policy defines compile-safe migration order" do
    policy = File.read!(@policy_path)

    assert policy =~ "dependency, CSS token, SaladUI wrapper, and shadcn-vue primitive"
    assert policy =~ "root area shell and button-menu routing contract"
    assert policy =~ "Remove DaisyUI from npm dependencies only after first-party runtime class"
    assert policy =~ "Keep public bootstrap and setup routes working"
  end

  test "policy records stop conditions before destructive deletion" do
    policy = File.read!(@policy_path)

    assert policy =~ "Do not delete a route before its replacement route"
    assert policy =~ "Do not remove a Vue widget before any required semantic-event"
    assert policy =~ "Do not remove DaisyUI from `package.json`"
    assert policy =~ "Do not introduce new browser-owned route state"
  end
end
