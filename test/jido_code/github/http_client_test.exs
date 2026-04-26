defmodule JidoCode.GitHub.HTTPClientTest do
  # covers: source.provider_adapter.github_repository_listing_fetches_full_accessible_set
  use ExUnit.Case, async: true

  alias JidoCode.GitHub.HTTPClient

  test "list_accessible_repositories/3 uses explicit Req timeout and retry options" do
    request_fun = fn request_opts ->
      send(self(), {:request_opts, request_opts})

      {:ok,
       %Req.Response{
         status: 200,
         body: [
           %{"id" => 42, "full_name" => "owner/repo-one"}
         ]
       }}
    end

    assert {:ok, repositories} =
             HTTPClient.list_accessible_repositories(
               :pat,
               "ghp_test_token",
               request_fun: request_fun,
               connect_timeout_ms: 1_234,
               receive_timeout_ms: 5_678,
               max_retries: 4,
               retry_base_delay_ms: 25
             )

    assert repositories == [
             %{
               id: "42",
               full_name: "owner/repo-one",
               owner: "owner",
               name: "repo-one"
             }
           ]

    assert_receive {:request_opts, request_opts}

    assert request_opts[:connect_options] == [timeout: 1_234]
    assert request_opts[:receive_timeout] == 5_678
    assert request_opts[:max_retries] == 4
    assert is_function(request_opts[:retry], 2)
    assert is_function(request_opts[:retry_delay], 1)
    assert request_opts[:retry_log_level] == false
  end

  test "list_accessible_repositories/3 maps authentication failures to typed reasons" do
    request_fun = fn _request_opts ->
      {:ok, %Req.Response{status: 401, body: %{"message" => "Bad credentials"}}}
    end

    assert {:error, failure} =
             HTTPClient.list_accessible_repositories(
               :pat,
               "ghp_test_token",
               request_fun: request_fun
             )

    assert failure.error_type == "github_api_authentication_failed"
    assert failure.reason_type == :authentication
    assert failure.request_intent == "github_pat_repository_listing"
    assert failure.detail =~ "Bad credentials"
  end

  test "list_accessible_repositories/3 preserves request intent and remediation when retries exhaust" do
    request_fun = fn _request_opts ->
      {:ok, %Req.Response{status: 503, body: %{"message" => "Service unavailable"}}}
    end

    assert {:error, failure} =
             HTTPClient.list_accessible_repositories(
               :pat,
               "ghp_test_token",
               request_fun: request_fun,
               max_retries: 3
             )

    assert failure.error_type == "github_api_retry_exhausted"
    assert failure.reason_type == :retry_exhausted
    assert failure.request_intent == "github_pat_repository_listing"
    assert failure.remediation =~ "Retry request intent `github_pat_repository_listing`"
    assert failure.detail =~ "exhausted retries"
    assert failure.status == 503
    assert failure.attempt_count == 4
    assert failure.max_retries == 3
  end

  test "list_accessible_repositories/3 paginates PAT listings beyond the default first page" do
    page_one =
      Enum.map(1..100, fn index ->
        %{"id" => index, "full_name" => "owner/repo-#{index}"}
      end)

    page_two = [
      %{"id" => 101, "full_name" => "owner/repo-101"},
      %{"id" => 102, "full_name" => "owner/repo-102"}
    ]

    request_fun = fn request_opts ->
      send(self(), {:request_opts, request_opts[:params]})

      case Keyword.get(request_opts[:params], :page) do
        1 -> {:ok, %Req.Response{status: 200, body: page_one}}
        2 -> {:ok, %Req.Response{status: 200, body: page_two}}
        3 -> {:ok, %Req.Response{status: 200, body: []}}
      end
    end

    assert {:ok, repositories} =
             HTTPClient.list_accessible_repositories(
               :pat,
               "ghp_test_token",
               request_fun: request_fun
             )

    assert length(repositories) == 102
    assert Enum.any?(repositories, &(&1.full_name == "owner/repo-1"))
    assert Enum.any?(repositories, &(&1.full_name == "owner/repo-101"))
    assert Enum.any?(repositories, &(&1.full_name == "owner/repo-102"))

    assert_receive {:request_opts, [page: 1, per_page: 100]}
    assert_receive {:request_opts, [page: 2, per_page: 100]}
  end
end
