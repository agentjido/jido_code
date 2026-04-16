defmodule JidoCodeWeb.LLMSettingsLiveTest do
  use JidoCodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias JidoCode.LLM.Discovery
  alias JidoCode.Security.SecretRefs

  setup %{conn: conn} do
    # Register and authenticate a user
    email = "test#{System.unique_integer()}@example.com"
    password = "TestPassword123!"
    :ok = register_owner(email, password)
    conn = authenticate_owner_conn(conn, email, password)

    {:ok, conn: conn, email: email}
  end

  describe "mount/3" do
    test "mounts successfully for authenticated user", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings/llm")

      assert html =~ "LLM Provider Settings"
      assert html =~ "Configure API keys"
    end

    test "renders all providers from Discovery", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings/llm")

      providers = Discovery.list_providers()

      # Check that major providers are rendered
      # Note: Discovery returns provider names directly, which may have different capitalization
      anthropic = Enum.find(providers, fn p -> p.id == :anthropic end)
      assert anthropic != nil
      assert html =~ anthropic.name

      # Verify we have provider cards
      assert html =~ "card"
    end

    test "shows credential status badges", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings/llm")

      # Should show credential status badges
      assert html =~ "badge"
    end
  end

  describe "provider cards" do
    test "renders provider cards", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings/llm")

      # Check that provider cards are rendered
      assert html =~ "card"
      assert html =~ "LLM Provider Settings"
    end

    test "shows credential status badges", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings/llm")

      # Should show credential status badges
      assert html =~ "badge"
    end

    test "shows environment variable keys", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings/llm")

      # Should show API key environment variables
      assert html =~ "API_KEY"
    end
  end

  describe "credential configuration" do
    test "shows configure button", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings/llm")

      assert html =~ "Configure"
    end
  end

  describe "test connection functionality" do
    test "shows test connection button", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings/llm")

      assert html =~ "Test Connection"
    end
  end

  describe "provider discovery integration" do
    test "providers from Discovery are rendered", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings/llm")

      providers = Discovery.list_providers()

      # Verify at least some providers are rendered
      assert length(providers) > 0
      # Check that we have multiple cards
      assert String.split(html, "card") |> length() > 2
    end
  end

  describe "SecretRefs integration" do
    test "page loads without SecretRefs errors", %{conn: conn} do
      # This test verifies that SecretRefs integration doesn't cause crashes
      assert {:ok, _view, _html} = live(conn, ~p"/settings/llm")
    end
  end

  describe "backward compatibility" do
    test "LLM settings page renders successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings/llm")

      # Verify the page structure is maintained
      assert html =~ "LLM"
      assert html =~ "Settings"
    end
  end
end
