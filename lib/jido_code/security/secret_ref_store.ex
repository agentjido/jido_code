defmodule JidoCode.Security.SecretRefStore do
  @moduledoc """
  Store-backed SecretRef metadata, lifecycle audit, and encrypted material access.
  """

  alias JidoCode.ControlPlane.Codecs.Registry
  alias JidoCode.ControlPlane.ProductStore
  alias JidoCode.ControlPlane.Store.Errors.NotFoundError
  alias JidoCode.Security.{SecretLifecycleAudit, SecretMaterialStore, SecretRef}

  @control_plane_ns JidoCode.ControlPlane.SemanticIdentity.ontology_namespace()
  @scopes [:instance, :project, :integration]
  @sources [:env, :onboarding, :rotation]
  @actions [:create, :rotate, :revoke]
  @outcomes [:succeeded, :failed]

  @spec upsert_secret_ref(map(), keyword()) :: {:ok, SecretRef.t()} | {:error, term()}
  def upsert_secret_ref(attrs, opts \\ []) when is_map(attrs) do
    with {:ok, record} <- secret_ref_record(attrs),
         {:ok, ciphertext} <- required_string(map_get(attrs, :ciphertext), :invalid_ciphertext),
         previous_material <- material_snapshot(record.secret_ref_id, opts),
         :ok <- SecretMaterialStore.put(record.secret_ref_id, ciphertext, opts) do
      case ProductStore.dispatch(:upsert, :secret_ref, Keyword.merge([record: record], opts)) do
        {:ok, %{record: saved_record}} ->
          {:ok, to_secret_ref(saved_record, ciphertext)}

        {:error, reason} ->
          restore_material(record.secret_ref_id, previous_material, opts)
          {:error, reason}
      end
    end
  end

  @spec restore_secret_ref(SecretRef.t(), keyword()) :: {:ok, SecretRef.t()} | {:error, term()}
  def restore_secret_ref(%SecretRef{} = secret_ref, opts \\ []) do
    upsert_secret_ref(
      %{
        id: secret_ref.id,
        scope: secret_ref.scope,
        name: secret_ref.name,
        ciphertext: secret_ref.ciphertext,
        source: secret_ref.source,
        key_version: secret_ref.key_version,
        last_rotated_at: secret_ref.last_rotated_at,
        expires_at: secret_ref.expires_at
      },
      opts
    )
  end

  @spec get_by_scope_name(atom(), String.t(), keyword()) :: {:ok, SecretRef.t() | nil} | {:error, term()}
  def get_by_scope_name(scope, name, opts \\ []) do
    canonical_key = canonical_key(scope, name)

    request_opts =
      Keyword.merge(
        [
          identity: %{
            identity: :unique_scope_name,
            predicate_iri: RDF.iri(@control_plane_ns <> "canonicalKey"),
            value: canonical_key
          }
        ],
        opts
      )

    case ProductStore.dispatch(:get, :secret_ref, request_opts) do
      {:ok, %{projection: projection}} -> decode_secret_ref_projection(projection, opts)
      {:error, %NotFoundError{}} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec get_by_id(String.t(), keyword()) :: {:ok, SecretRef.t()} | {:error, :not_found | term()}
  def get_by_id(secret_ref_id, opts \\ []) when is_binary(secret_ref_id) and secret_ref_id != "" do
    case ProductStore.dispatch(:get, :secret_ref, Keyword.merge([record: %{id: secret_ref_id}], opts)) do
      {:ok, %{projection: projection}} -> decode_secret_ref_projection(projection, opts)
      {:error, %NotFoundError{}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec list_secret_refs(keyword()) :: {:ok, [SecretRef.t()]} | {:error, term()}
  def list_secret_refs(opts \\ []) do
    case ProductStore.dispatch(:list, :secret_ref, Keyword.merge([query: %{limit: 500, offset: 0}], opts)) do
      {:ok, %{projections: projections}} ->
        secret_refs =
          projections
          |> Enum.map(&decode_secret_ref_projection(&1, opts))
          |> Enum.flat_map(fn
            {:ok, secret_ref} -> [secret_ref]
            {:error, _reason} -> []
          end)
          |> Enum.sort_by(&sort_datetime(&1.updated_at || &1.last_rotated_at), {:desc, DateTime})

        {:ok, secret_refs}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec delete_secret_ref(SecretRef.t(), keyword()) :: :ok | {:error, term()}
  def delete_secret_ref(%SecretRef{id: secret_ref_id}, opts \\ []) do
    case ProductStore.dispatch(:delete, :secret_ref, Keyword.merge([record: %{secret_ref_id: secret_ref_id}], opts)) do
      {:ok, _outcome} ->
        SecretMaterialStore.delete(secret_ref_id, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec create_lifecycle_audit(map(), keyword()) :: {:ok, SecretLifecycleAudit.t()} | {:error, term()}
  def create_lifecycle_audit(attrs, opts \\ []) when is_map(attrs) do
    with {:ok, record} <- audit_record(attrs) do
      case ProductStore.dispatch(:create, :secret_lifecycle_audit, Keyword.merge([record: record], opts)) do
        {:ok, %{record: saved_record}} -> {:ok, to_lifecycle_audit(saved_record)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec list_lifecycle_audits(keyword()) :: {:ok, [SecretLifecycleAudit.t()]} | {:error, term()}
  def list_lifecycle_audits(opts \\ []) do
    case ProductStore.dispatch(:list, :secret_lifecycle_audit, Keyword.merge([query: %{limit: 500, offset: 0}], opts)) do
      {:ok, %{projections: projections}} ->
        audits =
          projections
          |> Enum.map(&decode_audit_projection/1)
          |> Enum.flat_map(fn
            {:ok, audit} -> [audit]
            {:error, _reason} -> []
          end)
          |> Enum.sort_by(&sort_datetime(&1.occurred_at), {:desc, DateTime})

        {:ok, audits}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def canonical_key(scope, name), do: "#{scope}:#{name}"

  defp secret_ref_record(attrs) do
    with {:ok, scope} <- normalize_scope(map_get(attrs, :scope)),
         {:ok, name} <- required_string(map_get(attrs, :name), :invalid_name),
         {:ok, source} <- normalize_source(map_get(attrs, :source, :onboarding)),
         {:ok, key_version} <- normalize_integer(map_get(attrs, :key_version, 1), :invalid_key_version) do
      id = map_get(attrs, :secret_ref_id) || map_get(attrs, :id) || Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok,
       %{
         secret_ref_id: id,
         canonical_key: canonical_key(scope, name),
         scope: Atom.to_string(scope),
         name: name,
         display_name: map_get(attrs, :display_name) || name,
         provider: map_get(attrs, :provider),
         provider_host: map_get(attrs, :provider_host),
         source: Atom.to_string(source),
         key_version: key_version,
         last_rotated_at: normalize_datetime(map_get(attrs, :last_rotated_at)) || now,
         expires_at: normalize_datetime(map_get(attrs, :expires_at)),
         updated_at: now,
         metadata: map_get(attrs, :metadata, %{})
       }}
    end
  end

  defp audit_record(attrs) do
    with {:ok, scope} <- normalize_scope(map_get(attrs, :scope)),
         {:ok, name} <- required_string(map_get(attrs, :name), :invalid_name),
         {:ok, action_type} <- normalize_atom(map_get(attrs, :action_type), @actions, :invalid_action_type),
         {:ok, outcome_status} <- normalize_atom(map_get(attrs, :outcome_status), @outcomes, :invalid_outcome_status),
         {:ok, actor_id} <- required_string(map_get(attrs, :actor_id), :invalid_actor_id),
         {:ok, secret_ref_id} <- required_string(map_get(attrs, :secret_ref_id), :invalid_secret_ref_id) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok,
       %{
         secret_lifecycle_audit_id:
           map_get(attrs, :secret_lifecycle_audit_id) || map_get(attrs, :id) || Ecto.UUID.generate(),
         secret_ref_id: secret_ref_id,
         scope: Atom.to_string(scope),
         name: name,
         action_type: Atom.to_string(action_type),
         outcome_status: Atom.to_string(outcome_status),
         actor_id: actor_id,
         actor_email: normalize_optional_string(map_get(attrs, :actor_email)),
         occurred_at: normalize_datetime(map_get(attrs, :occurred_at)) || now,
         updated_at: now,
         metadata: map_get(attrs, :metadata, %{})
       }}
    end
  end

  defp decode_secret_ref_projection(projection, opts) do
    with {:ok, record} <- Registry.decode(:secret_ref, projection),
         secret_ref_id <- map_get(record, :secret_ref_id),
         {:ok, ciphertext} <- SecretMaterialStore.get(secret_ref_id, opts) do
      {:ok, to_secret_ref(record, ciphertext)}
    else
      {:error, :not_found} ->
        with {:ok, record} <- Registry.decode(:secret_ref, projection) do
          {:ok, to_secret_ref(record, nil)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_audit_projection(projection) do
    with {:ok, record} <- Registry.decode(:secret_lifecycle_audit, projection) do
      {:ok, to_lifecycle_audit(record)}
    end
  end

  defp to_secret_ref(record, ciphertext) when is_map(record) do
    %SecretRef{
      id: map_get(record, :secret_ref_id) || map_get(record, :id),
      scope: normalize_scope!(map_get(record, :scope)),
      name: map_get(record, :name),
      ciphertext: ciphertext,
      key_version: normalize_integer!(map_get(record, :key_version, 1)),
      source: normalize_source!(map_get(record, :source, :onboarding)),
      last_rotated_at: normalize_datetime(map_get(record, :last_rotated_at)),
      expires_at: normalize_datetime(map_get(record, :expires_at)),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
  end

  defp to_lifecycle_audit(record) when is_map(record) do
    %SecretLifecycleAudit{
      id: map_get(record, :secret_lifecycle_audit_id) || map_get(record, :id),
      secret_ref_id: map_get(record, :secret_ref_id),
      scope: normalize_scope!(map_get(record, :scope)),
      name: map_get(record, :name),
      action_type: normalize_atom!(map_get(record, :action_type), @actions),
      outcome_status: normalize_atom!(map_get(record, :outcome_status), @outcomes),
      actor_id: map_get(record, :actor_id),
      actor_email: map_get(record, :actor_email),
      occurred_at: normalize_datetime(map_get(record, :occurred_at)),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
  end

  defp material_snapshot(secret_ref_id, opts) do
    case SecretMaterialStore.get(secret_ref_id, opts) do
      {:ok, ciphertext} -> {:ok, ciphertext}
      {:error, :not_found} -> :missing
      {:error, reason} -> {:error, reason}
    end
  end

  defp restore_material(secret_ref_id, {:ok, ciphertext}, opts),
    do: SecretMaterialStore.put(secret_ref_id, ciphertext, opts)

  defp restore_material(secret_ref_id, :missing, opts), do: SecretMaterialStore.delete(secret_ref_id, opts)
  defp restore_material(_secret_ref_id, {:error, _reason}, _opts), do: :ok

  defp normalize_scope(scope) when scope in @scopes, do: {:ok, scope}

  defp normalize_scope(scope) when is_binary(scope) do
    normalize_atom(scope, @scopes, :invalid_scope)
  end

  defp normalize_scope(_scope), do: {:error, :invalid_scope}
  defp normalize_scope!(scope), do: elem(normalize_scope(scope), 1)

  defp normalize_source(source) when source in @sources, do: {:ok, source}

  defp normalize_source(source) when is_binary(source) do
    normalize_atom(source, @sources, :invalid_source)
  end

  defp normalize_source(_source), do: {:error, :invalid_source}
  defp normalize_source!(source), do: elem(normalize_source(source), 1)

  defp normalize_atom(value, allowed, error) when is_atom(value) do
    if value in allowed, do: {:ok, value}, else: {:error, error}
  end

  defp normalize_atom(value, allowed, error) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.to_existing_atom()
    |> normalize_atom(allowed, error)
  rescue
    ArgumentError -> {:error, error}
  end

  defp normalize_atom(_value, _allowed, error), do: {:error, error}
  defp normalize_atom!(value, allowed), do: elem(normalize_atom(value, allowed, :invalid_atom), 1)

  defp normalize_integer(value, _error) when is_integer(value), do: {:ok, value}

  defp normalize_integer(value, error) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _other -> {:error, error}
    end
  end

  defp normalize_integer(_value, error), do: {:error, error}
  defp normalize_integer!(value), do: elem(normalize_integer(value, :invalid_integer), 1)

  defp required_string(value, error) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, error}
      trimmed -> {:ok, trimmed}
    end
  end

  defp required_string(value, error) when is_atom(value), do: value |> Atom.to_string() |> required_string(error)
  defp required_string(_value, error), do: {:error, error}

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_datetime(%DateTime{} = datetime), do: datetime
  defp normalize_datetime(nil), do: nil

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _other -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp sort_datetime(%DateTime{} = datetime), do: datetime
  defp sort_datetime(_datetime), do: ~U[1970-01-01 00:00:00Z]

  defp map_get(map, key, default \\ nil)
  defp map_get(map, key, default) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  defp map_get(_map, _key, default), do: default
end
