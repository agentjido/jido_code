defmodule JidoCodeWeb.ProjectInventoryLive do
  # covers: architecture.frontend_stack.liveview_remains_product_host_shell
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  use JidoCodeWeb, :live_view

  alias JidoCode.Workbench.Inventory
  alias JidoCodeWeb.RouteShell

  @default_branch_filter_value "all"
  @default_filter_values %{
    "search" => "",
    "default_branch" => @default_branch_filter_value
  }
  @filter_query_keys ["search", "default_branch"]
  @max_search_query_length 120

  @impl true
  def mount(_params, _session, socket) do
    projects = load_projects()

    {:ok,
     socket
     |> assign(:projects_all, projects)
     |> assign(:project_count, 0)
     |> assign(:project_total_count, length(projects))
     |> assign(:filter_values, @default_filter_values)
     |> assign(:filter_form, to_filter_form(@default_filter_values))
     |> assign(:default_branch_filter_options, default_branch_filter_options(projects))
     |> stream(:projects, [], reset: true)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter_values = normalize_filter_values(params, socket.assigns.projects_all)
    {:noreply, apply_filters(socket, filter_values)}
  end

  @impl true
  def handle_event("apply_filters", %{"filters" => filter_params}, socket) do
    filter_values = normalize_filter_values(filter_params, socket.assigns.projects_all)

    {:noreply,
     socket
     |> apply_filters(filter_values)
     |> push_patch(to: projects_path_with_filter_values(filter_values))}
  end

  @impl true
  def handle_event("apply_filters", _params, socket) do
    {:noreply,
     socket
     |> apply_filters(@default_filter_values)
     |> push_patch(to: "/repos")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={%{}}
      active_area={:repositories}
      area_panel={JidoCodeWeb.AreaPanels.panel_for(:repositories)}
    >
      <.route_pane_shell
        id="project-inventory-shell"
        breadcrumbs={project_inventory_breadcrumbs()}
        pane={project_inventory_pane()}
      >
        <section id="project-inventory-filters-panel" class="rounded-lg border border-border bg-card p-4">
          <.form
            for={@filter_form}
            id="project-inventory-filters-form"
            phx-change="apply_filters"
            phx-submit="apply_filters"
            class="grid gap-3 lg:grid-cols-[minmax(16rem,1fr)_minmax(14rem,1fr)]"
          >
            <.input
              id="project-inventory-filter-search"
              field={@filter_form[:search]}
              type="text"
              label="Search"
              placeholder="Repository, name, branch, or repository ID"
            />
            <.input
              id="project-inventory-filter-default-branch"
              field={@filter_form[:default_branch]}
              type="select"
              label="Default branch"
              options={@default_branch_filter_options}
            />
          </.form>

          <div id="project-inventory-filter-chips" class="flex flex-wrap gap-2 pt-2">
            <span id="project-inventory-filter-chip-search" class="ui-badge ui-badge-outline">
              Search: {search_chip_label(@filter_values)}
            </span>
            <span id="project-inventory-filter-chip-default-branch" class="ui-badge ui-badge-outline">
              Default branch: {default_branch_chip_label(@filter_values)}
            </span>
          </div>

          <p id="project-inventory-results-count" class="pt-2 text-xs text-muted-foreground">
            Showing {@project_count} of {@project_total_count} repositories.
          </p>
        </section>

        <section class="rounded-lg border border-border bg-card overflow-x-auto">
          <table id="project-inventory-table" class="w-full caption-bottom text-sm">
            <thead>
              <tr>
                <th>Repository</th>
                <th>Display name</th>
                <th>Default branch</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody id="project-inventory-rows" phx-update="stream">
              <tr :if={@project_count == 0} id="project-inventory-empty-state">
                <td colspan="4" class="py-8 text-center text-sm text-muted-foreground">
                  No repositories match the active search and filters.
                </td>
              </tr>
              <tr :for={{dom_id, project} <- @streams.projects} id={dom_id}>
                <td id={"project-inventory-github-full-name-#{project.id}"} class="font-medium">
                  {project.github_full_name}
                </td>
                <td id={"project-inventory-name-#{project.id}"}>{project.name}</td>
                <td id={"project-inventory-default-branch-#{project.id}"}>
                  {project.default_branch}
                </td>
                <td id={"project-inventory-actions-#{project.id}"}>
                  <%= if detail_path = project_detail_path(project, @filter_values) do %>
                    <.link
                      id={"project-inventory-open-#{project.id}"}
                      class="text-primary underline-offset-4 hover:underline"
                      href={detail_path}
                    >
                      Open repo
                    </.link>
                  <% else %>
                    <span id={"project-inventory-open-disabled-#{project.id}"} class="text-muted-foreground">
                      Repo detail unavailable
                    </span>
                  <% end %>
                </td>
              </tr>
            </tbody>
          </table>
        </section>

        <:footer_actions>
          <.link id="project-inventory-reset-filters" patch={~p"/repos"} class="ui-button ui-button-sm ui-button-outline">
            Clear filters
          </.link>
          <button
            id="project-inventory-apply-filters"
            type="submit"
            form="project-inventory-filters-form"
            class="ui-button ui-button-sm ui-button-primary"
          >
            Apply filters
          </button>
        </:footer_actions>
      </.route_pane_shell>
    </Layouts.app>
    """
  end

  defp project_inventory_breadcrumbs do
    [
      RouteShell.breadcrumb(%{
        id: "project-inventory-breadcrumb-current",
        label: "Repositories",
        current?: true
      })
    ]
  end

  defp project_inventory_pane do
    RouteShell.pane(%{
      id: "project-inventory-pane",
      title: "Managed repository inventory",
      summary: "Search and filter imported repositories, then open repo detail."
    })
  end

  defp load_projects do
    case Inventory.load() do
      {:ok, rows, _warning} -> Enum.map(rows, &to_project_row/1)
      {:error, _reason} -> []
    end
  end

  defp to_project_row(row) do
    project_id =
      row
      |> map_get(:id, "id")
      |> normalize_optional_string()

    project_name =
      row
      |> map_get(:name, "name")
      |> normalize_optional_string()

    github_full_name =
      row
      |> map_get(:github_full_name, "github_full_name")
      |> normalize_optional_string()

    default_branch =
      row
      |> map_get(:default_branch, "default_branch")
      |> normalize_optional_string() || "main"

    %{
      id: project_id || github_full_name || project_name || "unknown-project",
      name: project_name || github_full_name || "unknown-project",
      github_full_name: github_full_name || project_name || "unknown-project",
      default_branch: default_branch
    }
  end

  defp apply_filters(socket, filter_values) do
    filtered_projects = filter_projects(socket.assigns.projects_all, filter_values)

    socket
    |> assign(:project_count, length(filtered_projects))
    |> assign(:project_total_count, length(socket.assigns.projects_all))
    |> assign(:filter_values, filter_values)
    |> assign(:filter_form, to_filter_form(filter_values))
    |> assign(:default_branch_filter_options, default_branch_filter_options(socket.assigns.projects_all))
    |> stream(:projects, filtered_projects, reset: true)
  end

  defp filter_projects(projects, filter_values) do
    search_term =
      filter_values
      |> Map.fetch!("search")
      |> String.downcase()

    default_branch_filter = Map.fetch!(filter_values, "default_branch")

    Enum.filter(projects, fn project ->
      default_branch_matches?(project, default_branch_filter) and
        search_matches?(project, search_term)
    end)
  end

  defp default_branch_matches?(_project, @default_branch_filter_value), do: true

  defp default_branch_matches?(project, default_branch_filter) do
    Map.get(project, :default_branch) == default_branch_filter
  end

  defp search_matches?(_project, ""), do: true

  defp search_matches?(project, search_term) do
    [
      Map.get(project, :github_full_name),
      Map.get(project, :name),
      Map.get(project, :default_branch),
      Map.get(project, :id)
    ]
    |> Enum.any?(fn value ->
      case normalize_optional_string(value) do
        nil -> false
        normalized_value -> String.contains?(String.downcase(normalized_value), search_term)
      end
    end)
  end

  defp normalize_filter_values(filter_values, projects) when is_map(filter_values) do
    %{
      "search" =>
        filter_values
        |> map_get("search", :search)
        |> normalize_search_query(),
      "default_branch" =>
        filter_values
        |> map_get("default_branch", :default_branch)
        |> normalize_default_branch_filter(projects)
    }
  end

  defp normalize_filter_values(_filter_values, _projects), do: @default_filter_values

  defp normalize_search_query(search_query) do
    case normalize_optional_string(search_query) do
      nil ->
        ""

      normalized_search_query ->
        if valid_search_query?(normalized_search_query) do
          normalized_search_query
        else
          ""
        end
    end
  end

  defp valid_search_query?(search_query) do
    String.length(search_query) <= @max_search_query_length and
      String.match?(search_query, ~r/^[\p{L}\p{N}\s\/._-]+$/u)
  end

  defp normalize_default_branch_filter(default_branch_filter, projects) do
    candidate_filter_value =
      normalize_optional_string(default_branch_filter) || @default_branch_filter_value

    valid_filter_values =
      projects
      |> Enum.map(&Map.get(&1, :default_branch))
      |> Enum.reject(&is_nil/1)
      |> then(&MapSet.new([@default_branch_filter_value | &1]))

    if MapSet.member?(valid_filter_values, candidate_filter_value) do
      candidate_filter_value
    else
      @default_branch_filter_value
    end
  end

  defp default_branch_filter_options(projects) do
    dynamic_options =
      projects
      |> Enum.map(fn project ->
        project
        |> Map.get(:default_branch)
        |> normalize_optional_string()
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort_by(&String.downcase/1)
      |> Enum.map(fn default_branch -> {default_branch, default_branch} end)

    [{"All branches", @default_branch_filter_value} | dynamic_options]
  end

  defp projects_path_with_filter_values(filter_values) do
    query_params =
      @filter_query_keys
      |> Enum.reduce([], fn key, acc ->
        value = Map.get(filter_values, key, Map.fetch!(@default_filter_values, key))
        default_value = Map.fetch!(@default_filter_values, key)

        if value == default_value do
          acc
        else
          [{key, value} | acc]
        end
      end)
      |> Enum.reverse()

    case query_params do
      [] -> "/repos"
      _other -> "/repos?" <> URI.encode_query(query_params)
    end
  end

  defp project_detail_path(project, filter_values) do
    project
    |> Map.get(:id)
    |> normalize_optional_string()
    |> case do
      nil ->
        nil

      project_id ->
        base_path = "/repos/#{URI.encode(project_id)}"
        return_to = projects_path_with_filter_values(filter_values)

        if return_to == "/repos" do
          base_path
        else
          "#{base_path}?return_to=#{URI.encode_www_form(return_to)}"
        end
    end
  end

  defp search_chip_label(filter_values) do
    case Map.fetch!(filter_values, "search") do
      "" -> "Any"
      search_query -> search_query
    end
  end

  defp default_branch_chip_label(filter_values) do
    case Map.fetch!(filter_values, "default_branch") do
      @default_branch_filter_value -> "All branches"
      default_branch -> default_branch
    end
  end

  defp to_filter_form(filter_values), do: to_form(filter_values, as: :filters)

  defp map_get(map, atom_key, string_key) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> nil
    end
  end

  defp map_get(_map, _atom_key, _string_key), do: nil

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_boolean(value), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized_value -> normalized_value
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(value) when is_float(value), do: :erlang.float_to_binary(value)
  defp normalize_optional_string(_value), do: nil
end
