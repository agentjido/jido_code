defmodule JidoCode.Mix.OnboardingReset do
  # covers: setup.onboarding.reset_mix_task
  # covers: developer.workflow.phoenix_mix_surface
  @moduledoc false

  alias JidoCode.Setup.OnboardingReset

  @spec run!([String.t()], keyword()) :: :ok
  def run!(args, opts \\ []) when is_list(args) and is_list(opts) do
    with {:ok, mode} <- parse_args(args),
         {:ok, report} <- reset_runner(opts).(mode) do
      Mix.shell().info(summary(report))
      :ok
    else
      {:error, message} when is_binary(message) ->
        Mix.raise(message)

      {:error, {error_type, message}} when is_atom(error_type) and is_binary(message) ->
        Mix.raise(message)

      {:error, reason} ->
        Mix.raise("Unable to reset onboarding (#{inspect(reason)}).")
    end
  end

  @spec parse_args([String.t()]) :: {:ok, OnboardingReset.mode()} | {:error, String.t()}
  def parse_args(args) when is_list(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args, strict: [full: :boolean, keep_owner: :boolean])

    full? = Keyword.get(opts, :full, false)
    keep_owner? = Keyword.get(opts, :keep_owner, false)

    cond do
      invalid != [] ->
        {:error, usage("Unknown options: #{Enum.map_join(invalid, ", ", fn {option, _value} -> option end)}.")}

      rest != [] ->
        {:error, usage("Unexpected arguments: #{Enum.join(rest, " ")}.")}

      full? and keep_owner? ->
        {:error, usage("Choose exactly one reset mode.")}

      full? ->
        {:ok, :full}

      keep_owner? ->
        {:ok, :keep_owner}

      true ->
        {:error, usage("Choose exactly one reset mode.")}
    end
  end

  defp reset_runner(opts) do
    Keyword.get(opts, :runner, &OnboardingReset.reset/1)
  end

  defp summary(%{
         mode: :full,
         cleared_owner_count: cleared_owner_count,
         cleared_onboarding_pat?: cleared_onboarding_pat?
       }) do
    "Onboarding reset to first-run bootstrap. Cleared #{cleared_owner_count} local user(s).#{pat_suffix(cleared_onboarding_pat?)}"
  end

  defp summary(%{
         mode: :keep_owner,
         owner_email: owner_email,
         cleared_onboarding_pat?: cleared_onboarding_pat?
       }) do
    "Onboarding rewound to the signed-in setup surface for #{owner_email}.#{pat_suffix(cleared_onboarding_pat?)}"
  end

  defp pat_suffix(true), do: " Cleared onboarding-managed GitHub PAT fallback."
  defp pat_suffix(false), do: ""

  defp usage(prefix) do
    "#{prefix} Use `mix onboarding.reset --full` for first-run reset or `mix onboarding.reset --keep-owner` to preserve the bootstrap owner and return to `/setup`."
  end
end
