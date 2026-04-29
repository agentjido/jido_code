defmodule JidoCode.Mix.OnboardingResetTest do
  # covers: setup.onboarding.reset_mix_task
  # covers: developer.workflow.phoenix_mix_surface
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias JidoCode.Mix.OnboardingReset

  test "parse_args requires exactly one reset mode" do
    assert {:error, message} = OnboardingReset.parse_args([])
    assert message =~ "Choose exactly one reset mode."

    assert {:error, message} = OnboardingReset.parse_args(["--full", "--keep-owner"])
    assert message =~ "Choose exactly one reset mode."
  end

  test "parse_args rejects unexpected options and arguments" do
    assert {:error, message} = OnboardingReset.parse_args(["--bogus"])
    assert message =~ "Unknown options"

    assert {:error, message} = OnboardingReset.parse_args(["--full", "extra"])
    assert message =~ "Unexpected arguments"
  end

  test "run! prints the full-reset summary" do
    output =
      capture_io(fn ->
        assert :ok =
                 OnboardingReset.run!(["--full"],
                   runner: fn :full ->
                     {:ok,
                      %{
                        mode: :full,
                        cleared_owner_count: 2,
                        cleared_managed_repo_count: 3,
                        cleared_onboarding_pat?: true,
                        owner_email: nil
                      }}
                   end
                 )
      end)

    assert output =~ "Onboarding reset to first-run bootstrap."
    assert output =~ "Cleared 2 local user(s) and 3 managed repo(s)."
    assert output =~ "3 managed repo(s)."
    assert output =~ "Cleared onboarding-managed GitHub PAT fallback."
  end

  test "run! prints the keep-owner summary" do
    output =
      capture_io(fn ->
        assert :ok =
                 OnboardingReset.run!(["--keep-owner"],
                   runner: fn :keep_owner ->
                     {:ok,
                      %{
                        mode: :keep_owner,
                        cleared_owner_count: 0,
                        cleared_managed_repo_count: 1,
                        cleared_onboarding_pat?: false,
                        owner_email: "owner@example.com"
                      }}
                   end
                 )
      end)

    assert output =~
             "Onboarding rewound to the signed-in setup surface for owner@example.com."

    assert output =~ "Cleared 1 managed repo(s)."
  end
end
