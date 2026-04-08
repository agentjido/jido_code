defmodule JidoCode.SourceCodeGraph.HelperQueries do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  @moduledoc false

  alias JidoCode.SourceCodeGraph

  @spec modules(map(), map()) :: String.t()
  def modules(graph_context, params \\ %{}) do
    limit = positive_limit(params[:limit], 25)

    filter =
      case normalized_string(params[:module_name_contains]) do
        nil ->
          ""

        search ->
          """
            FILTER(CONTAINS(LCASE(STR(?module_name)), LCASE("#{escape_string(search)}")))
          """
      end

    """
    SELECT ?module ?module_name
    WHERE {
      ?module a struct:Module .
      OPTIONAL { ?module struct:moduleName ?module_name . }
    #{filter}
      FILTER(STRSTARTS(STR(?module), "#{SourceCodeGraph.base_iri(graph_context.managed_repo_id)}"))
    }
    ORDER BY ?module_name ?module
    LIMIT #{limit}
    """
  end

  @spec functions(map(), map()) :: String.t()
  def functions(graph_context, params \\ %{}) do
    limit = positive_limit(params[:limit], 50)

    module_filter =
      case normalized_string(params[:module_name]) do
        nil ->
          ""

        module_name ->
          """
            FILTER(STR(?module_name) = "#{escape_string(module_name)}")
          """
      end

    function_filter =
      case normalized_string(params[:function_name]) do
        nil ->
          ""

        function_name ->
          """
            FILTER(STR(?function_name) = "#{escape_string(function_name)}")
          """
      end

    """
    SELECT ?module ?module_name ?function ?function_name ?arity
    WHERE {
      ?module a struct:Module ;
              struct:containsFunction ?function .
      OPTIONAL { ?module struct:moduleName ?module_name . }
      ?function a struct:Function .
      OPTIONAL { ?function struct:functionName ?function_name . }
      OPTIONAL { ?function struct:arity ?arity . }
      FILTER(STRSTARTS(STR(?module), "#{SourceCodeGraph.base_iri(graph_context.managed_repo_id)}"))
    #{module_filter}
    #{function_filter}
    }
    ORDER BY ?module_name ?function_name ?arity
    LIMIT #{limit}
    """
  end

  @spec runtime_patterns(map(), map()) :: String.t()
  def runtime_patterns(graph_context, params \\ %{}) do
    limit = positive_limit(params[:limit], 50)

    pattern_filter =
      case normalized_string(params[:pattern_name_contains]) do
        nil ->
          ""

        search ->
          """
            FILTER(CONTAINS(LCASE(STR(?pattern)), LCASE("#{escape_string(search)}")))
          """
      end

    """
    SELECT ?subject ?pattern
    WHERE {
      ?subject a ?pattern .
      FILTER(STRSTARTS(STR(?subject), "#{SourceCodeGraph.base_iri(graph_context.managed_repo_id)}"))
      FILTER(STRSTARTS(STR(?pattern), "https://w3id.org/elixir-code/otp#"))
    #{pattern_filter}
    }
    ORDER BY ?pattern ?subject
    LIMIT #{limit}
    """
  end

  @spec impact(map(), map()) :: String.t()
  def impact(graph_context, params \\ %{}) do
    limit = positive_limit(params[:limit], 50)
    subject_iri = impact_subject_iri(graph_context, params)
    direction = params[:direction] || :outgoing

    case direction do
      :incoming ->
        """
        SELECT ?source ?predicate
        WHERE {
          ?source ?predicate <#{subject_iri}> .
          FILTER(STRSTARTS(STR(?source), "#{SourceCodeGraph.base_iri(graph_context.managed_repo_id)}"))
        }
        ORDER BY ?predicate ?source
        LIMIT #{limit}
        """

      :both ->
        """
        SELECT ?source ?predicate ?target
        WHERE {
          {
            BIND(<#{subject_iri}> AS ?source)
            <#{subject_iri}> ?predicate ?target .
          }
          UNION
          {
            ?source ?predicate <#{subject_iri}> .
            BIND(<#{subject_iri}> AS ?target)
          }
          FILTER(
            (isIRI(?source) && STRSTARTS(STR(?source), "#{SourceCodeGraph.base_iri(graph_context.managed_repo_id)}")) ||
            (isIRI(?target) && STRSTARTS(STR(?target), "#{SourceCodeGraph.base_iri(graph_context.managed_repo_id)}"))
          )
        }
        ORDER BY ?predicate ?source ?target
        LIMIT #{limit}
        """

      _outgoing ->
        """
        SELECT ?predicate ?target
        WHERE {
          <#{subject_iri}> ?predicate ?target .
          FILTER(
            !isIRI(?target) ||
              STRSTARTS(STR(?target), "#{SourceCodeGraph.base_iri(graph_context.managed_repo_id)}") ||
              STRSTARTS(STR(?target), "https://w3id.org/elixir-code/")
          )
        }
        ORDER BY ?predicate ?target
        LIMIT #{limit}
        """
    end
  end

  defp impact_subject_iri(graph_context, params) do
    cond do
      is_binary(params[:subject_iri]) and String.trim(params[:subject_iri]) != "" ->
        String.trim(params[:subject_iri])

      is_binary(params[:function_name]) and String.trim(params[:function_name]) != "" ->
        module_name =
          normalized_string(params[:module_name]) ||
            raise ArgumentError, "module_name is required when function_name is provided"

        arity = positive_limit(params[:arity], 1)

        "#{SourceCodeGraph.base_iri(graph_context.managed_repo_id)}#{module_name}/#{String.trim(params[:function_name])}/#{arity}"

      is_binary(params[:module_name]) and String.trim(params[:module_name]) != "" ->
        "#{SourceCodeGraph.base_iri(graph_context.managed_repo_id)}#{String.trim(params[:module_name])}"

      true ->
        raise ArgumentError, "subject_iri or module_name is required for impact queries"
    end
  end

  defp normalized_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalized_string(_), do: nil

  defp positive_limit(nil, default), do: default
  defp positive_limit(value, _default) when is_integer(value) and value > 0, do: value

  defp positive_limit(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end

  defp positive_limit(_value, default), do: default

  defp escape_string(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end
end
