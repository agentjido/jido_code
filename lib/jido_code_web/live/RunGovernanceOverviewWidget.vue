<script setup lang="ts">
// covers: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
// covers: architecture.frontend_stack.server_authored_props_streams_and_events
// covers: architecture.frontend_stack.adoption_is_incremental_per_surface
// covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
// covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
// covers: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
import { ref } from "vue"
import { Button } from "@/vue/components/ui/button"

type EvidenceEntry = {
  key: string
  summary: string
}

type DecisionEntry = {
  decision: string
  rationale: string | null
}

type RuntimeEvidence = {
  statusLabel: string
  summary: string
  deliveryMode: string | null
  reason: string | null
  integration: string | null
} | null

type ViewMode = "overview" | "evidence" | "decisions" | "runtime"

const props = defineProps<{
  runStatus: string
  currentStage: string | null
  changeRequestStatus: string | null
  evidenceCount: number
  decisionCount: number
  runtimeEvidence: RuntimeEvidence
  evidenceEntries: EvidenceEntry[]
  decisionEntries: DecisionEntry[]
}>()

const activeView = ref<ViewMode>("overview")

const tabVariant = (mode: ViewMode) => (activeView.value === mode ? "default" : "ghost")
</script>

<template>
  <section class="rounded-lg border border-border bg-muted/40 p-4 space-y-4">
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div class="space-y-1">
        <h2 class="text-lg font-semibold">Governance overview</h2>
        <p class="text-sm text-muted-foreground">
          LiveView keeps review actions and run state transitions authoritative while this widget groups governed evidence for faster scanning.
        </p>
      </div>

      <div class="inline-flex rounded-md border border-border bg-muted/40 p-1">
        <Button :variant="tabVariant('overview')" size="sm" type="button" @click="activeView = 'overview'">
          Overview
        </Button>
        <Button :variant="tabVariant('evidence')" size="sm" type="button" @click="activeView = 'evidence'">
          Evidence
        </Button>
        <Button :variant="tabVariant('decisions')" size="sm" type="button" @click="activeView = 'decisions'">
          Decisions
        </Button>
        <Button :variant="tabVariant('runtime')" size="sm" type="button" @click="activeView = 'runtime'">
          Runtime
        </Button>
      </div>
    </div>

    <div v-if="activeView === 'overview'" class="grid gap-3 md:grid-cols-4">
      <article class="rounded-lg border border-border/70 bg-card p-3">
        <p class="text-xs uppercase text-muted-foreground">Run status</p>
        <p class="mt-1 text-2xl font-semibold">{{ props.runStatus }}</p>
      </article>
      <article class="rounded-lg border border-border/70 bg-card p-3">
        <p class="text-xs uppercase text-muted-foreground">Governed stage</p>
        <p class="mt-1 text-2xl font-semibold">{{ props.currentStage ?? "n/a" }}</p>
      </article>
      <article class="rounded-lg border border-border/70 bg-card p-3">
        <p class="text-xs uppercase text-muted-foreground">Evidence</p>
        <p class="mt-1 text-2xl font-semibold">{{ props.evidenceCount }}</p>
      </article>
      <article class="rounded-lg border border-border/70 bg-card p-3">
        <p class="text-xs uppercase text-muted-foreground">Decisions</p>
        <p class="mt-1 text-2xl font-semibold">{{ props.decisionCount }}</p>
      </article>
    </div>

    <div v-else-if="activeView === 'evidence'" class="space-y-2">
      <p v-if="props.evidenceEntries.length === 0" class="text-sm text-muted-foreground">
        No governed evidence records have been captured yet.
      </p>
      <ol v-else class="space-y-2">
        <li
          v-for="evidence in props.evidenceEntries"
          :id="`run-governance-overview-evidence-${evidence.key}`"
          :key="evidence.key"
          class="rounded-lg border border-border/70 bg-card p-3 space-y-1"
        >
          <p class="text-sm font-medium">{{ evidence.key }}</p>
          <p class="text-xs text-foreground">{{ evidence.summary }}</p>
        </li>
      </ol>
    </div>

    <div v-else-if="activeView === 'decisions'" class="space-y-2">
      <p v-if="props.decisionEntries.length === 0" class="text-sm text-muted-foreground">
        No governance decisions have been recorded yet.
      </p>
      <ol v-else class="space-y-2">
        <li
          v-for="(decision, index) in props.decisionEntries"
          :id="`run-governance-overview-decision-${index + 1}`"
          :key="`${decision.decision}-${index}`"
          class="rounded-lg border border-border/70 bg-card p-3 space-y-1"
        >
          <p class="text-sm font-medium">{{ decision.decision }}</p>
          <p v-if="decision.rationale" class="text-xs text-foreground">
            {{ decision.rationale }}
          </p>
        </li>
      </ol>
    </div>

    <div v-else class="space-y-2">
      <p v-if="!props.runtimeEvidence" class="text-sm text-muted-foreground">
        No bounded runtime evidence has been materialized for this run yet.
      </p>
      <div v-else class="rounded-lg border border-border/70 bg-card p-3 space-y-1">
        <p class="text-sm font-medium">Runtime posture: {{ props.runtimeEvidence.statusLabel }}</p>
        <p class="text-xs text-foreground">{{ props.runtimeEvidence.summary }}</p>
        <p v-if="props.runtimeEvidence.deliveryMode" class="text-xs text-muted-foreground">
          Delivery path: {{ props.runtimeEvidence.deliveryMode }}
        </p>
        <p v-if="props.runtimeEvidence.reason" class="text-xs text-muted-foreground">
          Runtime reason: {{ props.runtimeEvidence.reason }}
        </p>
        <p v-if="props.runtimeEvidence.integration" class="text-xs text-muted-foreground">
          Latest integration signal: {{ props.runtimeEvidence.integration }}
        </p>
      </div>
    </div>

    <p v-if="props.changeRequestStatus" class="text-xs text-muted-foreground">
      Review request status: {{ props.changeRequestStatus }}
    </p>
  </section>
</template>
