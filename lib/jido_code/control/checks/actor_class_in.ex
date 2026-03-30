defmodule JidoCode.Control.Checks.ActorClassIn do
  @moduledoc false

  use Ash.Policy.SimpleCheck

  alias JidoCode.Control.Actor

  @impl true
  def match?(actor, _context, opts) do
    {:ok, Actor.allowed?(actor, Keyword.get(opts, :classes, []))}
  end

  @impl true
  def describe(opts) do
    allowed =
      opts
      |> Keyword.get(:classes, [])
      |> Enum.map_join(", ", &to_string/1)

    "actor class is one of [#{allowed}]"
  end
end
