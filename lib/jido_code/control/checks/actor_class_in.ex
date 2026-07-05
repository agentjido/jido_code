defmodule JidoCode.Control.Checks.ActorClassIn do
  # covers: architecture.policy_layers.ash_policy_is_first_class_data_plane_membrane
  # covers: architecture.policy_layers.legacy_and_ingress_surfaces_require_explicit_actor_context
  @moduledoc false

  alias JidoCode.Control.Actor

  def match?(actor, _context, opts) do
    {:ok, Actor.allowed?(Actor.effective_actor(actor), Keyword.get(opts, :classes, []))}
  end

  def describe(opts) do
    allowed =
      opts
      |> Keyword.get(:classes, [])
      |> Enum.map_join(", ", &to_string/1)

    "actor class is one of [#{allowed}]"
  end
end
