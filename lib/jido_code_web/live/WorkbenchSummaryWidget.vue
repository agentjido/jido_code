<script setup lang="ts">
// covers: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
// covers: architecture.frontend_stack.server_authored_props_streams_and_events
// covers: architecture.frontend_stack.adoption_is_incremental_per_surface
// covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
import { computed, ref } from "vue"
import { Badge } from "@/vue/components/ui/badge"
import { Button } from "@/vue/components/ui/button"

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

const lensButtonVariant = (mode: LensMode) => (lens.value === mode ? "default" : "ghost")
</script>

<template>
  <section class="rounded-lg border border-border bg-card p-4 space-y-4">
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div class="space-y-1">
        <h2 class="text-lg font-semibold">Workbench summary</h2>
        <p class="text-sm text-muted-foreground">
          LiveView still owns filter state, streaming updates, and workflow kickoffs; this widget only groups the current inventory snapshot.
        </p>
      </div>

      <Button
        v-if="props.resetVisible"
        id="workbench-summary-reset-filters"
        variant="outline"
        size="sm"
        @click="emit('resetFilters')"
      >
        Reset filters
      </Button>
    </div>

    <div class="grid gap-3 md:grid-cols-3">
      <article class="rounded-lg border border-border/70 bg-muted/40 p-3">
        <p class="text-xs uppercase text-muted-foreground">Visible repos</p>
        <p class="mt-1 text-2xl font-semibold">{{ props.inventoryCount }}</p>
        <p class="mt-2 text-xs text-muted-foreground">of {{ props.inventoryTotalCount }} total</p>
      </article>
      <article class="rounded-lg border border-border/70 bg-muted/40 p-3">
        <p class="text-xs uppercase text-muted-foreground">Attention items</p>
        <p class="mt-1 text-2xl font-semibold">{{ props.attentionCount }}</p>
        <p class="mt-2 text-xs text-muted-foreground">projects with non-green recent outcomes</p>
      </article>
      <article class="rounded-lg border border-border/70 bg-muted/40 p-3 space-y-1">
        <p class="text-xs uppercase text-muted-foreground">Active filters</p>
        <p class="text-xs text-muted-foreground">Repo: {{ props.filterChips.project }}</p>
        <p class="text-xs text-muted-foreground">State: {{ props.filterChips.workState }}</p>
        <p class="text-xs text-muted-foreground">Freshness: {{ props.filterChips.freshnessWindow }}</p>
        <p class="text-xs text-muted-foreground">Sort: {{ props.filterChips.sortOrder }}</p>
      </article>
    </div>

    <div class="flex flex-wrap items-center justify-between gap-3">
      <p class="text-sm font-medium">Inventory lens</p>

      <div class="inline-flex rounded-md border border-border bg-muted/40 p-1">
        <Button :variant="lensButtonVariant('all')" size="sm" type="button" @click="lens = 'all'">
          All ({{ props.projectSummaries.length }})
        </Button>
        <Button :variant="lensButtonVariant('attention')" size="sm" type="button" @click="lens = 'attention'">
          Attention ({{ props.attentionCount }})
        </Button>
      </div>
    </div>

    <div v-if="filteredProjects.length === 0" class="rounded border border-dashed border-border/80 bg-muted/30 px-4 py-5 text-sm text-muted-foreground">
      No workbench projects match the current summary lens.
    </div>

    <ol v-else class="grid gap-3 lg:grid-cols-2">
      <li
        v-for="project in filteredProjects"
        :id="`workbench-summary-project-${project.id}`"
        :key="project.id"
        class="rounded-lg border border-border/70 bg-muted/40 p-3 space-y-1"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <p class="font-medium">{{ project.githubFullName }}</p>
          <Badge
            variant="outline"
            :class="project.requiresAttention ? 'border-accent-yellow/50 bg-accent-yellow/10 text-accent-yellow' : 'border-accent-green/50 bg-accent-green/10 text-accent-green'"
          >
            {{ project.requiresAttention ? "attention" : "stable" }}
          </Badge>
        </div>
        <p class="text-xs text-muted-foreground">Backlog: {{ project.backlogCount }}</p>
        <p v-if="project.runOutcomeStatus" class="text-xs text-muted-foreground">
          Recent run: {{ project.runOutcomeStatus }}
        </p>
        <p class="text-xs text-foreground">{{ project.recentActivitySummary }}</p>
      </li>
    </ol>
  </section>
</template>
