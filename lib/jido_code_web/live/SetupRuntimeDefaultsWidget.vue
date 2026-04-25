<script setup lang="ts">
// covers: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
// covers: architecture.frontend_stack.server_authored_props_streams_and_events
// covers: architecture.frontend_stack.adoption_is_incremental_per_surface
// covers: architecture.frontend_stack.setup_entry_surface_uses_bounded_live_vue_regions
// covers: setup.onboarding.runtime_environment_selection_persisted_metadata
// covers: setup.onboarding.hybrid_follow_up_regions_keep_sensitive_controls_liveview_owned
import { computed, ref, watch } from "vue"

type RuntimeOption = {
  label: string
  value: string
}

const props = defineProps<{
  runtimeDescription: string
  saveError: string | null
  form: {
    mode: string
    workspaceRoot: string
  }
  runtimeOptions: RuntimeOption[]
  installFlavor: string
  ownerEmail: string | null
  savedRuntimeLabel: string
  savedRuntimeNote: string
  selectedStartPathLabel: string
  buttonsDisabled: boolean
}>()

const emit = defineEmits<{
  (
    event: "changeRuntimeEnvironment",
    payload: { runtime_environment: { mode: string; workspace_root: string } }
  ): void
  (
    event: "saveRuntimeEnvironment",
    payload: { runtime_environment: { mode: string; workspace_root: string } }
  ): void
}>()

const localMode = ref(props.form.mode ?? "cloud")
const localWorkspaceRoot = ref(props.form.workspaceRoot ?? "")

watch(
  () => props.form,
  form => {
    localMode.value = form.mode ?? "cloud"
    localWorkspaceRoot.value = form.workspaceRoot ?? ""
  },
  { deep: true }
)

const showWorkspaceRoot = computed(() => localMode.value === "local")

const runtimePayload = () => ({
  runtime_environment: {
    mode: localMode.value,
    workspace_root: localWorkspaceRoot.value,
  },
})

const changeMode = (mode: string) => {
  localMode.value = mode
  emit("changeRuntimeEnvironment", runtimePayload())
}

const changeWorkspaceRoot = () => {
  emit("changeRuntimeEnvironment", runtimePayload())
}

const saveRuntimeDefaults = () => {
  if (props.buttonsDisabled) return
  emit("saveRuntimeEnvironment", runtimePayload())
}
</script>

<template>
  <section id="setup-runtime-defaults-panel" class="space-y-4 rounded-2xl border border-base-300 bg-base-100/80 p-5">
    <div class="space-y-2">
      <p class="text-xs font-medium uppercase tracking-[0.25em] text-base-content/50">Runtime defaults</p>
      <p id="setup-runtime-defaults-description" class="text-sm text-base-content/70">
        {{ props.runtimeDescription }}
      </p>
    </div>

    <div v-if="props.saveError" id="setup-runtime-save-error" class="alert alert-error">
      <span>{{ props.saveError }}</span>
    </div>

    <form id="setup-runtime-environment-form" class="space-y-3" @submit.prevent="saveRuntimeDefaults">
      <label class="fieldset">
        <span class="label mb-1">Runtime environment</span>
        <select
          id="setup-runtime-environment-select"
          class="select w-full"
          :disabled="props.buttonsDisabled"
          :value="localMode"
          @change="changeMode(($event.target as HTMLSelectElement).value)"
        >
          <option v-for="option in props.runtimeOptions" :key="option.value" :value="option.value">
            {{ option.label }}
          </option>
        </select>
      </label>

      <label v-if="showWorkspaceRoot" class="fieldset">
        <span class="label mb-1">Default workspace root</span>
        <input
          id="setup-runtime-workspace-root"
          v-model="localWorkspaceRoot"
          type="text"
          class="input w-full"
          placeholder="/absolute/path/used/for/new/local-imports"
          autocomplete="off"
          :disabled="props.buttonsDisabled"
          @change="changeWorkspaceRoot"
        />
      </label>

      <button
        id="setup-runtime-environment-save"
        type="submit"
        :disabled="props.buttonsDisabled"
        :class="['btn btn-primary w-full sm:w-auto', props.buttonsDisabled && 'btn-disabled']"
      >
        Save runtime defaults
      </button>
    </form>

    <dl class="space-y-4 border-t border-base-300/70 pt-4">
      <div class="space-y-1">
        <dt class="text-xs font-medium uppercase tracking-[0.25em] text-base-content/50">Install flavor</dt>
        <dd id="setup-install-flavor" class="text-sm font-medium">{{ props.installFlavor }}</dd>
      </div>

      <div class="space-y-1">
        <dt class="text-xs font-medium uppercase tracking-[0.25em] text-base-content/50">Admin email</dt>
        <dd id="setup-owner-email" class="text-sm font-medium">{{ props.ownerEmail }}</dd>
      </div>

      <div class="space-y-1">
        <dt class="text-xs font-medium uppercase tracking-[0.25em] text-base-content/50">Saved runtime default</dt>
        <dd id="setup-saved-runtime-environment" class="text-sm font-medium">
          {{ props.savedRuntimeLabel }}
        </dd>
        <p id="setup-saved-runtime-note" class="text-sm text-base-content/60">
          {{ props.savedRuntimeNote }}
        </p>
      </div>

      <div class="space-y-1">
        <dt class="text-xs font-medium uppercase tracking-[0.25em] text-base-content/50">Saved choice</dt>
        <dd id="setup-selected-start-path" class="text-sm font-medium">
          {{ props.selectedStartPathLabel }}
        </dd>
      </div>
    </dl>
  </section>
</template>
