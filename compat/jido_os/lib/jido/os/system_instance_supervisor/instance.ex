defmodule Jido.Os.SystemInstanceSupervisor.Instance do
  @moduledoc false

  alias Jido.Os.SystemInstanceSupervisor

  def ready?(instance_id) when is_binary(instance_id) do
    match?({:ok, _pid}, SystemInstanceSupervisor.lookup_instance(instance_id))
  end
end
