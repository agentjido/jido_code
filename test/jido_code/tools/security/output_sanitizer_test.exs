defmodule JidoCode.Tools.Security.OutputSanitizerTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.Security.OutputSanitizer

  # =============================================================================
  # Tests: sanitize/2 - String patterns
  # =============================================================================

  describe "sanitize/2 with strings" do
    test "redacts password assignments" do
      # The entire key=value pattern is replaced with [REDACTED]
      assert OutputSanitizer.sanitize("password=secret123") == "[REDACTED]"
      assert OutputSanitizer.sanitize("password: mysecret") == "[REDACTED]"
      assert OutputSanitizer.sanitize("PASSWORD=SECRET") == "[REDACTED]"
    end

    test "redacts secret assignments" do
      assert OutputSanitizer.sanitize("secret=abc123") == "[REDACTED]"
      assert OutputSanitizer.sanitize("SECRET: xyz") == "[REDACTED]"
    end

    test "redacts api_key assignments" do
      assert OutputSanitizer.sanitize("api_key=myapikey") == "[REDACTED]"
      assert OutputSanitizer.sanitize("apikey: 12345") == "[REDACTED]"
      assert OutputSanitizer.sanitize("API_KEY=ABCDEF") == "[REDACTED]"
    end

    test "redacts token assignments" do
      assert OutputSanitizer.sanitize("token=abc123def") == "[REDACTED]"
      assert OutputSanitizer.sanitize("TOKEN: secret") == "[REDACTED]"
    end

    test "redacts bearer tokens" do
      assert OutputSanitizer.sanitize("Authorization: bearer abc123.xyz.789") ==
               "Authorization: [REDACTED_BEARER]"

      assert OutputSanitizer.sanitize("Bearer eyJhbGciOiJIUzI1NiJ9") ==
               "[REDACTED_BEARER]"
    end

    test "redacts OpenAI API keys" do
      assert OutputSanitizer.sanitize("sk-abcdefghijklmnopqrstuvwxyz123456789012345678") ==
               "[REDACTED_API_KEY]"

      assert OutputSanitizer.sanitize("My key is sk-1234567890abcdefghijklmnopqrstuvwxyz") ==
               "My key is [REDACTED_API_KEY]"
    end

    test "redacts GitHub personal access tokens" do
      assert OutputSanitizer.sanitize("ghp_abcdefghijklmnopqrstuvwxyz1234567890") ==
               "[REDACTED_GITHUB_TOKEN]"
    end

    test "redacts GitHub OAuth tokens" do
      assert OutputSanitizer.sanitize("gho_abcdefghijklmnopqrstuvwxyz1234567890") ==
               "[REDACTED_GITHUB_TOKEN]"
    end

    test "redacts AWS access keys" do
      assert OutputSanitizer.sanitize("AKIAIOSFODNN7EXAMPLE") == "[REDACTED_AWS_KEY]"

      # Access key ID in a value assignment is also redacted
      result = OutputSanitizer.sanitize("aws_access_key_id: AKIAIOSFODNN7EXAMPLE")
      assert result =~ "[REDACTED"
      refute result =~ "AKIAIOSFODNN7EXAMPLE"
    end

    test "redacts AWS secret access keys" do
      secret = "aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
      assert OutputSanitizer.sanitize(secret) == "[REDACTED_AWS_SECRET]"
    end

    test "redacts Slack tokens" do
      assert OutputSanitizer.sanitize("xoxb-1234567890-abcdefghij") ==
               "[REDACTED_SLACK_TOKEN]"

      assert OutputSanitizer.sanitize("xoxp-token-here") == "[REDACTED_SLACK_TOKEN]"
    end

    test "redacts Anthropic API keys" do
      assert OutputSanitizer.sanitize("sk-ant-api03-abcdef123456") ==
               "[REDACTED_ANTHROPIC_KEY]"
    end

    test "preserves non-sensitive strings" do
      assert OutputSanitizer.sanitize("hello world") == "hello world"
      assert OutputSanitizer.sanitize("username=alice") == "username=alice"
      assert OutputSanitizer.sanitize("count: 42") == "count: 42"
    end

    test "handles empty strings" do
      assert OutputSanitizer.sanitize("") == ""
    end

    test "handles multiple sensitive patterns in one string" do
      input = "password=secret123 and token=abc456"
      result = OutputSanitizer.sanitize(input)
      assert result =~ "[REDACTED]"
      refute result =~ "secret123"
      refute result =~ "abc456"
    end
  end

  # =============================================================================
  # Tests: sanitize/2 - Map sanitization
  # =============================================================================

  describe "sanitize/2 with maps" do
    test "redacts password field (atom key)" do
      assert OutputSanitizer.sanitize(%{password: "secret123"}) ==
               %{password: "[REDACTED]"}
    end

    test "redacts password field (string key)" do
      assert OutputSanitizer.sanitize(%{"password" => "secret123"}) ==
               %{"password" => "[REDACTED]"}
    end

    test "redacts multiple sensitive fields" do
      input = %{
        username: "alice",
        password: "secret",
        api_key: "key123",
        token: "tok456"
      }

      result = OutputSanitizer.sanitize(input)

      assert result.username == "alice"
      assert result.password == "[REDACTED]"
      assert result.api_key == "[REDACTED]"
      assert result.token == "[REDACTED]"
    end

    test "redacts secret field" do
      assert OutputSanitizer.sanitize(%{secret: "mysecret"}) == %{secret: "[REDACTED]"}
    end

    test "redacts api_key field" do
      assert OutputSanitizer.sanitize(%{api_key: "key123"}) == %{api_key: "[REDACTED]"}
      assert OutputSanitizer.sanitize(%{apikey: "key123"}) == %{apikey: "[REDACTED]"}
    end

    test "redacts token fields" do
      assert OutputSanitizer.sanitize(%{token: "tok"}) == %{token: "[REDACTED]"}
      assert OutputSanitizer.sanitize(%{access_token: "tok"}) == %{access_token: "[REDACTED]"}
      assert OutputSanitizer.sanitize(%{refresh_token: "tok"}) == %{refresh_token: "[REDACTED]"}
    end

    test "redacts auth fields" do
      assert OutputSanitizer.sanitize(%{auth: "value"}) == %{auth: "[REDACTED]"}
      assert OutputSanitizer.sanitize(%{authorization: "value"}) == %{authorization: "[REDACTED]"}
      assert OutputSanitizer.sanitize(%{credentials: "value"}) == %{credentials: "[REDACTED]"}
    end

    test "redacts private_key field" do
      assert OutputSanitizer.sanitize(%{private_key: "-----BEGIN RSA-----"}) ==
               %{private_key: "[REDACTED]"}
    end

    test "redacts AWS credential fields" do
      input = %{
        aws_access_key_id: "AKIAIOSFODNN7EXAMPLE",
        aws_secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
      }

      result = OutputSanitizer.sanitize(input)

      assert result.aws_access_key_id == "[REDACTED]"
      assert result.aws_secret_access_key == "[REDACTED]"
    end

    test "preserves non-sensitive map fields" do
      input = %{username: "alice", email: "alice@example.com", count: 42}
      assert OutputSanitizer.sanitize(input) == input
    end

    test "handles empty maps" do
      assert OutputSanitizer.sanitize(%{}) == %{}
    end

    test "recursively sanitizes nested maps" do
      # Use non-sensitive parent key 'config' instead of 'credentials'
      input = %{
        user: %{
          name: "alice",
          config: %{
            password: "secret",
            api_key: "key123"
          }
        }
      }

      result = OutputSanitizer.sanitize(input)

      assert result.user.name == "alice"
      assert result.user.config.password == "[REDACTED]"
      assert result.user.config.api_key == "[REDACTED]"
    end

    test "sanitizes string values within maps" do
      input = %{
        config: "password=secret123",
        env: "API_KEY=mykey"
      }

      result = OutputSanitizer.sanitize(input)

      assert result.config =~ "[REDACTED]"
      refute result.config =~ "secret123"
    end
  end

  # =============================================================================
  # Tests: sanitize/2 - List sanitization
  # =============================================================================

  describe "sanitize/2 with lists" do
    test "sanitizes strings in lists" do
      input = ["normal", "password=secret", "more text"]
      result = OutputSanitizer.sanitize(input)

      assert Enum.at(result, 0) == "normal"
      assert Enum.at(result, 1) =~ "[REDACTED]"
      assert Enum.at(result, 2) == "more text"
    end

    test "sanitizes maps in lists" do
      input = [
        %{username: "alice", password: "secret1"},
        %{username: "bob", password: "secret2"}
      ]

      result = OutputSanitizer.sanitize(input)

      assert Enum.at(result, 0).password == "[REDACTED]"
      assert Enum.at(result, 1).password == "[REDACTED]"
    end

    test "handles empty lists" do
      assert OutputSanitizer.sanitize([]) == []
    end

    test "handles mixed lists" do
      input = [42, "password=secret", %{token: "abc"}, :atom]
      result = OutputSanitizer.sanitize(input)

      assert Enum.at(result, 0) == 42
      assert Enum.at(result, 1) =~ "[REDACTED]"
      assert Enum.at(result, 2).token == "[REDACTED]"
      assert Enum.at(result, 3) == :atom
    end

    test "handles nested lists" do
      input = [["password=secret"], [%{api_key: "key"}]]
      result = OutputSanitizer.sanitize(input)

      assert hd(hd(result)) =~ "[REDACTED]"
      assert hd(Enum.at(result, 1)).api_key == "[REDACTED]"
    end
  end

  # =============================================================================
  # Tests: sanitize/2 - Tuple handling
  # =============================================================================

  describe "sanitize/2 with tuples" do
    test "sanitizes {:ok, value} tuples" do
      # The entire key=value pattern is replaced
      assert OutputSanitizer.sanitize({:ok, "password=secret"}) ==
               {:ok, "[REDACTED]"}
    end

    test "sanitizes {:error, value} tuples" do
      # The entire key=value pattern is replaced
      assert OutputSanitizer.sanitize({:error, "api_key=abc123"}) ==
               {:error, "[REDACTED]"}
    end

    test "sanitizes nested values in tuples" do
      input = {:ok, %{password: "secret", data: "normal"}}
      result = OutputSanitizer.sanitize(input)

      assert {:ok, sanitized_map} = result
      assert sanitized_map.password == "[REDACTED]"
      assert sanitized_map.data == "normal"
    end
  end

  # =============================================================================
  # Tests: sanitize/2 - Other types
  # =============================================================================

  describe "sanitize/2 with other types" do
    test "passes through integers" do
      assert OutputSanitizer.sanitize(42) == 42
    end

    test "passes through floats" do
      assert OutputSanitizer.sanitize(3.14) == 3.14
    end

    test "passes through atoms" do
      assert OutputSanitizer.sanitize(:ok) == :ok
      assert OutputSanitizer.sanitize(:password) == :password
    end

    test "passes through nil" do
      assert OutputSanitizer.sanitize(nil) == nil
    end

    test "passes through booleans" do
      assert OutputSanitizer.sanitize(true) == true
      assert OutputSanitizer.sanitize(false) == false
    end
  end

  # =============================================================================
  # Tests: contains_sensitive?/1
  # =============================================================================

  describe "contains_sensitive?/1" do
    test "returns true for strings with sensitive patterns" do
      assert OutputSanitizer.contains_sensitive?("password=secret")
      assert OutputSanitizer.contains_sensitive?("bearer abc123")
      assert OutputSanitizer.contains_sensitive?("sk-1234567890abcdefghijklmnopqrstuvwxyz")
    end

    test "returns false for strings without sensitive patterns" do
      refute OutputSanitizer.contains_sensitive?("hello world")
      refute OutputSanitizer.contains_sensitive?("username=alice")
    end

    test "returns true for maps with sensitive fields" do
      assert OutputSanitizer.contains_sensitive?(%{password: "secret"})
      assert OutputSanitizer.contains_sensitive?(%{api_key: "key"})
    end

    test "returns true for maps with nested sensitive content" do
      assert OutputSanitizer.contains_sensitive?(%{user: %{password: "secret"}})
      assert OutputSanitizer.contains_sensitive?(%{data: "token=abc"})
    end

    test "returns false for maps without sensitive content" do
      refute OutputSanitizer.contains_sensitive?(%{username: "alice"})
      refute OutputSanitizer.contains_sensitive?(%{count: 42})
    end

    test "returns true for lists with sensitive content" do
      assert OutputSanitizer.contains_sensitive?(["password=secret"])
      assert OutputSanitizer.contains_sensitive?([%{token: "abc"}])
    end

    test "returns false for lists without sensitive content" do
      refute OutputSanitizer.contains_sensitive?(["hello", "world"])
      refute OutputSanitizer.contains_sensitive?([1, 2, 3])
    end

    test "returns false for other types" do
      refute OutputSanitizer.contains_sensitive?(42)
      refute OutputSanitizer.contains_sensitive?(:atom)
      refute OutputSanitizer.contains_sensitive?(nil)
    end
  end

  # =============================================================================
  # Tests: sensitive_patterns/0
  # =============================================================================

  describe "sensitive_patterns/0" do
    test "returns a list of pattern tuples" do
      patterns = OutputSanitizer.sensitive_patterns()

      assert is_list(patterns)
      assert length(patterns) > 0

      Enum.each(patterns, fn {pattern, replacement} ->
        assert %Regex{} = pattern
        assert is_binary(replacement)
      end)
    end
  end

  # =============================================================================
  # Tests: sensitive_fields/0
  # =============================================================================

  describe "sensitive_fields/0" do
    test "returns a MapSet of field names" do
      fields = OutputSanitizer.sensitive_fields()

      assert %MapSet{} = fields
      assert MapSet.member?(fields, :password)
      assert MapSet.member?(fields, "password")
      assert MapSet.member?(fields, :api_key)
      assert MapSet.member?(fields, :token)
    end
  end

  # =============================================================================
  # Tests: Telemetry emission
  # =============================================================================

  describe "telemetry emission" do
    test "emits telemetry on string sanitization" do
      ref = make_ref()
      test_pid = self()
      handler_id = "test-output-sanitizer-string-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :security, :output_sanitized],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      try do
        OutputSanitizer.sanitize("password=secret")

        assert_receive {:telemetry, ^ref, [:jido_code, :security, :output_sanitized], measurements,
                        metadata}

        assert measurements.redaction_count >= 1
        assert metadata.type == :string
      after
        :telemetry.detach(handler_id)
      end
    end

    test "emits telemetry on map field sanitization" do
      ref = make_ref()
      test_pid = self()
      handler_id = "test-output-sanitizer-map-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :security, :output_sanitized],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      try do
        OutputSanitizer.sanitize(%{password: "secret"})

        assert_receive {:telemetry, ^ref, [:jido_code, :security, :output_sanitized], measurements,
                        metadata}

        assert measurements.redaction_count >= 1
        assert metadata.type == :map
      after
        :telemetry.detach(handler_id)
      end
    end

    test "does not emit telemetry when no redaction occurs" do
      ref = make_ref()
      test_pid = self()
      handler_id = "test-output-sanitizer-no-redact-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :security, :output_sanitized],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      try do
        OutputSanitizer.sanitize("hello world")
        OutputSanitizer.sanitize(%{username: "alice"})

        refute_receive {:telemetry, ^ref, _, _, _}, 100
      after
        :telemetry.detach(handler_id)
      end
    end

    test "does not emit telemetry when emit_telemetry: false" do
      ref = make_ref()
      test_pid = self()
      handler_id = "test-output-sanitizer-disabled-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :security, :output_sanitized],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      try do
        OutputSanitizer.sanitize("password=secret", emit_telemetry: false)

        refute_receive {:telemetry, ^ref, _, _, _}, 100
      after
        :telemetry.detach(handler_id)
      end
    end

    test "includes context in telemetry metadata" do
      ref = make_ref()
      test_pid = self()
      handler_id = "test-output-sanitizer-context-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :security, :output_sanitized],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, metadata})
        end,
        nil
      )

      try do
        OutputSanitizer.sanitize("password=secret", context: %{tool: "read_file"})

        assert_receive {:telemetry, ^ref, metadata}
        assert metadata.tool == "read_file"
      after
        :telemetry.detach(handler_id)
      end
    end
  end

  # =============================================================================
  # Tests: Edge cases and complex scenarios
  # =============================================================================

  describe "edge cases" do
    test "handles deeply nested structures" do
      input = %{
        level1: %{
          level2: %{
            level3: %{
              password: "deep_secret"
            }
          }
        }
      }

      result = OutputSanitizer.sanitize(input)

      assert result.level1.level2.level3.password == "[REDACTED]"
    end

    test "handles mixed nesting of lists and maps" do
      # Use non-sensitive parent keys - 'settings' instead of 'credentials'
      input = %{
        users: [
          %{name: "alice", settings: %{password: "pass1", theme: "dark"}},
          %{name: "bob", settings: %{password: "pass2", theme: "light"}}
        ]
      }

      result = OutputSanitizer.sanitize(input)

      assert Enum.at(result.users, 0).settings.password == "[REDACTED]"
      assert Enum.at(result.users, 0).settings.theme == "dark"
      assert Enum.at(result.users, 1).settings.password == "[REDACTED]"
      assert Enum.at(result.users, 1).settings.theme == "light"
    end

    test "handles large strings efficiently" do
      # Create a large string with a sensitive pattern embedded
      large_prefix = String.duplicate("x", 10_000)
      large_suffix = String.duplicate("y", 10_000)
      input = large_prefix <> "password=secret" <> large_suffix

      result = OutputSanitizer.sanitize(input)

      refute result =~ "secret"
      assert result =~ "[REDACTED]"
    end

    test "handles unicode content" do
      input = "密码: パスワード password=секрет"
      result = OutputSanitizer.sanitize(input)

      assert result =~ "[REDACTED]"
      assert result =~ "密码"
      assert result =~ "パスワード"
    end

    test "handles special regex characters in values" do
      # This shouldn't crash or misbehave with regex special chars
      input = %{data: "text with (parens) [brackets] {braces}"}
      result = OutputSanitizer.sanitize(input)
      assert result.data =~ "parens"
    end
  end
end
