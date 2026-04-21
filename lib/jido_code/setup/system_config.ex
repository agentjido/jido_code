defmodule JidoCode.Setup.SystemConfig do
  # covers: setup.runtime_environment_defaults.selection_persisted_in_database_backed_system_config
  # covers: setup.onboarding.runtime_environment_selection_persisted_metadata
  @moduledoc """
  Onboarding state loader and progress persistence for setup routing.
  """

  @enforce_keys [
    :onboarding_completed,
    :onboarding_step,
    :onboarding_state,
    :default_environment,
    :workspace_root
  ]
  defstruct onboarding_completed: false,
            onboarding_step: 1,
            onboarding_state: %{},
            default_environment: :sprite,
            workspace_root: nil

  @type onboarding_state :: %{optional(String.t()) => map()}

  @type t :: %__MODULE__{
          onboarding_completed: boolean(),
          onboarding_step: pos_integer(),
          onboarding_state: onboarding_state(),
          default_environment: :sprite | :local,
          workspace_root: String.t() | nil
        }

  @type load_error :: %{
          diagnostic: String.t(),
          detail: term(),
          onboarding_step: pos_integer()
        }

  @type save_error :: %{
          diagnostic: String.t(),
          detail: term(),
          onboarding_step: pos_integer()
        }

  @spec load() :: {:ok, t()} | {:error, load_error()}
  def load do
    with {:ok, raw_config} <- run_loader(),
         {:ok, config} <- normalize_config(raw_config) do
      {:ok, config}
    else
      {:error, reason} -> {:error, load_error(reason)}
    end
  end

  @spec save_step_progress(map()) :: {:ok, t()} | {:error, save_error()}
  @spec save_step_progress(map(), map()) :: {:ok, t()} | {:error, save_error()}
  def save_step_progress(validated_state, config_updates \\ %{})

  def save_step_progress(validated_state, config_updates)
      when is_map(validated_state) and is_map(config_updates) do
    case load() do
      {:ok, %__MODULE__{} = config} ->
        current_step = config.onboarding_step

        with {:ok, normalized_updates} <- normalize_config_updates(config_updates) do
          %__MODULE__{} = updated_config = apply_config_updates(config, normalized_updates)

          updated_config =
            %{updated_config | onboarding_step: current_step + 1}

          updated_config =
            %{
              updated_config
              | onboarding_state:
                  Map.put(
                    config.onboarding_state,
                    Integer.to_string(current_step),
                    validated_state
                  )
            }

          case persist_config(updated_config) do
            {:ok, persisted_config} ->
              {:ok, persisted_config}

            {:error, reason} ->
              {:error, save_error(reason, current_step)}
          end
        else
          {:error, reason} ->
            {:error, save_error(reason, current_step)}
        end

      {:error, reason} ->
        {:error, save_error({:load_failed, reason}, onboarding_step_from_reason(reason))}
    end
  end

  def save_step_progress(_validated_state, _config_updates),
    do: {:error, save_error(:invalid_step_state, 1)}

  @spec update((t() -> t() | {:ok, t()} | {:error, term()})) :: {:ok, t()} | {:error, save_error()}
  def update(updater) when is_function(updater, 1) do
    case load() do
      {:ok, %__MODULE__{} = config} ->
        with {:ok, updated_config} <- apply_config_update(updater, config),
             {:ok, persisted_config} <- persist_config(updated_config) do
          {:ok, persisted_config}
        else
          {:error, reason} ->
            {:error, save_error(reason, config.onboarding_step)}
        end

      {:error, reason} ->
        {:error, save_error({:load_failed, reason}, onboarding_step_from_reason(reason))}
    end
  end

  def update(_updater), do: {:error, save_error(:invalid_config_updater, 1)}

  @spec update_onboarding_state((onboarding_state() ->
                                   onboarding_state() | {:ok, onboarding_state()} | {:error, term()})) ::
          {:ok, t()} | {:error, save_error()}
  def update_onboarding_state(updater) when is_function(updater, 1) do
    case load() do
      {:ok, %__MODULE__{} = config} ->
        with {:ok, updated_onboarding_state} <-
               apply_onboarding_state_update(updater, config.onboarding_state),
             {:ok, persisted_config} <-
               persist_config(%__MODULE__{config | onboarding_state: updated_onboarding_state}) do
          {:ok, persisted_config}
        else
          {:error, reason} ->
            {:error, save_error(reason, config.onboarding_step)}
        end

      {:error, reason} ->
        {:error, save_error({:load_failed, reason}, onboarding_step_from_reason(reason))}
    end
  end

  def update_onboarding_state(_updater),
    do: {:error, save_error(:invalid_onboarding_state_updater, 1)}

  @doc false
  def default_loader do
    {:ok, Application.get_env(:jido_code, :system_config, %{})}
  end

  @doc false
  def default_saver(%__MODULE__{} = config) do
    persisted_config = %{
      onboarding_completed: config.onboarding_completed,
      onboarding_step: config.onboarding_step,
      onboarding_state: config.onboarding_state,
      default_environment: config.default_environment,
      workspace_root: config.workspace_root
    }

    Application.put_env(:jido_code, :system_config, persisted_config)

    {:ok, persisted_config}
  end

  defp run_loader do
    loader = Application.get_env(:jido_code, :system_config_loader, &__MODULE__.default_loader/0)

    if is_function(loader, 0) do
      safe_invoke_loader(loader)
    else
      {:error, :invalid_loader}
    end
  end

  defp run_saver(config) do
    saver = Application.get_env(:jido_code, :system_config_saver, &__MODULE__.default_saver/1)

    if is_function(saver, 1) do
      safe_invoke_saver(saver, config)
    else
      {:error, :invalid_saver}
    end
  end

  defp safe_invoke_loader(loader) do
    try do
      case loader.() do
        {:ok, _config} = result ->
          result

        {:error, _reason} = result ->
          result

        other ->
          {:error, {:invalid_loader_result, other}}
      end
    rescue
      exception ->
        {:error, {:loader_exception, Exception.message(exception)}}
    catch
      kind, reason ->
        {:error, {:loader_throw, {kind, reason}}}
    end
  end

  defp safe_invoke_saver(saver, config) do
    try do
      case saver.(config) do
        {:ok, _config} = result ->
          result

        {:error, _reason} = result ->
          result

        other ->
          {:error, {:invalid_saver_result, other}}
      end
    rescue
      exception ->
        {:error, {:saver_exception, Exception.message(exception)}}
    catch
      kind, reason ->
        {:error, {:saver_throw, {kind, reason}}}
    end
  end

  defp normalize_config(%__MODULE__{} = config), do: validate_config(config)

  defp normalize_config(config) when is_map(config) do
    validate_config(%__MODULE__{
      onboarding_completed: map_get(config, :onboarding_completed, "onboarding_completed", false),
      onboarding_step: map_get(config, :onboarding_step, "onboarding_step", 1),
      onboarding_state: map_get(config, :onboarding_state, "onboarding_state", %{}),
      default_environment:
        config
        |> map_get(:default_environment, "default_environment", :sprite)
        |> normalize_default_environment(:sprite),
      workspace_root:
        config
        |> map_get(:workspace_root, "workspace_root", nil)
        |> normalize_workspace_root()
    })
  end

  defp normalize_config(other), do: {:error, {:invalid_config, other}}

  defp validate_config(
         %__MODULE__{
           onboarding_completed: completed,
           onboarding_step: step,
           onboarding_state: onboarding_state,
           default_environment: default_environment,
           workspace_root: workspace_root
         } = config
       )
       when is_boolean(completed) and is_integer(step) and step > 0 and is_map(onboarding_state) do
    if valid_default_environment?(default_environment) and
         valid_workspace_root?(default_environment, workspace_root) do
      {:ok, config}
    else
      {:error, {:invalid_config, config}}
    end
  end

  defp validate_config(%__MODULE__{} = config), do: {:error, {:invalid_config, config}}

  defp persist_config(%__MODULE__{} = config) do
    with {:ok, raw_config} <- run_saver(config),
         {:ok, normalized_config} <- normalize_config(raw_config) do
      {:ok, normalized_config}
    end
  end

  defp apply_config_updates(%__MODULE__{} = config, updates) when map_size(updates) == 0,
    do: config

  defp apply_config_updates(%__MODULE__{} = config, updates) do
    onboarding_completed = Map.get(updates, :onboarding_completed, config.onboarding_completed)
    default_environment = Map.get(updates, :default_environment, config.default_environment)
    workspace_root = Map.get(updates, :workspace_root, config.workspace_root)

    %__MODULE__{
      config
      | onboarding_completed: onboarding_completed,
        default_environment: default_environment,
        workspace_root: normalize_workspace_root_for_environment(default_environment, workspace_root)
    }
  end

  defp normalize_config_updates(config_updates) when is_map(config_updates) do
    with {:ok, onboarding_completed} <-
           normalize_onboarding_completed_update(
             map_get(config_updates, :onboarding_completed, "onboarding_completed", :__not_set__)
           ),
         {:ok, default_environment} <-
           normalize_default_environment_update(
             map_get(config_updates, :default_environment, "default_environment", :__not_set__)
           ),
         {:ok, workspace_root} <-
           normalize_workspace_root_update(map_get(config_updates, :workspace_root, "workspace_root", :__not_set__)) do
      {:ok,
       %{}
       |> maybe_put(:onboarding_completed, onboarding_completed)
       |> maybe_put(:default_environment, default_environment)
       |> maybe_put(:workspace_root, workspace_root)}
    end
  end

  defp normalize_config_updates(_config_updates), do: {:error, :invalid_config_updates}

  defp apply_onboarding_state_update(updater, onboarding_state) when is_function(updater, 1) do
    try do
      case updater.(onboarding_state) do
        %{} = updated_onboarding_state ->
          {:ok, updated_onboarding_state}

        {:ok, %{} = updated_onboarding_state} ->
          {:ok, updated_onboarding_state}

        {:error, reason} ->
          {:error, reason}

        other ->
          {:error, {:invalid_onboarding_state_update, other}}
      end
    rescue
      exception ->
        {:error, {:onboarding_state_update_exception, Exception.message(exception)}}
    catch
      kind, reason ->
        {:error, {:onboarding_state_update_throw, {kind, reason}}}
    end
  end

  defp apply_config_update(updater, %__MODULE__{} = config) when is_function(updater, 1) do
    try do
      case updater.(config) do
        %__MODULE__{} = updated_config ->
          validate_config(updated_config)

        {:ok, %__MODULE__{} = updated_config} ->
          validate_config(updated_config)

        {:error, reason} ->
          {:error, reason}

        other ->
          {:error, {:invalid_config_update, other}}
      end
    rescue
      exception ->
        {:error, {:config_update_exception, Exception.message(exception)}}
    catch
      kind, reason ->
        {:error, {:config_update_throw, {kind, reason}}}
    end
  end

  defp normalize_onboarding_completed_update(:__not_set__), do: {:ok, :__not_set__}

  defp normalize_onboarding_completed_update(onboarding_completed)
       when is_boolean(onboarding_completed),
       do: {:ok, onboarding_completed}

  defp normalize_onboarding_completed_update(_onboarding_completed),
    do: {:error, :invalid_onboarding_completed}

  defp normalize_default_environment_update(:__not_set__), do: {:ok, :__not_set__}
  defp normalize_default_environment_update(:sprite), do: {:ok, :sprite}
  defp normalize_default_environment_update(:local), do: {:ok, :local}
  defp normalize_default_environment_update("sprite"), do: {:ok, :sprite}
  defp normalize_default_environment_update("local"), do: {:ok, :local}

  defp normalize_default_environment_update(_default_environment),
    do: {:error, :invalid_default_environment}

  defp normalize_workspace_root_update(:__not_set__), do: {:ok, :__not_set__}
  defp normalize_workspace_root_update(nil), do: {:ok, nil}

  defp normalize_workspace_root_update(workspace_root) when is_binary(workspace_root) do
    workspace_root
    |> String.trim()
    |> case do
      "" -> {:ok, nil}
      normalized_workspace_root -> {:ok, normalized_workspace_root}
    end
  end

  defp normalize_workspace_root_update(_workspace_root), do: {:error, :invalid_workspace_root}

  defp normalize_workspace_root_for_environment(:sprite, _workspace_root), do: nil
  defp normalize_workspace_root_for_environment(:local, workspace_root), do: workspace_root

  defp normalize_workspace_root_for_environment(_default_environment, workspace_root),
    do: workspace_root

  defp maybe_put(map, _key, :__not_set__), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp valid_default_environment?(default_environment),
    do: default_environment in [:sprite, :local]

  defp valid_workspace_root?(:sprite, workspace_root), do: is_nil(workspace_root)

  defp valid_workspace_root?(:local, workspace_root),
    do: is_binary(workspace_root) and String.trim(workspace_root) != ""

  defp valid_workspace_root?(_default_environment, _workspace_root), do: false

  defp normalize_default_environment(:sprite, _default), do: :sprite
  defp normalize_default_environment(:local, _default), do: :local
  defp normalize_default_environment("sprite", _default), do: :sprite
  defp normalize_default_environment("local", _default), do: :local
  defp normalize_default_environment(_default_environment, default), do: default

  defp normalize_workspace_root(nil), do: nil

  defp normalize_workspace_root(workspace_root) when is_binary(workspace_root) do
    workspace_root
    |> String.trim()
    |> case do
      "" -> nil
      normalized_workspace_root -> normalized_workspace_root
    end
  end

  defp normalize_workspace_root(_workspace_root), do: nil

  defp map_get(map, atom_key, string_key, default) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp load_error(reason) do
    %{
      onboarding_step: 1,
      detail: reason,
      diagnostic:
        "Unable to load SystemConfig. Continue setup from step 1 and verify configuration storage (#{format_reason(reason)})."
    }
  end

  defp save_error(reason, onboarding_step) do
    %{
      onboarding_step: onboarding_step,
      detail: reason,
      diagnostic:
        "Unable to persist onboarding progress. No progress was advanced, so you can safely retry this step (#{format_reason(reason)})."
    }
  end

  defp onboarding_step_from_reason(%{onboarding_step: onboarding_step})
       when is_integer(onboarding_step) and onboarding_step > 0 do
    onboarding_step
  end

  defp onboarding_step_from_reason(_), do: 1

  defp format_reason(reason), do: inspect(reason)
end
