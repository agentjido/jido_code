defmodule JidoCodeWeb.OperatorStateComponents do
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  # covers: architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
  @moduledoc false

  use Phoenix.Component

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :state, :map, required: true
  attr :kind, :atom, default: :warning
  attr :compact, :boolean, default: false
  attr :dom_prefix, :string, default: nil
  attr :class, :any, default: nil
  slot :actions
  slot :inner_block

  def operator_state_notice(assigns) do
    ~H"""
    <section
      id={@id}
      role={if @kind == :error, do: "alert", else: "status"}
      aria-live={if @kind == :error, do: "assertive", else: "polite"}
      aria-label={@title}
      class={[
        "rounded-lg border space-y-2",
        state_classes(@kind),
        if(@compact, do: "p-3", else: "p-4"),
        @class
      ]}
    >
      <p id={"#{state_dom_prefix(@dom_prefix, @id)}-label"} class="break-words font-semibold">{@title}</p>
      <p
        :if={typed_state_value(@state)}
        id={"#{state_dom_prefix(@dom_prefix, @id)}-type"}
        class="break-words text-sm"
      >
        {typed_prefix(@kind)}: {typed_state_value(@state)}
      </p>
      <p
        :if={state_detail(@state)}
        id={"#{state_dom_prefix(@dom_prefix, @id)}-detail"}
        class="break-words text-sm"
      >
        {state_detail(@state)}
      </p>
      <p
        :if={state_remediation(@state)}
        id={"#{state_dom_prefix(@dom_prefix, @id)}-remediation"}
        class="break-words text-sm"
      >
        {state_remediation(@state)}
      </p>
      {render_slot(@inner_block)}
      <div :if={Enum.any?(@actions)} class="flex flex-wrap gap-3 pt-1">
        {render_slot(@actions)}
      </div>
    </section>
    """
  end

  defp state_classes(:error), do: "border-destructive/60 bg-destructive/10"
  defp state_classes(:info), do: "border-accent-cyan/60 bg-accent-cyan/10"
  defp state_classes(_kind), do: "border-accent-yellow/60 bg-accent-yellow/10"

  defp typed_prefix(:error), do: "Typed error"
  defp typed_prefix(:info), do: "Typed info"
  defp typed_prefix(:notice), do: "Typed notice"
  defp typed_prefix(_kind), do: "Typed warning"

  defp typed_state_value(state), do: Map.get(state, :error_type) || Map.get(state, "error_type")
  defp state_detail(state), do: Map.get(state, :detail) || Map.get(state, "detail")
  defp state_remediation(state), do: Map.get(state, :remediation) || Map.get(state, "remediation")
  defp state_dom_prefix(nil, id), do: id
  defp state_dom_prefix(prefix, _id), do: prefix
end
