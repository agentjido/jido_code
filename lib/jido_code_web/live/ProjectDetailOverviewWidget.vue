<script setup lang="ts">
// covers: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
// covers: architecture.frontend_stack.server_authored_props_streams_and_events
// covers: architecture.frontend_stack.adoption_is_incremental_per_surface
// covers: architecture.conversation_driver.project_detail_surface_preserves_managed_repo_context
import { computed, ref } from "vue"

type WorkflowCard = {
  id: string
  label: string
  name: string
  launchable: boolean
  feedbackStatus: string | null
  feedbackMessage: string | null
}

type ConversationSummary = {
  status: string
  ready: boolean
  blocked: boolean
  blockedDetail: string | null
  messageCount: number
  startEnabled: boolean
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
  conversation: ConversationSummary
}>()

const emit = defineEmits<{
  (event: "startConversation"): void
}>()

const filter = ref<FilterMode>("all")

const filteredWorkflows = computed(() => {
  if (filter.value === "launchable") {
    return props.workflowCards.filter(card => card.launchable)
  }

  return props.workflowCards
})

const filterButtonClass = (mode: FilterMode) => [
  "btn btn-xs join-item",
  filter.value === mode ? "btn-primary" : "btn-ghost",
]

const launchStateLabel = computed(() => (props.launchReady ? "Ready" : "Blocked"))
</script>

<template>
  <section class="rounded-lg border border-base-300 bg-base-200/20 p-4 space-y-4">
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div class="space-y-1">
        <h2 class="text-lg font-semibold">Managed repo overview</h2>
        <p class="text-sm text-base-content/70">
          LiveView still owns workflow launch and conversation state; this summary only groups the current server-authored context.
        </p>
      </div>

      <button
        v-if="props.conversation.startEnabled"
        id="project-detail-overview-start-conversation"
        type="button"
        class="btn btn-sm btn-primary"
        @click="emit('startConversation')"
      >
        Start conversation
      </button>
    </div>

    <div class="grid gap-3 md:grid-cols-3">
      <article class="rounded-lg border border-base-300/70 bg-base-100 p-3">
        <p class="text-xs uppercase text-base-content/60">Repository</p>
        <p class="mt-1 text-sm font-semibold">{{ props.githubFullName }}</p>
        <p class="mt-2 text-xs text-base-content/70">
          {{ props.projectName }} · default branch {{ props.defaultBranch }}
        </p>
      </article>

      <article class="rounded-lg border border-base-300/70 bg-base-100 p-3">
        <p class="text-xs uppercase text-base-content/60">Launch posture</p>
        <p class="mt-1 text-2xl font-semibold">{{ launchStateLabel }}</p>
        <p class="mt-2 text-xs text-base-content/70">{{ props.launchSummary }}</p>
      </article>

      <article class="rounded-lg border border-base-300/70 bg-base-100 p-3">
        <p class="text-xs uppercase text-base-content/60">Conversation</p>
        <p class="mt-1 text-2xl font-semibold">{{ props.conversation.status }}</p>
        <p class="mt-2 text-xs text-base-content/70">
          {{ props.conversation.messageCount }} message(s) in the current session view.
        </p>
        <p v-if="props.conversation.blockedDetail" class="mt-1 text-xs text-warning">
          {{ props.conversation.blockedDetail }}
        </p>
      </article>
    </div>

    <div class="flex flex-wrap items-center justify-between gap-3">
      <div class="space-y-1">
        <p class="text-sm font-medium">Workflow cards</p>
        <p class="text-xs text-base-content/70">
          Managed repo {{ props.managedRepoId ?? "pending compatibility projection" }}
        </p>
      </div>

      <div class="join">
        <button :class="filterButtonClass('all')" type="button" @click="filter = 'all'">
          All ({{ props.workflowCards.length }})
        </button>
        <button :class="filterButtonClass('launchable')" type="button" @click="filter = 'launchable'">
          Launchable ({{ props.workflowCards.filter(card => card.launchable).length }})
        </button>
      </div>
    </div>

    <div v-if="filteredWorkflows.length === 0" class="rounded border border-dashed border-base-300/80 bg-base-100 px-4 py-5 text-sm text-base-content/70">
      No workflows match the current lens.
    </div>

    <div v-else class="grid gap-3 md:grid-cols-2">
      <article
        v-for="workflow in filteredWorkflows"
        :id="`project-detail-overview-workflow-${workflow.id}`"
        :key="workflow.id"
        class="rounded-lg border border-base-300/70 bg-base-100 p-3 space-y-1"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <p class="font-medium">{{ workflow.label }}</p>
          <span class="badge" :class="workflow.launchable ? 'badge-success' : 'badge-warning'">
            {{ workflow.launchable ? "launchable" : "blocked" }}
          </span>
        </div>
        <p class="font-mono text-xs text-base-content/70">{{ workflow.name }}</p>
        <p v-if="workflow.feedbackMessage" class="text-xs text-base-content/80">
          {{ workflow.feedbackMessage }}
        </p>
      </article>
    </div>
  </section>
</template>
