<script setup lang="ts">
// covers: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
// covers: architecture.frontend_stack.server_authored_props_streams_and_events
// covers: architecture.frontend_stack.adoption_is_incremental_per_surface
// covers: architecture.frontend_stack.setup_entry_surface_uses_bounded_live_vue_regions
// covers: setup.onboarding.start_path_preference_persisted
// covers: setup.onboarding.hybrid_follow_up_regions_keep_sensitive_controls_liveview_owned
import { computed } from "vue"
import { Badge } from "@/vue/components/ui/badge"
import { Button } from "@/vue/components/ui/button"

type StartOption = {
  id: string
  title: string
  summary: string
  detail: string
  badgeLabel: string | null
  buttonLabel: string
  buttonVariant: "default" | "outline" | "ghost"
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
      class="flex flex-wrap items-center justify-between gap-2 rounded-2xl border border-border/70 bg-muted/40 px-4 py-3 text-sm text-muted-foreground"
    >
      <p>
        {{
          selectedOption
            ? `Saved start path: ${selectedOption.title}`
            : "Choose the start path that best fits this install."
        }}
      </p>
      <Badge v-if="selectedOption" variant="outline">LiveView owned</Badge>
    </div>

    <article
      v-for="option in props.options"
      :id="`setup-start-choice-${option.id}`"
      :key="option.id"
      :class="[
        'rounded-2xl border p-5 transition',
        option.selected ? 'border-primary/50 bg-card shadow-sm' : 'border-border bg-card/80',
      ]"
    >
      <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div class="space-y-2">
          <div class="flex flex-wrap items-center gap-2">
            <h2 class="text-xl font-semibold">{{ option.title }}</h2>
            <Badge
              v-if="option.badgeLabel"
              :id="`setup-start-choice-${option.id}-badge`"
              variant="outline"
            >
              {{ option.badgeLabel }}
            </Badge>
          </div>
          <p class="text-sm font-medium text-foreground">{{ option.summary }}</p>
          <p class="max-w-2xl text-sm text-muted-foreground">{{ option.detail }}</p>
        </div>

        <Button
          :id="`setup-start-choice-${option.id}-save`"
          :variant="option.buttonVariant"
          size="sm"
          :disabled="option.disabled"
          :aria-pressed="option.selected"
          class="w-full sm:w-auto"
          @click="chooseStartPath(option)"
        >
          {{ option.buttonLabel }}
        </Button>
      </div>
    </article>
  </section>
</template>
