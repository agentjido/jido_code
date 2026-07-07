<script setup lang="ts">
// covers: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
// covers: architecture.frontend_stack.server_authored_props_streams_and_events
// covers: architecture.frontend_stack.adoption_is_incremental_per_surface
import { computed, ref } from "vue"
import { Badge } from "@/vue/components/ui/badge"
import { Button } from "@/vue/components/ui/button"

type WorkflowCard = {
  id: string
  label: string
  name: string
  launchable: boolean
  feedbackStatus: string | null
  feedbackMessage: string | null
}

type FilterMode = "all" | "launchable"

const props = defineProps<{
  githubFullName: string
  projectName: string
  defaultBranch: string
  managedRepoId: string | null
  launchReady: boolean
  launchSummary: string
  workflowCards: WorkflowCard[]
}>()

const filter = ref<FilterMode>("all")

const filteredWorkflows = computed(() => {
  if (filter.value === "launchable") {
    return props.workflowCards.filter(card => card.launchable)
  }

  return props.workflowCards
})

const filterButtonVariant = (mode: FilterMode) => (filter.value === mode ? "default" : "ghost")

const launchStateLabel = computed(() => (props.launchReady ? "Ready" : "Blocked"))
</script>

<template>
  <section class="rounded-lg border border-border bg-muted/40 p-4 space-y-4">
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div class="space-y-1">
        <h2 class="text-lg font-semibold">Managed repo overview</h2>
        <p class="text-sm text-muted-foreground">
          LiveView still owns workflow launch state; this summary only groups the current server-authored context.
        </p>
      </div>
    </div>

    <div class="grid gap-3 md:grid-cols-3">
      <article class="rounded-lg border border-border/70 bg-card p-3">
        <p class="text-xs uppercase text-muted-foreground">Repository</p>
        <p class="mt-1 text-sm font-semibold">{{ props.githubFullName }}</p>
        <p class="mt-2 text-xs text-muted-foreground">
          {{ props.projectName }} · default branch {{ props.defaultBranch }}
        </p>
      </article>

      <article class="rounded-lg border border-border/70 bg-card p-3">
        <p class="text-xs uppercase text-muted-foreground">Launch posture</p>
        <p class="mt-1 text-2xl font-semibold">{{ launchStateLabel }}</p>
        <p class="mt-2 text-xs text-muted-foreground">{{ props.launchSummary }}</p>
      </article>

      <article class="rounded-lg border border-border/70 bg-card p-3">
        <p class="text-xs uppercase text-muted-foreground">Workflow cards</p>
        <p class="mt-1 text-2xl font-semibold">{{ props.workflowCards.length }}</p>
        <p class="mt-2 text-xs text-muted-foreground">
          Launch status and outcome summaries stay server-authored for governed operator review.
        </p>
      </article>
    </div>

    <div class="flex flex-wrap items-center justify-between gap-3">
      <div class="space-y-1">
        <p class="text-sm font-medium">Workflow cards</p>
        <p class="text-xs text-muted-foreground">
          Managed repo {{ props.managedRepoId ?? "pending compatibility projection" }}
        </p>
      </div>

      <div class="inline-flex rounded-md border border-border bg-muted/40 p-1">
        <Button :variant="filterButtonVariant('all')" size="sm" type="button" @click="filter = 'all'">
          All ({{ props.workflowCards.length }})
        </Button>
        <Button :variant="filterButtonVariant('launchable')" size="sm" type="button" @click="filter = 'launchable'">
          Launchable ({{ props.workflowCards.filter(card => card.launchable).length }})
        </Button>
      </div>
    </div>

    <div v-if="filteredWorkflows.length === 0" class="rounded border border-dashed border-border/80 bg-card px-4 py-5 text-sm text-muted-foreground">
      No workflows match the current lens.
    </div>

    <div v-else class="grid gap-3 md:grid-cols-2">
      <article
        v-for="workflow in filteredWorkflows"
        :id="`project-detail-overview-workflow-${workflow.id}`"
        :key="workflow.id"
        class="rounded-lg border border-border/70 bg-card p-3 space-y-1"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <p class="font-medium">{{ workflow.label }}</p>
          <Badge
            variant="outline"
            :class="workflow.launchable ? 'border-accent-green/50 bg-accent-green/10 text-accent-green' : 'border-accent-yellow/50 bg-accent-yellow/10 text-accent-yellow'"
          >
            {{ workflow.launchable ? "launchable" : "blocked" }}
          </Badge>
        </div>
        <p class="font-mono text-xs text-muted-foreground">{{ workflow.name }}</p>
        <p v-if="workflow.feedbackMessage" class="text-xs text-foreground">
          {{ workflow.feedbackMessage }}
        </p>
      </article>
    </div>
  </section>
</template>
