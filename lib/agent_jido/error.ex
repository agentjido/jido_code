defmodule AgentJido.Error do
  @moduledoc """
  Centralized error handling for AgentJido using Splode.

  Error classes are for classification; concrete `...Error` structs are for raising/matching.

  ## Error Classes

  - `:invalid` - Invalid input or validation errors
  - `:execution` - Runtime execution failures
  - `:config` - Configuration errors
  - `:internal` - Internal/unexpected errors

  ## Usage

      # Using helper functions
      AgentJido.Error.validation_error("Email is required", %{field: :email})
      AgentJido.Error.execution_error("Failed to process request", %{reason: :timeout})

      # Raising errors
      raise AgentJido.Error.InvalidInputError, message: "Invalid email format", field: :email
  """

  use Splode,
    error_classes: [
      invalid: Invalid,
      execution: Execution,
      config: Config,
      internal: Internal
    ],
    unknown_error: __MODULE__.Internal.UnknownError

  # Error classes – classification only
  defmodule Invalid do
    @moduledoc "Invalid input error class for Splode."
    use Splode.ErrorClass, class: :invalid
  end

  defmodule Execution do
    @moduledoc "Execution error class for Splode."
    use Splode.ErrorClass, class: :execution
  end

  defmodule Config do
    @moduledoc "Configuration error class for Splode."
    use Splode.ErrorClass, class: :config
  end

  defmodule Internal do
    @moduledoc "Internal error class for Splode."
    use Splode.ErrorClass, class: :internal

    defmodule UnknownError do
      @moduledoc "Unknown/unexpected error."
      use Splode.Error, class: :internal

      def message(%{error: error}) do
        "Unknown error: #{inspect(error)}"
      end
    end
  end

  # Concrete exception structs – raise/rescue these
  defmodule InvalidInputError do
    @moduledoc "Error for invalid input parameters."
    use Splode.Error, class: :invalid

    @type t :: %__MODULE__{}

    def message(%{message: message}), do: message
  end

  defmodule ValidationError do
    @moduledoc "Error for validation failures."
    use Splode.Error, class: :invalid

    @type t :: %__MODULE__{}

    def message(%{message: message, field: field}) when not is_nil(field) do
      "Validation failed for #{field}: #{message}"
    end

    def message(%{message: message}), do: message
  end

  defmodule ExecutionFailureError do
    @moduledoc "Error for runtime execution failures."
    use Splode.Error, class: :execution

    @type t :: %__MODULE__{}

    def message(%{message: message}), do: message
  end

  defmodule ConfigurationError do
    @moduledoc "Error for configuration issues."
    use Splode.Error, class: :config

    @type t :: %__MODULE__{}

    def message(%{message: message}), do: message
  end

  # Helper functions

  @doc "Creates a validation error with optional details."
  @spec validation_error(String.t(), map() | keyword()) :: ValidationError.t()
  def validation_error(message, details \\ %{}) do
    ValidationError.exception(merge_error_details(message, details))
  end

  @doc "Creates an invalid input error."
  @spec invalid_input_error(String.t(), map() | keyword()) :: InvalidInputError.t()
  def invalid_input_error(message, details \\ %{}) do
    InvalidInputError.exception(merge_error_details(message, details))
  end

  @doc "Creates an execution failure error."
  @spec execution_error(String.t(), map() | keyword()) :: ExecutionFailureError.t()
  def execution_error(message, details \\ %{}) do
    ExecutionFailureError.exception(merge_error_details(message, details))
  end

  @doc "Creates a configuration error."
  @spec config_error(String.t(), map() | keyword()) :: ConfigurationError.t()
  def config_error(message, details \\ %{}) do
    ConfigurationError.exception(merge_error_details(message, details))
  end

  defp merge_error_details(message, details) when is_list(details) do
    Keyword.merge([message: message], details)
  end

  defp merge_error_details(message, details) when is_map(details) do
    Keyword.merge([message: message], Map.to_list(details))
  end

  defp merge_error_details(message, nil) do
    [message: message]
  end
end
