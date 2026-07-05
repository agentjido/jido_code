defmodule JidoCode.Mix.ControlPlane do
  @moduledoc false

  alias JidoCode.ControlPlane.{Integrity, Recovery}

  @spec run!(atom(), [String.t()]) :: :ok
  def run!(command, args) when is_atom(command) and is_list(args) do
    case command do
      :integrity -> run_integrity!(args)
      :export -> run_export!(args)
      :restore -> run_restore!(args)
      :reset -> run_reset!(args)
    end
  end

  defp run_integrity!(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: [json: :boolean])
    reject_invalid!(invalid)
    reject_rest!(rest)

    case Integrity.check() do
      {:ok, report} ->
        emit(report, Keyword.get(opts, :json, false), &integrity_summary/1)

        if report.status == :failed do
          Mix.raise("Control-plane integrity failed with #{length(report.issues)} issue(s).")
        end

        :ok

      {:error, reason} ->
        Mix.raise("Unable to check control-plane integrity: #{inspect(reason)}")
    end
  end

  defp run_export!(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [format: :string, include_sensitive: :boolean, json: :boolean],
        aliases: [f: :format]
      )

    reject_invalid!(invalid)

    [path] =
      require_exact_args!(rest, 1, "Usage: mix control_plane.export PATH [--format nquads|trig] [--include-sensitive]")

    export_opts = [
      format: format_option(opts),
      redact?: not Keyword.get(opts, :include_sensitive, false)
    ]

    case Recovery.export(path, Enum.reject(export_opts, fn {_key, value} -> is_nil(value) end)) do
      {:ok, report} -> emit(report, Keyword.get(opts, :json, false), &export_summary/1)
      {:error, reason} -> Mix.raise("Unable to export control-plane store: #{inspect(reason)}")
    end
  end

  defp run_restore!(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [format: :string, force: :boolean, json: :boolean],
        aliases: [f: :format]
      )

    reject_invalid!(invalid)
    [path] = require_exact_args!(rest, 1, "Usage: mix control_plane.restore PATH [--format nquads|trig] --force")

    unless Keyword.get(opts, :force, false) do
      Mix.raise("Refusing to restore without --force.")
    end

    restore_opts =
      [format: format_option(opts)]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    case Recovery.restore(path, restore_opts) do
      {:ok, report} -> emit(report, Keyword.get(opts, :json, false), &restore_summary/1)
      {:error, reason} -> Mix.raise("Unable to restore control-plane store: #{inspect(reason)}")
    end
  end

  defp run_reset!(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: [force: :boolean, json: :boolean])
    reject_invalid!(invalid)
    reject_rest!(rest)

    unless Keyword.get(opts, :force, false) or Mix.env() in [:dev, :test] do
      Mix.raise("Refusing to reset the control-plane store outside dev/test without --force.")
    end

    case Recovery.reset() do
      {:ok, health} -> emit(health, Keyword.get(opts, :json, false), &reset_summary/1)
      {:error, reason} -> Mix.raise("Unable to reset control-plane store: #{inspect(reason)}")
    end
  end

  defp emit(report, true, _summary_fun), do: Mix.shell().info(Jason.encode!(json_safe(report), pretty: true))
  defp emit(report, false, summary_fun), do: Mix.shell().info(summary_fun.(report))

  defp integrity_summary(report) do
    "Control-plane integrity #{report.status}: #{length(report.issues)} issue(s), #{report.identities.duplicate_identity_count} duplicate identity value(s), #{report.links.dangling_link_count} dangling link(s)."
  end

  defp export_summary(report) do
    "Exported #{report.exported_quad_count} control-plane quad(s) to #{report.path} as #{report.format}; omitted #{report.omitted_quad_count} redacted quad(s)."
  end

  defp restore_summary(report) do
    "Restored #{report.restored_quad_count} control-plane quad(s) from #{report.path}; integrity #{report.integrity.status}."
  end

  defp reset_summary(health) do
    "Reset control-plane store at #{health.path}; ontology bootstrap #{health.ontology_bootstrap.state}."
  end

  defp format_option(opts) do
    case Keyword.get(opts, :format) do
      nil -> nil
      "nquads" -> :nquads
      "nq" -> :nquads
      "trig" -> :trig
      other -> Mix.raise("Unsupported format #{inspect(other)}. Use nquads or trig.")
    end
  end

  defp reject_invalid!([]), do: :ok

  defp reject_invalid!(invalid) do
    Mix.raise("Unknown option(s): #{Enum.map_join(invalid, ", ", fn {option, _value} -> option end)}")
  end

  defp reject_rest!([]), do: :ok
  defp reject_rest!(rest), do: Mix.raise("Unexpected argument(s): #{Enum.join(rest, " ")}")

  defp require_exact_args!(args, count, usage) do
    if length(args) == count do
      args
    else
      Mix.raise(usage)
    end
  end

  defp json_safe(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp json_safe(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), json_safe(value)} end)
  end

  defp json_safe(list) when is_list(list), do: Enum.map(list, &json_safe/1)
  defp json_safe(value), do: value
end
