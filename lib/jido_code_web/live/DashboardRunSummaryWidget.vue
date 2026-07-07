<script setup lang="ts">
// covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
// covers: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
// covers: architecture.frontend_stack.server_authored_props_streams_and_events
// covers: architecture.frontend_stack.adoption_is_incremental_per_surface
import { computed, ref } from "vue"
import { Button } from "@/vue/components/ui/button"

type RunSummary = {
  id: string
  runId: string
  workflowName: string
  status: string
  statusBadgeClass: string
  governanceSummary: string | null
  recencyLabel: string
  detailPath: string
  requiresAttention: boolean
  terminal: boolean
}

type FilterMode = "all" | "attention" | "terminal"

const props = defineProps<{
  runSummaries: RunSummary[]
  runSummaryCount: number
  lastRefreshedLabel: string
}>()

const filter = ref<FilterMode>("all")

const counts = computed(() => ({
  all: props.runSummaryCount,
  attention: props.runSummaries.filter(run => run.requiresAttention).length,
  terminal: props.runSummaries.filter(run => run.terminal).length,
}))

const filteredRuns = computed(() => {
  switch (filter.value) {
    case "attention":
      return props.runSummaries.filter(run => run.requiresAttention)
    case "terminal":
      return props.runSummaries.filter(run => run.terminal)
    default:
      return props.runSummaries
  }
})

const filterButtonVariant = (mode: FilterMode) => (filter.value === mode ? "default" : "ghost")
</script>

<template>
  <div class="space-y-3">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div class="space-y-1">
        <p class="text-sm font-medium">Operator lenses</p>
        <p class="text-xs text-muted-foreground">
          LiveView owns the feed; this widget only adds faster client-side slicing.
        </p>
      </div>

      <div class="inline-flex rounded-md border border-border bg-muted/40 p-1">
        <Button :variant="filterButtonVariant('all')" size="sm" type="button" @click="filter = 'all'">
          All ({{ counts.all }})
        </Button>
        <Button :variant="filterButtonVariant('attention')" size="sm" type="button" @click="filter = 'attention'">
          Attention ({{ counts.attention }})
        </Button>
        <Button :variant="filterButtonVariant('terminal')" size="sm" type="button" @click="filter = 'terminal'">
          Terminal ({{ counts.terminal }})
        </Button>
      </div>
    </div>

    <p class="text-xs text-muted-foreground">
      Feed snapshot from {{ props.lastRefreshedLabel }}
    </p>

    <div
      v-if="filteredRuns.length === 0"
      id="dashboard-run-summary-widget-empty"
      class="rounded border border-dashed border-border/80 bg-muted/30 px-4 py-5 text-sm text-muted-foreground"
    >
      {{
        props.runSummaryCount === 0
          ? "No recent runs available."
          : "No runs match the current operator lens."
      }}
    </div>

    <div v-else class="grid gap-3">
      <article
        v-for="run in filteredRuns"
        :id="`dashboard-run-summary-widget-${run.id}`"
        :key="run.id"
        class="rounded-lg border border-border/70 bg-muted/40 p-3 space-y-2"
      >
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div class="space-y-1">
            <a :href="run.detailPath" class="font-mono text-xs text-primary underline-offset-4 hover:underline">
              {{ run.runId }}
            </a>
            <p class="text-xs text-muted-foreground">{{ run.workflowName }}</p>
          </div>

          <span :class="run.statusBadgeClass">{{ run.status }}</span>
        </div>

        <p v-if="run.governanceSummary" class="text-xs text-foreground">
          {{ run.governanceSummary }}
        </p>

        <p class="text-xs text-muted-foreground">
          {{ run.recencyLabel }}
        </p>
      </article>
    </div>
  </div>
</template>
