<script setup lang="ts">
// covers: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
// covers: architecture.frontend_stack.server_authored_props_streams_and_events
// covers: architecture.frontend_stack.adoption_is_incremental_per_surface
// covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
// covers: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
import { computed, ref } from "vue"
import { Badge } from "@/vue/components/ui/badge"
import { Button } from "@/vue/components/ui/button"

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

const filterButtonVariant = (mode: FilterMode) => (filter.value === mode ? "default" : "ghost")
</script>

<template>
  <div class="space-y-4">
    <div class="grid gap-3 md:grid-cols-3">
      <div class="rounded border border-border/70 bg-muted/40 p-3">
        <p class="text-xs uppercase text-muted-foreground">Blocked repos</p>
        <p class="mt-1 text-2xl font-semibold">{{ props.counts.blocked }}</p>
      </div>
      <div class="rounded border border-border/70 bg-muted/40 p-3">
        <p class="text-xs uppercase text-muted-foreground">Review-required repos</p>
        <p class="mt-1 text-2xl font-semibold">{{ props.counts.degraded }}</p>
      </div>
      <div class="rounded border border-border/70 bg-muted/40 p-3">
        <p class="text-xs uppercase text-muted-foreground">Stable repos</p>
        <p class="mt-1 text-2xl font-semibold">{{ props.counts.available }}</p>
      </div>
    </div>

    <div class="flex flex-wrap items-center justify-between gap-3">
      <p class="text-sm font-medium">Posture lenses</p>

      <div class="inline-flex rounded-md border border-border bg-muted/40 p-1">
        <Button :variant="filterButtonVariant('all')" size="sm" type="button" @click="filter = 'all'">
          All
        </Button>
        <Button :variant="filterButtonVariant('blocked')" size="sm" type="button" @click="filter = 'blocked'">
          Blocked
        </Button>
        <Button :variant="filterButtonVariant('review')" size="sm" type="button" @click="filter = 'review'">
          Review
        </Button>
        <Button :variant="filterButtonVariant('stable')" size="sm" type="button" @click="filter = 'stable'">
          Stable
        </Button>
      </div>
    </div>

    <p
      v-if="filteredSummaries.length === 0"
      id="dashboard-runtime-posture-widget-empty"
      class="rounded border border-dashed border-border/80 bg-muted/30 px-4 py-5 text-sm text-muted-foreground"
    >
      No runtime-service posture has been materialized for the current lens.
    </p>

    <ol v-else class="space-y-2">
      <li
        v-for="summary in filteredSummaries"
        :id="`dashboard-runtime-posture-widget-${summary.id}`"
        :key="summary.id"
        class="rounded border border-border/60 bg-muted/40 p-3 space-y-1"
      >
        <div class="flex flex-wrap items-center gap-2">
          <p class="text-sm font-medium">{{ summary.repoLabel }}</p>
          <span :class="summary.statusBadgeClass">{{ summary.statusLabel }}</span>
          <Badge
            v-if="summary.reviewRequired"
            variant="outline"
            class="border-accent-yellow/50 bg-accent-yellow/10 text-accent-yellow"
          >
            review required
          </Badge>
        </div>
        <p class="text-xs text-foreground">{{ summary.summary }}</p>
        <p class="text-xs text-muted-foreground">{{ summary.details }}</p>
      </li>
    </ol>
  </div>
</template>
