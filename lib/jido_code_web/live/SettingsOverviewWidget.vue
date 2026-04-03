<script setup lang="ts">
// covers: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
// covers: architecture.frontend_stack.server_authored_props_streams_and_events
// covers: architecture.frontend_stack.adoption_is_incremental_per_surface
type OverviewCard = {
  id: string
  label: string
  value: string
  detail: string
  active: boolean
}

const props = defineProps<{
  activeTab: string
  cards: OverviewCard[]
  activeTabSummary: string
  openAddRepoVisible: boolean
}>()

const emit = defineEmits<{
  (event: "openAddRepo"): void
}>()

const cardClass = (card: OverviewCard) => [
  "rounded-lg border p-3 transition-colors",
  card.active
    ? "border-primary/70 bg-primary/10"
    : "border-base-300/70 bg-base-200/20",
]
</script>

<template>
  <section class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-4">
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div class="space-y-1">
        <h2 class="text-lg font-semibold">Settings overview</h2>
        <p class="text-sm text-base-content/70">
          LiveView still owns route state and mutations; Vue only groups the current operator snapshot.
        </p>
      </div>

      <button
        v-if="props.openAddRepoVisible"
        id="settings-overview-open-add-repo"
        type="button"
        class="btn btn-sm btn-primary"
        @click="emit('openAddRepo')"
      >
        Add GitHub repository
      </button>
    </div>

    <div class="grid gap-3 md:grid-cols-3">
      <article
        v-for="card in props.cards"
        :id="`settings-overview-card-${card.id}`"
        :key="card.id"
        :class="cardClass(card)"
      >
        <p class="text-xs uppercase text-base-content/60">{{ card.label }}</p>
        <p class="mt-1 text-2xl font-semibold">{{ card.value }}</p>
        <p class="mt-2 text-xs text-base-content/70">{{ card.detail }}</p>
      </article>
    </div>

    <p id="settings-overview-active-tab-summary" class="text-sm text-base-content/80">
      {{ props.activeTabSummary }}
    </p>
  </section>
</template>
