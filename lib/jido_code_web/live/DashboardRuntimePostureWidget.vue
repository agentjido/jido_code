<script setup lang="ts">
// covers: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
// covers: architecture.frontend_stack.server_authored_props_streams_and_events
// covers: architecture.frontend_stack.adoption_is_incremental_per_surface
// covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
// covers: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
import { computed, ref } from "vue"

type RuntimeEvidenceSummary = {
  id: string
  repoLabel: string
  status: string
  statusLabel: string
  statusBadgeClass: string
  reviewRequired: boolean
  summary: string
  details: string
}

type FilterMode = "all" | "blocked" | "review" | "stable"

const props = defineProps<{
  counts: {
    blocked: number
    degraded: number
    available: number
  }
  runtimeEvidenceSummaries: RuntimeEvidenceSummary[]
}>()

const filter = ref<FilterMode>("all")

const filteredSummaries = computed(() => {
  switch (filter.value) {
    case "blocked":
      return props.runtimeEvidenceSummaries.filter(summary => summary.status === "blocked")
    case "review":
      return props.runtimeEvidenceSummaries.filter(summary => summary.status === "degraded")
    case "stable":
      return props.runtimeEvidenceSummaries.filter(summary => summary.status === "available")
    default:
      return props.runtimeEvidenceSummaries
  }
})

const filterButtonClass = (mode: FilterMode) => [
  "btn btn-xs join-item",
  filter.value === mode ? "btn-primary" : "btn-ghost",
]
</script>

<template>
  <div class="space-y-4">
    <div class="grid gap-3 md:grid-cols-3">
      <div class="rounded border border-base-300/70 bg-base-200/20 p-3">
        <p class="text-xs uppercase text-base-content/60">Blocked repos</p>
        <p class="mt-1 text-2xl font-semibold">{{ props.counts.blocked }}</p>
      </div>
      <div class="rounded border border-base-300/70 bg-base-200/20 p-3">
        <p class="text-xs uppercase text-base-content/60">Review-required repos</p>
        <p class="mt-1 text-2xl font-semibold">{{ props.counts.degraded }}</p>
      </div>
      <div class="rounded border border-base-300/70 bg-base-200/20 p-3">
        <p class="text-xs uppercase text-base-content/60">Stable repos</p>
        <p class="mt-1 text-2xl font-semibold">{{ props.counts.available }}</p>
      </div>
    </div>

    <div class="flex flex-wrap items-center justify-between gap-3">
      <p class="text-sm font-medium">Posture lenses</p>

      <div class="join">
        <button :class="filterButtonClass('all')" type="button" @click="filter = 'all'">
          All
        </button>
        <button :class="filterButtonClass('blocked')" type="button" @click="filter = 'blocked'">
          Blocked
        </button>
        <button :class="filterButtonClass('review')" type="button" @click="filter = 'review'">
          Review
        </button>
        <button :class="filterButtonClass('stable')" type="button" @click="filter = 'stable'">
          Stable
        </button>
      </div>
    </div>

    <p
      v-if="filteredSummaries.length === 0"
      id="dashboard-runtime-posture-widget-empty"
      class="rounded border border-dashed border-base-300/80 bg-base-200/10 px-4 py-5 text-sm text-base-content/70"
    >
      No runtime-service posture has been materialized for the current lens.
    </p>

    <ol v-else class="space-y-2">
      <li
        v-for="summary in filteredSummaries"
        :id="`dashboard-runtime-posture-widget-${summary.id}`"
        :key="summary.id"
        class="rounded border border-base-300/60 bg-base-200/20 p-3 space-y-1"
      >
        <div class="flex flex-wrap items-center gap-2">
          <p class="text-sm font-medium">{{ summary.repoLabel }}</p>
          <span :class="summary.statusBadgeClass">{{ summary.statusLabel }}</span>
          <span v-if="summary.reviewRequired" class="badge badge-warning badge-outline">
            review required
          </span>
        </div>
        <p class="text-xs text-base-content/80">{{ summary.summary }}</p>
        <p class="text-xs text-base-content/70">{{ summary.details }}</p>
      </li>
    </ol>
  </div>
</template>
