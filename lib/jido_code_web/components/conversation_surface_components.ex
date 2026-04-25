defmodule JidoCodeWeb.ConversationSurfaceComponents do
  # covers: architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage
  # covers: architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage
  # covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
  @moduledoc false

  use Phoenix.Component

  attr :id, :string, default: nil
  attr :status, :any, required: true
  attr :class, :any, default: nil

  def conversation_status_badge(assigns) do
    ~H"""
    <span id={@id} class={["badge badge-sm badge-outline font-medium", status_badge_class(@status), @class]}>
      {status_label(@status)}
    </span>
    """
  end

  attr :id, :string, default: nil
  attr :scope, :any, default: nil
  attr :attachment_mode, :any, default: nil
  attr :work_item_id, :string, default: nil
  attr :historical, :boolean, default: false
  attr :class, :any, default: nil

  def conversation_role_badge(assigns) do
    ~H"""
    <span id={@id} class={["badge badge-sm badge-outline font-medium", role_badge_class(assigns), @class]}>
      {role_label(assigns)}
    </span>
    """
  end

  attr :id, :string, default: nil
  attr :stream_mode, :any, required: true
  attr :discontinuity_count, :integer, default: 0
  attr :class, :any, default: nil

  def conversation_stream_badge(assigns) do
    ~H"""
    <span
      id={@id}
      class={["badge badge-sm badge-outline font-medium", stream_badge_class(@stream_mode), @class]}
    >
      {stream_label(@stream_mode)}
      <span :if={@discontinuity_count > 0} class="ml-1 text-[10px] opacity-80">
        +{@discontinuity_count} gaps
      </span>
    </span>
    """
  end

  attr :id, :string, required: true
  attr :sequence, :any, default: nil
  attr :label, :string, required: true
  attr :title, :string, required: true
  attr :excerpt, :string, default: nil
  attr :occurred_at, :string, default: nil
  attr :event_name, :string, default: nil
  attr :tone, :any, default: :neutral

  def conversation_event_row(assigns) do
    ~H"""
    <article id={@id} class={["rounded-md border p-3", event_row_class(@tone)]}>
      <div class="flex flex-wrap items-center justify-between gap-2">
        <div class="flex items-center gap-2">
          <span :if={!is_nil(@sequence)} class="font-mono text-xs text-base-content/60">
            ##{@sequence}
          </span>
          <span class={["badge badge-sm badge-outline font-semibold", event_label_class(@tone)]}>
            {@label}
          </span>
          <span :if={present_string?(@event_name)} class="text-xs text-base-content/60">
            {@event_name}
          </span>
        </div>
        <time :if={present_string?(@occurred_at)} class="text-xs text-base-content/60">
          {@occurred_at}
        </time>
      </div>
      <p class="mt-2 text-sm font-medium">
        {@title}
      </p>
      <p :if={present_string?(@excerpt)} class="mt-1 whitespace-pre-wrap text-xs text-base-content/70">
        {@excerpt}
      </p>
    </article>
    """
  end

  defp status_badge_class(status) do
    case normalize_status(status) do
      "active" -> "badge-success"
      "paused" -> "badge-warning"
      "completed" -> "badge-info"
      "cancelled" -> "badge-error"
      "failed" -> "badge-error"
      "blocked" -> "badge-warning"
      _other -> "badge-ghost"
    end
  end

  defp status_label(status), do: normalize_status(status)

  defp role_badge_class(%{historical: true}), do: "badge-info"

  defp role_badge_class(assigns) do
    case role_key(assigns) do
      :repo_intake -> "badge-neutral"
      :governed -> "badge-primary"
      _other -> "badge-ghost"
    end
  end

  defp role_label(%{historical: true}), do: "Historical lineage"

  defp role_label(assigns) do
    case role_key(assigns) do
      :repo_intake -> "Repo intake"
      :governed -> "Governed conversation"
      _other -> "Conversation"
    end
  end

  defp role_key(%{scope: scope, attachment_mode: attachment_mode, work_item_id: work_item_id}) do
    normalized_scope = normalize_status(scope)
    normalized_attachment = normalize_status(attachment_mode)

    cond do
      present_string?(work_item_id) -> :governed
      normalized_scope == "work_item_scoped" -> :governed
      normalized_scope == "repo_scoped" and normalized_attachment == "pre_work" -> :repo_intake
      normalized_attachment == "pre_work" -> :repo_intake
      true -> :conversation
    end
  end

  defp stream_badge_class(stream_mode) do
    case normalize_status(stream_mode) do
      "live" -> "badge-success"
      "degraded" -> "badge-warning"
      "idle" -> "badge-ghost"
      _other -> "badge-ghost"
    end
  end

  defp stream_label(stream_mode) do
    case normalize_status(stream_mode) do
      "live" -> "Live stream"
      "degraded" -> "Snapshot only"
      "idle" -> "Idle"
      other -> other
    end
  end

  defp normalize_status(value) when is_binary(value) do
    case String.trim(value) do
      "" -> "unknown"
      trimmed -> trimmed
    end
  end

  defp normalize_status(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_status()
  defp normalize_status(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_status(_value), do: "unknown"

  defp event_row_class(:error), do: "border-error/60 bg-error/10"
  defp event_row_class(:warning), do: "border-warning/60 bg-warning/10"
  defp event_row_class(:success), do: "border-success/60 bg-success/10"
  defp event_row_class(:status), do: "border-info/50 bg-info/10"
  defp event_row_class(:input), do: "border-primary/50 bg-primary/5"
  defp event_row_class(:progress), do: "border-info/40 bg-info/5"
  defp event_row_class(:tool), do: "border-base-300/70 bg-base-100"
  defp event_row_class(:turn), do: "border-base-300/70 bg-base-200/20"
  defp event_row_class(_tone), do: "border-base-300/70 bg-base-200/30"

  defp event_label_class(:error), do: "badge-error"
  defp event_label_class(:warning), do: "badge-warning"
  defp event_label_class(:success), do: "badge-success"
  defp event_label_class(:status), do: "badge-info"
  defp event_label_class(:input), do: "badge-primary"
  defp event_label_class(:progress), do: "badge-info"
  defp event_label_class(:tool), do: "badge-neutral"
  defp event_label_class(:turn), do: "badge-ghost"
  defp event_label_class(_tone), do: "badge-ghost"

  defp present_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_string?(_value), do: false
end
