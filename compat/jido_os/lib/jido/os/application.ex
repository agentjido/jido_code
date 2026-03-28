defmodule Jido.Os.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Jido.Os.State
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Jido.Os.Supervisor)
  end
end
