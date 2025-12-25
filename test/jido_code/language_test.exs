defmodule JidoCode.LanguageTest do
  use ExUnit.Case, async: true

  alias JidoCode.Language

  describe "detect/1" do
    setup do
      # Create a temporary directory for testing
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "language_test_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(test_dir)

      on_exit(fn ->
        File.rm_rf!(test_dir)
      end)

      {:ok, test_dir: test_dir}
    end

    test "detects elixir from mix.exs", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "mix.exs"), "defmodule MyApp do end")
      assert Language.detect(test_dir) == :elixir
    end

    test "detects javascript from package.json", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "package.json"), "{}")
      assert Language.detect(test_dir) == :javascript
    end

    test "detects typescript from tsconfig.json", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "tsconfig.json"), "{}")
      assert Language.detect(test_dir) == :typescript
    end

    test "detects rust from Cargo.toml", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "Cargo.toml"), "[package]")
      assert Language.detect(test_dir) == :rust
    end

    test "detects python from pyproject.toml", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "pyproject.toml"), "[project]")
      assert Language.detect(test_dir) == :python
    end

    test "detects python from requirements.txt", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "requirements.txt"), "flask==2.0")
      assert Language.detect(test_dir) == :python
    end

    test "detects go from go.mod", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "go.mod"), "module example.com/app")
      assert Language.detect(test_dir) == :go
    end

    test "detects ruby from Gemfile", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "Gemfile"), "source 'https://rubygems.org'")
      assert Language.detect(test_dir) == :ruby
    end

    test "detects java from pom.xml", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "pom.xml"), "<project></project>")
      assert Language.detect(test_dir) == :java
    end

    test "detects java from build.gradle", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "build.gradle"), "apply plugin: 'java'")
      assert Language.detect(test_dir) == :java
    end

    test "detects kotlin from build.gradle.kts", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "build.gradle.kts"), "plugins { kotlin(\"jvm\") }")
      assert Language.detect(test_dir) == :kotlin
    end

    test "detects php from composer.json", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "composer.json"), "{}")
      assert Language.detect(test_dir) == :php
    end

    test "detects cpp from CMakeLists.txt", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "CMakeLists.txt"), "cmake_minimum_required()")
      assert Language.detect(test_dir) == :cpp
    end

    test "detects csharp from .csproj files", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "MyApp.csproj"), "<Project></Project>")
      assert Language.detect(test_dir) == :csharp
    end

    test "detects c from Makefile with .c files", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "Makefile"), "all: main.o")
      File.write!(Path.join(test_dir, "main.c"), "int main() { return 0; }")
      assert Language.detect(test_dir) == :c
    end

    test "does not detect c if only Makefile (no .c files)", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "Makefile"), "all: main.o")
      # No .c files
      assert Language.detect(test_dir) == :elixir
    end

    test "does not detect c if only .c files (no Makefile)", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "main.c"), "int main() { return 0; }")
      # No Makefile
      assert Language.detect(test_dir) == :elixir
    end

    test "defaults to elixir when no marker file found", %{test_dir: test_dir} do
      assert Language.detect(test_dir) == :elixir
    end

    test "priority: mix.exs wins over package.json", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "mix.exs"), "")
      File.write!(Path.join(test_dir, "package.json"), "{}")
      assert Language.detect(test_dir) == :elixir
    end

    test "returns default for non-binary input" do
      assert Language.detect(nil) == :elixir
      assert Language.detect(123) == :elixir
    end
  end

  describe "default/0" do
    test "returns :elixir" do
      assert Language.default() == :elixir
    end
  end

  describe "valid?/1" do
    test "returns true for valid language atoms" do
      assert Language.valid?(:elixir) == true
      assert Language.valid?(:javascript) == true
      assert Language.valid?(:typescript) == true
      assert Language.valid?(:python) == true
      assert Language.valid?(:rust) == true
      assert Language.valid?(:go) == true
      assert Language.valid?(:ruby) == true
      assert Language.valid?(:java) == true
      assert Language.valid?(:kotlin) == true
      assert Language.valid?(:csharp) == true
      assert Language.valid?(:php) == true
      assert Language.valid?(:cpp) == true
      assert Language.valid?(:c) == true
    end

    test "returns false for invalid atoms" do
      assert Language.valid?(:invalid) == false
      assert Language.valid?(:haskell) == false
    end

    test "returns false for non-atoms" do
      assert Language.valid?("elixir") == false
      assert Language.valid?(123) == false
      assert Language.valid?(nil) == false
    end
  end

  describe "all_languages/0" do
    test "returns all supported languages" do
      languages = Language.all_languages()

      assert :elixir in languages
      assert :javascript in languages
      assert :typescript in languages
      assert :python in languages
      assert :rust in languages
      assert :go in languages
      assert :ruby in languages
      assert :java in languages
      assert :kotlin in languages
      assert :csharp in languages
      assert :php in languages
      assert :cpp in languages
      assert :c in languages
    end

    test "returns a list" do
      assert is_list(Language.all_languages())
    end
  end

  describe "normalize/1" do
    test "normalizes valid atom" do
      assert Language.normalize(:elixir) == {:ok, :elixir}
      assert Language.normalize(:python) == {:ok, :python}
    end

    test "normalizes valid string" do
      assert Language.normalize("elixir") == {:ok, :elixir}
      assert Language.normalize("python") == {:ok, :python}
    end

    test "normalizes with case insensitivity" do
      assert Language.normalize("ELIXIR") == {:ok, :elixir}
      assert Language.normalize("Python") == {:ok, :python}
    end

    test "normalizes common aliases" do
      assert Language.normalize("js") == {:ok, :javascript}
      assert Language.normalize("ts") == {:ok, :typescript}
      assert Language.normalize("py") == {:ok, :python}
      assert Language.normalize("rb") == {:ok, :ruby}
      assert Language.normalize("c++") == {:ok, :cpp}
      assert Language.normalize("c#") == {:ok, :csharp}
      assert Language.normalize("cs") == {:ok, :csharp}
    end

    test "trims whitespace" do
      assert Language.normalize("  elixir  ") == {:ok, :elixir}
    end

    test "returns error for invalid language" do
      assert Language.normalize(:invalid) == {:error, :invalid_language}
      assert Language.normalize("invalid") == {:error, :invalid_language}
    end

    test "returns error for non-string/atom input" do
      assert Language.normalize(123) == {:error, :invalid_language}
      assert Language.normalize(nil) == {:error, :invalid_language}
    end
  end

  describe "display_name/1" do
    test "returns human-readable names" do
      assert Language.display_name(:elixir) == "Elixir"
      assert Language.display_name(:javascript) == "JavaScript"
      assert Language.display_name(:typescript) == "TypeScript"
      assert Language.display_name(:rust) == "Rust"
      assert Language.display_name(:python) == "Python"
      assert Language.display_name(:go) == "Go"
      assert Language.display_name(:ruby) == "Ruby"
      assert Language.display_name(:java) == "Java"
      assert Language.display_name(:kotlin) == "Kotlin"
      assert Language.display_name(:csharp) == "C#"
      assert Language.display_name(:php) == "PHP"
      assert Language.display_name(:cpp) == "C++"
      assert Language.display_name(:c) == "C"
    end

    test "returns 'Unknown' for invalid language" do
      assert Language.display_name(:invalid) == "Unknown"
    end
  end

  describe "icon/1" do
    test "returns icons for languages" do
      assert Language.icon(:elixir) == "💧"
      assert Language.icon(:javascript) == "🟨"
      assert Language.icon(:typescript) == "🔷"
      assert Language.icon(:rust) == "🦀"
      assert Language.icon(:python) == "🐍"
      assert Language.icon(:go) == "🐹"
      assert Language.icon(:ruby) == "💎"
      assert Language.icon(:java) == "☕"
      assert Language.icon(:kotlin) == "🎯"
      assert Language.icon(:csharp) == "🟣"
      assert Language.icon(:php) == "🐘"
      assert Language.icon(:cpp) == "⚡"
      assert Language.icon(:c) == "🔧"
    end

    test "returns default icon for unknown language" do
      assert Language.icon(:unknown) == "📝"
    end
  end
end
