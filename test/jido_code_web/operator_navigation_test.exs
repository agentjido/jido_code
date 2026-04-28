defmodule JidoCodeWeb.OperatorNavigationTest do
  use ExUnit.Case, async: true

  alias JidoCodeWeb.OperatorNavigation

  test "omits global navigation when no signed-in actor is present" do
    assert OperatorNavigation.from_view(JidoCodeWeb.DashboardLive, %{}) == nil
  end

  test "marks dashboard as the selected major destination for the authenticated home" do
    navigation = OperatorNavigation.from_view(JidoCodeWeb.DashboardLive, %{current_user: %{id: "user-1"}})

    assert navigation.route_badge == "Authenticated home"
    assert navigation.route_label == "Dashboard"

    assert Enum.any?(navigation.major_destinations, fn destination ->
             destination.id == :dashboard and destination.selected? and
               destination.navigate == "/dashboard?subject=work&section=overview"
           end)
  end

  test "defaults direct repo detail entry to the repositories major destination" do
    navigation =
      OperatorNavigation.from_view(JidoCodeWeb.ProjectDetailLive, %{
        current_user: %{id: "user-1"},
        project_detail: %{github_full_name: "owner/repo-navigation"}
      })

    assert navigation.route_badge == "Managed repo"
    assert navigation.route_label == "owner/repo-navigation"
    assert navigation.context_links == [%{id: "operator-context-repo", label: "owner/repo-navigation", current?: true}]

    assert Enum.any?(navigation.major_destinations, fn destination ->
             destination.id == :repositories and destination.selected?
           end)
  end

  test "keeps run detail aligned to dashboard when the broader parent route is dashboard work" do
    navigation =
      OperatorNavigation.from_view(JidoCodeWeb.RunDetailLive, %{
        current_user: %{id: "user-1"},
        project_id: "owner-repo-one",
        run_id: "run-123",
        return_to_path:
          "/repos/owner-repo-one?return_to=" <>
            URI.encode_www_form("/dashboard?subject=work&section=overview")
      })

    assert navigation.route_badge == "Governed run"
    assert navigation.route_label == "Run run-123"

    assert Enum.any?(navigation.major_destinations, fn destination ->
             destination.id == :dashboard and destination.selected?
           end)

    assert Enum.any?(navigation.context_links, fn context_link ->
             context_link.id == "operator-context-repo" and
               context_link.navigate ==
                 "/repos/owner-repo-one?return_to=" <>
                   URI.encode_www_form("/dashboard?subject=work&section=overview")
           end)

    assert Enum.any?(navigation.context_links, fn context_link ->
             context_link.id == "operator-context-run" and context_link.current? and
               context_link.label == "Run run-123"
           end)
  end

  test "surfaces the active settings tab as contextual orientation" do
    navigation =
      OperatorNavigation.from_view(JidoCodeWeb.SettingsLive, %{
        current_user: %{id: "user-1"},
        active_tab: "auth"
      })

    assert navigation.route_badge == "Operator configuration"
    assert navigation.route_label == "Settings"

    assert navigation.context_links == [
             %{id: "operator-context-settings-tab", label: "Auth & Integrations", current?: true}
           ]

    assert Enum.any?(navigation.major_destinations, fn destination ->
             destination.id == :settings and destination.selected?
           end)
  end
end
