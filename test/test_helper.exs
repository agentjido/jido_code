# Compile test support modules
Code.require_file("support/env_isolation.ex", __DIR__)
Code.require_file("support/manager_isolation.ex", __DIR__)

# Exclude LLM integration tests by default
# Run with: mix test --include llm
ExUnit.start(exclude: [:llm])
