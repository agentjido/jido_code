defmodule JidoCodeWeb.OperatorShellComponents do
  @moduledoc false

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
    <section id={@id} class={["space-y-4", @class]}>
      <.breadcrumb_lane id={"#{@id}-breadcrumbs"} breadcrumbs={@breadcrumbs} />
      <.parent_subject_rail id={"#{@id}-parent-subjects"} subjects={@parent_subjects} />

      <div class="flex flex-col gap-4 lg:flex-row lg:items-start">
        <aside id={@sidebar_id} class="min-w-0 lg:w-80 lg:flex-none">
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

  def breadcrumb_lane(assigns) do
    ~H"""
    <nav
      id={@id}
      aria-label="Operator breadcrumbs"
      class="rounded-lg border border-base-300/70 bg-base-200/20 px-4 py-3"
    >
      <ol class="flex flex-wrap items-center gap-2 text-sm text-base-content/75">
        <li :for={{breadcrumb, index} <- Enum.with_index(@breadcrumbs)} class="flex items-center gap-2">
          <.breadcrumb_item breadcrumb={breadcrumb} />
          <.icon
            :if={index < length(@breadcrumbs) - 1}
            name="hero-chevron-right-mini"
            class="size-4 text-base-content/35"
          />
        </li>
      </ol>
    </nav>
    """
  end

  attr :breadcrumb, :map, required: true

  defp breadcrumb_item(assigns) do
    ~H"""
    <span :if={@breadcrumb.current?} id={@breadcrumb.id} aria-current="page" class="font-medium text-base-content">
      {@breadcrumb.label}
    </span>

    <.link
      :if={!@breadcrumb.current? and is_binary(@breadcrumb.navigate)}
      id={@breadcrumb.id}
      navigate={@breadcrumb.navigate}
      class="link link-hover font-medium"
    >
      {@breadcrumb.label}
    </.link>

    <.link
      :if={!@breadcrumb.current? and !is_binary(@breadcrumb.navigate) and is_binary(@breadcrumb.patch)}
      id={@breadcrumb.id}
      patch={@breadcrumb.patch}
      class="link link-hover font-medium"
    >
      {@breadcrumb.label}
    </.link>

    <span
      :if={!@breadcrumb.current? and !is_binary(@breadcrumb.navigate) and !is_binary(@breadcrumb.patch)}
      id={@breadcrumb.id}
      class="font-medium"
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
      class="rounded-lg border border-base-300/70 bg-base-100 px-3 py-3"
    >
      <div class="flex flex-wrap items-center gap-2">
        <.subject_chip :for={subject <- @subjects} subject={subject} />
      </div>
    </nav>
    """
  end

  attr :subject, :map, required: true

  defp subject_chip(assigns) do
    ~H"""
    <div class={[
      "inline-flex items-center gap-2 rounded-lg border px-3 py-2 text-sm",
      if(@subject.selected?,
        do: "border-primary/60 bg-primary/8 text-base-content shadow-sm",
        else: "border-base-300/70 bg-base-200/20 text-base-content/80"
      )
    ]}>
      <span class="font-semibold">{@subject.label}</span>
      <.subject_description_bubble description={@subject.description} />
    </div>
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
      class="inline-flex size-5 items-center justify-center rounded-full border border-base-300/70 bg-base-100 text-base-content/55 outline-none transition hover:text-base-content focus-visible:ring-2 focus-visible:ring-primary/40"
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
    <section class="rounded-lg border border-base-300/70 bg-base-200/20 p-3">
      <div class="space-y-1 px-1">
        <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/55">
          {@heading}
        </p>
        <p :if={@summary} id={"#{@id}-note"} class="text-sm text-base-content/70">
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
      class={[
        "rounded-lg border px-3 py-3 text-left transition",
        if(@subject.selected?,
          do: "border-primary/60 bg-primary/8 text-base-content shadow-sm",
          else: "border-base-300/70 bg-base-100/85 text-base-content/80 hover:border-base-300 hover:bg-base-100"
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
      class={[
        "rounded-lg border px-3 py-3 text-left transition",
        if(@subject.selected?,
          do: "border-primary/60 bg-primary/8 text-base-content shadow-sm",
          else: "border-base-300/70 bg-base-100/85 text-base-content/80 hover:border-base-300 hover:bg-base-100"
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
        <p :if={@subject.summary} id={"#{@nav_id}-#{@subject.id}-summary"} class="text-xs leading-5 text-base-content/65">
          {@subject.summary}
        </p>
      </div>
      <span
        :if={@subject.badge}
        id={"#{@nav_id}-#{@subject.id}-badge"}
        class="badge badge-sm border font-medium"
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
    <section id={@pane.id} class={["space-y-0 rounded-lg border border-base-300 bg-base-100", @class]}>
      <header id={"#{@pane.id}-header"} class="space-y-1 border-b border-base-300/70 px-4 py-4">
        <h2 id={"#{@pane.id}-title"} class="text-lg font-semibold">{@pane.title}</h2>
        <p id={"#{@pane.id}-summary"} class="text-sm text-base-content/70">
          {@pane.summary}
        </p>
      </header>

      <div id={"#{@pane.id}-middle"} class="space-y-4 px-4 py-4">
        {render_slot(@inner_block)}
      </div>

      <footer
        id={"#{@pane.id}-footer"}
        class="flex min-h-16 flex-wrap items-center justify-end gap-2 border-t border-base-300/70 px-4 py-4"
      >
        {render_slot(@footer_actions)}
      </footer>
    </section>
    """
  end
end
