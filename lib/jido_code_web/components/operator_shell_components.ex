defmodule JidoCodeWeb.OperatorShellComponents do
  @moduledoc """
  Transitional area-content wrappers used inside the root shell.

  The root shell owns product-area navigation through `JidoCodeWeb.Layouts`.
  These components keep existing route-owned panes addressable while their
  internals move away from the legacy subject-tree visual language.
  """

  use Phoenix.Component

  import JidoCodeWeb.CoreComponents

  attr :id, :string, required: true
  attr :breadcrumbs, :list, default: []
  attr :parent_subjects, :list, default: []
  attr :child_subjects, :list, default: []
  attr :child_nav_id, :string, required: true
  attr :child_nav_label, :string, required: true
  attr :child_nav_heading, :string, required: true
  attr :child_nav_summary, :string, default: nil
  attr :sidebar_id, :string, default: nil
  attr :content_id, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def subject_tree_shell(assigns) do
    ~H"""
    <section id={@id} class={["space-y-4 overflow-x-clip", @class]}>
      <.breadcrumb_lane id={"#{@id}-breadcrumbs"} breadcrumbs={@breadcrumbs} />
      <.parent_subject_rail
        :if={@parent_subjects != []}
        id={"#{@id}-parent-subjects"}
        subjects={@parent_subjects}
      />

      <div class="flex flex-col gap-4 lg:flex-row lg:items-start">
        <aside id={@sidebar_id} class="min-w-0 lg:sticky lg:top-24 lg:w-80 lg:flex-none">
          <.child_subject_sidebar
            id={@child_nav_id}
            label={@child_nav_label}
            heading={@child_nav_heading}
            summary={@child_nav_summary}
            subjects={@child_subjects}
          />
        </aside>

        <div id={@content_id} class="min-w-0 flex-1">
          {render_slot(@inner_block)}
        </div>
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :breadcrumbs, :list, default: []
  attr :pane, :map, required: true
  attr :class, :any, default: nil
  attr :pane_class, :any, default: nil
  slot :inner_block, required: true
  slot :footer_actions

  def single_pane_shell(assigns) do
    ~H"""
    <section id={@id} class={["space-y-4 overflow-x-clip", @class]}>
      <.breadcrumb_lane id={"#{@id}-breadcrumbs"} breadcrumbs={@breadcrumbs} />

      <.subject_pane pane={@pane} class={@pane_class}>
        {render_slot(@inner_block)}

        <:footer_actions>
          {render_slot(@footer_actions)}
        </:footer_actions>
      </.subject_pane>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :breadcrumbs, :list, default: []

  def breadcrumb_lane(assigns) do
    ~H"""
    <nav
      id={@id}
      aria-label="Area breadcrumbs"
      class="overflow-x-auto rounded-lg border border-border bg-muted/40 px-4 py-3"
    >
      <ol class="flex min-w-max flex-nowrap items-center gap-2 text-sm text-muted-foreground sm:min-w-0 sm:flex-wrap">
        <li :for={{breadcrumb, index} <- Enum.with_index(@breadcrumbs)} class="flex items-center gap-2">
          <.breadcrumb_item breadcrumb={breadcrumb} />
          <.icon
            :if={index < length(@breadcrumbs) - 1}
            name="hero-chevron-right-mini"
            class="size-4 text-muted-foreground/60"
          />
        </li>
      </ol>
    </nav>
    """
  end

  attr :breadcrumb, :map, required: true

  defp breadcrumb_item(assigns) do
    ~H"""
    <span :if={@breadcrumb.current?} id={@breadcrumb.id} aria-current="page" class="font-medium text-foreground">
      {@breadcrumb.label}
    </span>

    <.link
      :if={!@breadcrumb.current? and is_binary(@breadcrumb.navigate)}
      id={@breadcrumb.id}
      navigate={@breadcrumb.navigate}
      class="font-medium text-muted-foreground hover:text-foreground"
    >
      {@breadcrumb.label}
    </.link>

    <.link
      :if={!@breadcrumb.current? and !is_binary(@breadcrumb.navigate) and is_binary(@breadcrumb.patch)}
      id={@breadcrumb.id}
      patch={@breadcrumb.patch}
      class="font-medium text-muted-foreground hover:text-foreground"
    >
      {@breadcrumb.label}
    </.link>

    <span
      :if={!@breadcrumb.current? and !is_binary(@breadcrumb.navigate) and !is_binary(@breadcrumb.patch)}
      id={@breadcrumb.id}
      class="font-medium text-muted-foreground"
    >
      {@breadcrumb.label}
    </span>
    """
  end

  attr :id, :string, required: true
  attr :subjects, :list, default: []

  def parent_subject_rail(assigns) do
    ~H"""
    <nav
      id={@id}
      aria-label="Top-level subjects"
      class="overflow-x-auto rounded-lg border border-border bg-card px-3 py-3"
    >
      <div class="flex min-w-max flex-nowrap items-center gap-2 sm:min-w-0 sm:flex-wrap">
        <.subject_chip :for={subject <- @subjects} rail_id={@id} subject={subject} />
      </div>
    </nav>
    """
  end

  attr :rail_id, :string, required: true
  attr :subject, :map, required: true

  defp subject_chip(assigns) do
    ~H"""
    <.link
      :if={is_binary(@subject.patch)}
      id={"#{@rail_id}-#{@subject.id}"}
      patch={@subject.patch}
      aria-current={if(@subject.selected?, do: "page", else: nil)}
      class={[
        "inline-flex items-center gap-2 rounded-md border px-3 py-2 text-sm transition focus:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2",
        if(@subject.selected?,
          do: "border-primary bg-primary/10 text-foreground shadow-sm",
          else: "border-border bg-muted/40 text-muted-foreground hover:bg-card hover:text-foreground"
        )
      ]}
    >
      <.subject_chip_content subject={@subject} />
    </.link>

    <.link
      :if={!is_binary(@subject.patch) and is_binary(@subject.navigate)}
      id={"#{@rail_id}-#{@subject.id}"}
      navigate={@subject.navigate}
      aria-current={if(@subject.selected?, do: "page", else: nil)}
      class={[
        "inline-flex items-center gap-2 rounded-md border px-3 py-2 text-sm transition focus:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2",
        if(@subject.selected?,
          do: "border-primary bg-primary/10 text-foreground shadow-sm",
          else: "border-border bg-muted/40 text-muted-foreground hover:bg-card hover:text-foreground"
        )
      ]}
    >
      <.subject_chip_content subject={@subject} />
    </.link>

    <span
      :if={!is_binary(@subject.patch) and !is_binary(@subject.navigate)}
      id={"#{@rail_id}-#{@subject.id}"}
      aria-current={if(@subject.selected?, do: "page", else: nil)}
      class={[
        "inline-flex items-center gap-2 rounded-md border px-3 py-2 text-sm",
        if(@subject.selected?,
          do: "border-primary bg-primary/10 text-foreground shadow-sm",
          else: "border-border bg-muted/40 text-muted-foreground"
        )
      ]}
    >
      <.subject_chip_content subject={@subject} />
    </span>
    """
  end

  attr :subject, :map, required: true

  defp subject_chip_content(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-2 rounded-md text-sm",
      if(@subject.selected?,
        do: "text-foreground",
        else: "text-inherit"
      )
    ]}>
      <span class="font-semibold">{@subject.label}</span>
      <.subject_description_bubble description={@subject.description} />
    </span>
    """
  end

  attr :description, :string, default: nil

  defp subject_description_bubble(assigns) do
    ~H"""
    <span
      :if={@description}
      tabindex="0"
      role="note"
      title={@description}
      aria-label={@description}
      class="inline-flex size-5 items-center justify-center rounded-md border border-border bg-background text-muted-foreground outline-none transition hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring"
    >
      <.icon name="hero-information-circle-mini" class="size-3.5" />
    </span>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :heading, :string, required: true
  attr :summary, :string, default: nil
  attr :subjects, :list, default: []

  def child_subject_sidebar(assigns) do
    ~H"""
    <section
      aria-labelledby={"#{@id}-heading"}
      class="rounded-lg border border-border bg-muted/40 p-3"
    >
      <div class="space-y-1 px-1">
        <h2 id={"#{@id}-heading"} class="text-xs font-semibold uppercase text-muted-foreground">
          {@heading}
        </h2>
        <p :if={@summary} id={"#{@id}-note"} class="text-sm text-muted-foreground">
          {@summary}
        </p>
      </div>

      <nav
        id={@id}
        aria-label={@label}
        aria-describedby={if @summary, do: "#{@id}-note", else: nil}
        class="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-1"
      >
        <.subject_link :for={subject <- @subjects} nav_id={@id} subject={subject} />
      </nav>
    </section>
    """
  end

  attr :nav_id, :string, required: true
  attr :subject, :map, required: true

  defp subject_link(assigns) do
    ~H"""
    <.link
      :if={is_binary(@subject.patch)}
      id={"#{@nav_id}-#{@subject.id}"}
      patch={@subject.patch}
      aria-current={if(@subject.selected?, do: "page", else: nil)}
      aria-controls={@subject.pane_id}
      aria-describedby={subject_link_describedby(@nav_id, @subject)}
      data-pane-id={@subject.pane_id}
      class={[
        "rounded-md border px-3 py-3 text-left transition focus:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2",
        if(@subject.selected?,
          do: "border-primary bg-primary/10 text-foreground shadow-sm",
          else: "border-border bg-card text-muted-foreground hover:bg-muted hover:text-foreground"
        )
      ]}
    >
      <.subject_link_content nav_id={@nav_id} subject={@subject} />
    </.link>

    <.link
      :if={!is_binary(@subject.patch) and is_binary(@subject.navigate)}
      id={"#{@nav_id}-#{@subject.id}"}
      navigate={@subject.navigate}
      aria-current={if(@subject.selected?, do: "page", else: nil)}
      aria-controls={@subject.pane_id}
      aria-describedby={subject_link_describedby(@nav_id, @subject)}
      data-pane-id={@subject.pane_id}
      class={[
        "rounded-md border px-3 py-3 text-left transition focus:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2",
        if(@subject.selected?,
          do: "border-primary bg-primary/10 text-foreground shadow-sm",
          else: "border-border bg-card text-muted-foreground hover:bg-muted hover:text-foreground"
        )
      ]}
    >
      <.subject_link_content nav_id={@nav_id} subject={@subject} />
    </.link>
    """
  end

  attr :nav_id, :string, required: true
  attr :subject, :map, required: true

  defp subject_link_content(assigns) do
    ~H"""
    <div class="flex items-start justify-between gap-3">
      <div class="min-w-0 space-y-1">
        <p class="font-semibold">{@subject.label}</p>
        <p :if={@subject.summary} id={"#{@nav_id}-#{@subject.id}-summary"} class="text-xs leading-5 text-muted-foreground">
          {@subject.summary}
        </p>
      </div>
      <span
        :if={@subject.badge}
        id={"#{@nav_id}-#{@subject.id}-badge"}
        class={["ui-badge ui-badge-sm font-medium", subject_badge_class(@subject.badge)]}
      >
        {@subject.badge.label}
      </span>
    </div>
    """
  end

  attr :pane, :map, required: true
  attr :class, :any, default: nil
  slot :inner_block, required: true
  slot :footer_actions

  def subject_pane(assigns) do
    ~H"""
    <section
      id={@pane.id}
      role="region"
      aria-labelledby={"#{@pane.id}-title"}
      aria-describedby={"#{@pane.id}-summary"}
      class={["ui-card space-y-0", @class]}
    >
      <header id={"#{@pane.id}-header"} class="space-y-1 border-b border-border px-4 py-4">
        <h2 id={"#{@pane.id}-title"} class="text-lg font-semibold">{@pane.title}</h2>
        <p id={"#{@pane.id}-summary"} class="text-sm text-muted-foreground">
          {@pane.summary}
        </p>
      </header>

      <div id={"#{@pane.id}-middle"} class="space-y-4 px-4 py-4">
        {render_slot(@inner_block)}
      </div>

      <footer
        :if={@footer_actions != []}
        id={"#{@pane.id}-footer"}
        class="flex min-h-16 flex-wrap items-center justify-end gap-2 border-t border-border px-4 py-4"
      >
        {render_slot(@footer_actions)}
      </footer>
    </section>
    """
  end

  defp subject_link_describedby(nav_id, subject) do
    [subject_summary_id(nav_id, subject), subject_badge_id(nav_id, subject)]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      ids -> Enum.join(ids, " ")
    end
  end

  defp subject_summary_id(nav_id, %{summary: summary, id: id}) when is_binary(summary),
    do: "#{nav_id}-#{id}-summary"

  defp subject_summary_id(_nav_id, _subject), do: nil

  defp subject_badge_id(nav_id, %{badge: badge, id: id}) when is_map(badge),
    do: "#{nav_id}-#{id}-badge"

  defp subject_badge_id(_nav_id, _subject), do: nil

  defp subject_badge_class(%{tone: :warning}),
    do: "ui-badge-warning"

  defp subject_badge_class(%{tone: :neutral}),
    do: "ui-badge-neutral"

  defp subject_badge_class(_badge),
    do: "ui-badge-neutral"
end
