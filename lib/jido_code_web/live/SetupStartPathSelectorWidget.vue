<script setup lang="ts">
// covers: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
// covers: architecture.frontend_stack.server_authored_props_streams_and_events
// covers: architecture.frontend_stack.adoption_is_incremental_per_surface
// covers: architecture.frontend_stack.setup_entry_surface_uses_bounded_live_vue_regions
// covers: setup.onboarding.start_path_preference_persisted
// covers: setup.onboarding.hybrid_follow_up_regions_keep_sensitive_controls_liveview_owned
import { computed } from "vue"

type StartOption = {
  id: string
  title: string
  summary: string
  detail: string
  badgeLabel: string | null
  buttonLabel: string
  buttonClass: string
  selected: boolean
  disabled: boolean
}

const props = defineProps<{
  options: StartOption[]
  selectedStartPath: string | null
}>()

const emit = defineEmits<{
  (event: "chooseStartPath", payload: { choice: string }): void
}>()

const selectedOption = computed(
  () => props.options.find(option => option.id === props.selectedStartPath) ?? null
)

const chooseStartPath = (option: StartOption) => {
  if (option.disabled) return
  emit("chooseStartPath", { choice: option.id })
}
</script>

<template>
  <section class="space-y-4">
    <div
      id="setup-start-path-widget-summary"
      class="flex flex-wrap items-center justify-between gap-2 rounded-2xl border border-base-300/70 bg-base-200/20 px-4 py-3 text-sm text-base-content/70"
    >
      <p>
        {{
          selectedOption
            ? `Saved start path: ${selectedOption.title}`
            : "Choose the start path that best fits this install."
        }}
      </p>
      <span v-if="selectedOption" class="badge badge-outline text-xs">LiveView owned</span>
    </div>

    <article
      v-for="option in props.options"
      :id="`setup-start-choice-${option.id}`"
      :key="option.id"
      :class="[
        'rounded-2xl border p-5 transition',
        option.selected ? 'border-primary/50 bg-base-100 shadow-sm' : 'border-base-300 bg-base-100/80',
      ]"
    >
      <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div class="space-y-2">
          <div class="flex flex-wrap items-center gap-2">
            <h2 class="text-xl font-semibold">{{ option.title }}</h2>
            <span
              v-if="option.badgeLabel"
              :id="`setup-start-choice-${option.id}-badge`"
              class="badge badge-outline text-xs"
            >
              {{ option.badgeLabel }}
            </span>
          </div>
          <p class="text-sm font-medium text-base-content/80">{{ option.summary }}</p>
          <p class="max-w-2xl text-sm text-base-content/60">{{ option.detail }}</p>
        </div>

        <button
          :id="`setup-start-choice-${option.id}-save`"
          type="button"
          :disabled="option.disabled"
          :aria-pressed="option.selected"
          :class="['btn btn-sm w-full sm:w-auto', option.buttonClass, option.disabled && 'btn-disabled']"
          @click="chooseStartPath(option)"
        >
          {{ option.buttonLabel }}
        </button>
      </div>
    </article>
  </section>
</template>
