<script setup lang="ts">
// covers: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
// covers: architecture.frontend_stack.server_authored_props_streams_and_events
// covers: architecture.frontend_stack.adoption_is_incremental_per_surface
// covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
import { computed, ref } from "vue"

type FilterChips = {
  project: string
  workState: string
  freshnessWindow: string
  sortOrder: string
}

type ProjectSummary = {
  id: string
  githubFullName: string
  backlogCount: number
  recentActivitySummary: string
  runOutcomeStatus: string | null
  requiresAttention: boolean
}

type LensMode = "all" | "attention"

const props = defineProps<{
  inventoryCount: number
  inventoryTotalCount: number
  attentionCount: number
  filterChips: FilterChips
  projectSummaries: ProjectSummary[]
  resetVisible: boolean
}>()

const emit = defineEmits<{
  (event: "resetFilters"): void
}>()

const lens = ref<LensMode>("all")

const filteredProjects = computed(() => {
  if (lens.value === "attention") {
    return props.projectSummaries.filter(project => project.requiresAttention)
  }

  return props.projectSummaries
})

const lensButtonClass = (mode: LensMode) => [
  "btn btn-xs join-item",
  lens.value === mode ? "btn-primary" : "btn-ghost",
]
</script>

<template>
  <section class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-4">
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div class="space-y-1">
        <h2 class="text-lg font-semibold">Workbench summary</h2>
        <p class="text-sm text-base-content/70">
          LiveView still owns filter state, streaming updates, and workflow kickoffs; this widget only groups the current inventory snapshot.
        </p>
      </div>

      <button
        v-if="props.resetVisible"
        id="workbench-summary-reset-filters"
        type="button"
        class="btn btn-sm btn-outline"
        @click="emit('resetFilters')"
      >
        Reset filters
      </button>
    </div>

    <div class="grid gap-3 md:grid-cols-3">
      <article class="rounded-lg border border-base-300/70 bg-base-200/20 p-3">
        <p class="text-xs uppercase text-base-content/60">Visible repos</p>
        <p class="mt-1 text-2xl font-semibold">{{ props.inventoryCount }}</p>
        <p class="mt-2 text-xs text-base-content/70">of {{ props.inventoryTotalCount }} total</p>
      </article>
      <article class="rounded-lg border border-base-300/70 bg-base-200/20 p-3">
        <p class="text-xs uppercase text-base-content/60">Attention items</p>
        <p class="mt-1 text-2xl font-semibold">{{ props.attentionCount }}</p>
        <p class="mt-2 text-xs text-base-content/70">projects with non-green recent outcomes</p>
      </article>
      <article class="rounded-lg border border-base-300/70 bg-base-200/20 p-3 space-y-1">
        <p class="text-xs uppercase text-base-content/60">Active filters</p>
        <p class="text-xs text-base-content/70">Repo: {{ props.filterChips.project }}</p>
        <p class="text-xs text-base-content/70">State: {{ props.filterChips.workState }}</p>
        <p class="text-xs text-base-content/70">Freshness: {{ props.filterChips.freshnessWindow }}</p>
        <p class="text-xs text-base-content/70">Sort: {{ props.filterChips.sortOrder }}</p>
      </article>
    </div>

    <div class="flex flex-wrap items-center justify-between gap-3">
      <p class="text-sm font-medium">Inventory lens</p>

      <div class="join">
        <button :class="lensButtonClass('all')" type="button" @click="lens = 'all'">
          All ({{ props.projectSummaries.length }})
        </button>
        <button :class="lensButtonClass('attention')" type="button" @click="lens = 'attention'">
          Attention ({{ props.attentionCount }})
        </button>
      </div>
    </div>

    <div v-if="filteredProjects.length === 0" class="rounded border border-dashed border-base-300/80 bg-base-200/10 px-4 py-5 text-sm text-base-content/70">
      No workbench projects match the current summary lens.
    </div>

    <ol v-else class="grid gap-3 lg:grid-cols-2">
      <li
        v-for="project in filteredProjects"
        :id="`workbench-summary-project-${project.id}`"
        :key="project.id"
        class="rounded-lg border border-base-300/70 bg-base-200/20 p-3 space-y-1"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <p class="font-medium">{{ project.githubFullName }}</p>
          <span class="badge" :class="project.requiresAttention ? 'badge-warning' : 'badge-success'">
            {{ project.requiresAttention ? "attention" : "stable" }}
          </span>
        </div>
        <p class="text-xs text-base-content/70">Backlog: {{ project.backlogCount }}</p>
        <p v-if="project.runOutcomeStatus" class="text-xs text-base-content/70">
          Recent run: {{ project.runOutcomeStatus }}
        </p>
        <p class="text-xs text-base-content/80">{{ project.recentActivitySummary }}</p>
      </li>
    </ol>
  </section>
</template>
