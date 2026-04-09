<script setup lang="ts">
// covers: architecture.source_code_graph_product_adoption.managed_repo_routes_host_semantic_inspection
// covers: architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals
// covers: architecture.frontend_stack.semantic_operator_surfaces_can_use_bounded_hybrid_regions
// covers: architecture.frontend_stack.server_authored_props_streams_and_events
import { computed, ref } from "vue"

type SummaryCard = {
  id: string
  label: string
  count: number
  detail: string
}

type ModuleItem = {
  moduleName: string | null
  moduleIri: string | null
}

type FunctionItem = {
  moduleName: string | null
  functionName: string | null
  arity: number | null
}

type RuntimePatternItem = {
  patternName: string | null
  patternIri: string | null
}

type ImpactItem = {
  predicateName: string | null
  sourceIri: string | null
  targetIri: string | null
}

type ExplorerLens = "modules" | "functions" | "runtimePatterns" | "impact"

const props = defineProps<{
  managedRepoId: string | null
  graph: {
    state: string
    ready: boolean
    stale: boolean
    degraded: boolean
    importedRevision: string | null
    currentRevision: string | null
  }
  summaryCards: SummaryCard[]
  modules: ModuleItem[]
  functions: FunctionItem[]
  runtimePatterns: RuntimePatternItem[]
  impact: ImpactItem[]
  recovery: {
    available: boolean
    label: string | null
  }
}>()

const emit = defineEmits<{
  requestRecovery: []
}>()

const lens = ref<ExplorerLens>("modules")

const lensButtons = [
  { id: "modules", label: "Modules" },
  { id: "functions", label: "Functions" },
  { id: "runtimePatterns", label: "Runtime patterns" },
  { id: "impact", label: "Impact" },
] as const

const graphStateLabel = computed(() => {
  switch (props.graph.state) {
    case "ready":
      return "Ready"
    case "stale":
      return "Stale"
    case "degraded":
      return "Degraded"
    case "failed":
      return "Failed"
    case "not_ready":
      return "Not loaded"
    case "disabled":
      return "Disabled"
    default:
      return "Unavailable"
  }
})

const graphBadgeClass = computed(() => {
  switch (props.graph.state) {
    case "ready":
      return "badge badge-success"
    case "stale":
    case "degraded":
      return "badge badge-warning"
    case "failed":
      return "badge badge-error"
    default:
      return "badge badge-outline"
  }
})

const lensRows = computed(() => {
  switch (lens.value) {
    case "modules":
      return props.modules.map(item => ({
        title: item.moduleName ?? "Unnamed module",
        detail: item.moduleIri ?? "No module identifier available",
      }))
    case "functions":
      return props.functions.map(item => ({
        title: [item.moduleName, item.functionName].filter(Boolean).join(" · ") || "Unnamed function",
        detail: item.arity == null ? "Arity unavailable" : `Arity ${item.arity}`,
      }))
    case "runtimePatterns":
      return props.runtimePatterns.map(item => ({
        title: item.patternName ?? "Unnamed runtime pattern",
        detail: item.patternIri ?? "No runtime pattern identifier available",
      }))
    case "impact":
      return props.impact.map(item => ({
        title: item.predicateName ?? "Relationship",
        detail: [item.sourceIri, item.targetIri].filter(Boolean).join(" -> ") || "No bounded impact path available",
      }))
  }
})

const lensButtonClass = (candidate: ExplorerLens) => [
  "btn btn-xs join-item",
  lens.value === candidate ? "btn-primary" : "btn-ghost",
]
</script>

<template>
  <section class="rounded-lg border border-base-300 bg-base-200/20 p-4 space-y-4">
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div class="space-y-1">
        <h3 class="text-lg font-semibold">Semantic explorer</h3>
        <p class="text-sm text-base-content/70">
          This managed repository keeps semantic inspection bounded to modules, functions, runtime patterns, and impact relationships.
        </p>
      </div>

      <div class="space-y-1 text-right">
        <span :class="graphBadgeClass">{{ graphStateLabel }}</span>
        <p class="text-xs text-base-content/70">
          Managed repo {{ props.managedRepoId ?? "pending" }}
        </p>
      </div>
    </div>

    <div class="grid gap-3 md:grid-cols-4">
      <article
        v-for="card in props.summaryCards"
        :key="card.id"
        :id="`project-detail-semantic-card-${card.id}`"
        class="rounded-lg border border-base-300/70 bg-base-100 p-3"
      >
        <p class="text-xs uppercase text-base-content/60">{{ card.label }}</p>
        <p class="mt-1 text-2xl font-semibold">{{ card.count }}</p>
        <p class="mt-2 text-xs text-base-content/70">{{ card.detail }}</p>
      </article>
    </div>

    <div class="flex flex-wrap items-center justify-between gap-3">
      <div class="space-y-1">
        <p class="text-sm font-medium">Inspection lens</p>
        <p class="text-xs text-base-content/70">
          Imported revision {{ props.graph.importedRevision ?? "not loaded" }}
          <span v-if="props.graph.currentRevision"> · current revision {{ props.graph.currentRevision }}</span>
        </p>
      </div>

      <div class="flex items-center gap-3">
        <div class="join">
          <button
            v-for="button in lensButtons"
            :key="button.id"
            :class="lensButtonClass(button.id)"
            type="button"
            @click="lens = button.id"
          >
            {{ button.label }}
          </button>
        </div>

        <button
          v-if="props.recovery.available"
          id="project-detail-semantic-widget-recover"
          type="button"
          class="btn btn-xs btn-outline"
          @click="emit('requestRecovery')"
        >
          {{ props.recovery.label ?? "Recover semantic graph" }}
        </button>
      </div>
    </div>

    <div
      v-if="lensRows.length === 0"
      id="project-detail-semantic-empty-state"
      class="rounded border border-dashed border-base-300/80 bg-base-100 px-4 py-5 text-sm text-base-content/70"
    >
      No bounded semantic entries are currently available for this lens.
    </div>

    <div v-else class="grid gap-3 md:grid-cols-2">
      <article
        v-for="row in lensRows"
        :key="`${lens}-${row.title}-${row.detail}`"
        class="rounded-lg border border-base-300/70 bg-base-100 p-3 space-y-1"
      >
        <p class="font-medium">{{ row.title }}</p>
        <p class="text-xs text-base-content/70 break-all">{{ row.detail }}</p>
      </article>
    </div>
  </section>
</template>
