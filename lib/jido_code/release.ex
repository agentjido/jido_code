defmodule JidoCode.Release do
  @moduledoc """
  Release task compatibility for the embedded-store runtime.
  """

  def migrate, do: :ok

  def rollback(_repo, _version), do: {:error, :embedded_store_has_no_sql_migrations}

  def create_db, do: :ok
end
