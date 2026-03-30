defmodule JidoCode.Control.Actor do
  @moduledoc """
  Normalizes human and machine actor classes for control-plane authorization.
  """

  alias JidoCode.Accounts.User

  @actor_classes [
    :admin,
    :operator,
    :factory_system,
    :managed_repo_orchestrator,
    :run_worker,
    :external_ingress
  ]

  @type actor_class ::
          :admin
          | :operator
          | :factory_system
          | :managed_repo_orchestrator
          | :run_worker
          | :external_ingress

  @spec classes() :: [actor_class()]
  def classes, do: @actor_classes

  @spec class(term()) :: actor_class() | nil
  def class(%User{} = actor), do: human_default(actor)

  def class(%{} = actor) do
    actor
    |> actor_class_value()
    |> normalize_actor_class(human_default(actor))
  end

  def class(_actor), do: nil

  @spec allowed?(term(), [actor_class()]) :: boolean()
  def allowed?(actor, classes) when is_list(classes), do: class(actor) in classes

  @spec admin_actor(map()) :: map()
  def admin_actor(attrs \\ %{}), do: build_actor(:admin, "admin", attrs)

  @spec operator_actor(map()) :: map()
  def operator_actor(attrs \\ %{}), do: build_actor(:operator, "operator", attrs)

  @spec factory_system_actor(map()) :: map()
  def factory_system_actor(attrs \\ %{}), do: build_actor(:factory_system, "factory-system", attrs)

  @spec managed_repo_orchestrator_actor(map()) :: map()
  def managed_repo_orchestrator_actor(attrs \\ %{}),
    do: build_actor(:managed_repo_orchestrator, "managed-repo-orchestrator", attrs)

  @spec run_worker_actor(map()) :: map()
  def run_worker_actor(attrs \\ %{}), do: build_actor(:run_worker, "run-worker", attrs)

  @spec external_ingress_actor(map()) :: map()
  def external_ingress_actor(attrs \\ %{}), do: build_actor(:external_ingress, "external-ingress", attrs)

  defp build_actor(actor_class, fallback_id, attrs) do
    attrs
    |> normalize_map()
    |> Map.put_new("id", "system:#{fallback_id}")
    |> Map.put("actor_class", Atom.to_string(actor_class))
  end

  defp actor_class_value(actor) do
    Map.get(actor, :actor_class) ||
      Map.get(actor, "actor_class") ||
      Map.get(actor, :class) ||
      Map.get(actor, "class") ||
      Map.get(actor, :role) ||
      Map.get(actor, "role") ||
      Map.get(actor, :user_type) ||
      Map.get(actor, "user_type")
  end

  defp human_default(%User{}), do: :operator

  defp human_default(%{} = actor) do
    if present?(Map.get(actor, :id) || Map.get(actor, "id")) or
         present?(Map.get(actor, :email) || Map.get(actor, "email")) do
      :operator
    else
      nil
    end
  end

  defp human_default(_actor), do: nil

  defp normalize_actor_class(value, _fallback) when value in @actor_classes, do: value

  defp normalize_actor_class(value, fallback) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "admin" -> :admin
      "operator" -> :operator
      "user" -> :operator
      "factory_system" -> :factory_system
      "factory-system" -> :factory_system
      "managed_repo_orchestrator" -> :managed_repo_orchestrator
      "managed-repo-orchestrator" -> :managed_repo_orchestrator
      "run_worker" -> :run_worker
      "run-worker" -> :run_worker
      "external_ingress" -> :external_ingress
      "external-ingress" -> :external_ingress
      _other -> fallback
    end
  end

  defp normalize_actor_class(value, fallback) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_actor_class(fallback)
  end

  defp normalize_actor_class(_value, fallback), do: fallback

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      Map.put(acc, normalized_key, nested_value)
    end)
  end

  defp normalize_map(_value), do: %{}

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)
end
