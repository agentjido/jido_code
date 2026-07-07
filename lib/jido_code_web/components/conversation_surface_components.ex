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
    <span id={@id} class={["ui-badge ui-badge-sm ui-badge-outline font-medium", status_badge_class(@status), @class]}>
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
    <span id={@id} class={["ui-badge ui-badge-sm ui-badge-outline font-medium", role_badge_class(assigns), @class]}>
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
      class={["ui-badge ui-badge-sm ui-badge-outline font-medium", stream_badge_class(@stream_mode), @class]}
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
          <span :if={!is_nil(@sequence)} class="font-mono text-xs text-muted-foreground">
            ##{@sequence}
          </span>
          <span class={["ui-badge ui-badge-sm ui-badge-outline font-semibold", event_label_class(@tone)]}>
            {@label}
          </span>
          <span :if={present_string?(@event_name)} class="text-xs text-muted-foreground">
            {@event_name}
          </span>
        </div>
        <time :if={present_string?(@occurred_at)} class="text-xs text-muted-foreground">
          {@occurred_at}
        </time>
      </div>
      <p class="mt-2 text-sm font-medium">
        {@title}
      </p>
      <p :if={present_string?(@excerpt)} class="mt-1 whitespace-pre-wrap text-xs text-muted-foreground">
        {@excerpt}
      </p>
    </article>
    """
  end

  defp status_badge_class(status) do
    case normalize_status(status) do
      "active" -> "ui-badge-success"
      "paused" -> "ui-badge-warning"
      "completed" -> "ui-badge-info"
      "cancelled" -> "ui-badge-error"
      "failed" -> "ui-badge-error"
      "blocked" -> "ui-badge-warning"
      _other -> "ui-badge-ghost"
    end
  end

  defp status_label(status), do: normalize_status(status)

  defp role_badge_class(%{historical: true}), do: "ui-badge-info"

  defp role_badge_class(assigns) do
    case role_key(assigns) do
      :repo_intake -> "ui-badge-neutral"
      :governed -> "ui-badge-primary"
      _other -> "ui-badge-ghost"
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
      "live" -> "ui-badge-success"
      "degraded" -> "ui-badge-warning"
      "idle" -> "ui-badge-ghost"
      _other -> "ui-badge-ghost"
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

  defp event_row_class(:error), do: "border-destructive/60 bg-destructive/10"
  defp event_row_class(:warning), do: "border-accent-yellow/60 bg-accent-yellow/10"
  defp event_row_class(:success), do: "border-accent-green/60 bg-accent-green/10"
  defp event_row_class(:status), do: "border-accent-cyan/50 bg-accent-cyan/10"
  defp event_row_class(:input), do: "border-primary/50 bg-primary/5"
  defp event_row_class(:progress), do: "border-accent-cyan/40 bg-accent-cyan/5"
  defp event_row_class(:tool), do: "border-border/70 bg-card"
  defp event_row_class(:turn), do: "border-border/70 bg-muted/20"
  defp event_row_class(_tone), do: "border-border/70 bg-muted/30"

  defp event_label_class(:error), do: "ui-badge-error"
  defp event_label_class(:warning), do: "ui-badge-warning"
  defp event_label_class(:success), do: "ui-badge-success"
  defp event_label_class(:status), do: "ui-badge-info"
  defp event_label_class(:input), do: "ui-badge-primary"
  defp event_label_class(:progress), do: "ui-badge-info"
  defp event_label_class(:tool), do: "ui-badge-neutral"
  defp event_label_class(:turn), do: "ui-badge-ghost"
  defp event_label_class(_tone), do: "ui-badge-ghost"

  defp present_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_string?(_value), do: false
end
