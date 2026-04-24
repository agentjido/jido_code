<script setup lang="ts">
// covers: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
// covers: architecture.frontend_stack.server_authored_props_streams_and_events
// covers: architecture.frontend_stack.adoption_is_incremental_per_surface
// covers: architecture.frontend_stack.setup_entry_surface_uses_bounded_live_vue_regions
// covers: setup.onboarding.github_repository_selection_persisted_metadata
// covers: setup.onboarding.github_repository_selection_prefers_live_vue_widget_with_liveview_fallback
// covers: setup.onboarding.hybrid_follow_up_regions_keep_sensitive_controls_liveview_owned
import { computed, ref, watch } from "vue"

type RepositoryOption = {
  id: string
  fullName: string
  owner: string
  name: string
}

const props = defineProps<{
  panelTitle: string
  panelBadgeLabel: string
  panelSummary: string
  panelDetail: string
  boundaryNote: string
  listingStatus: string
  listingDetail: string
  listingRemediation: string | null
  listingErrorType: string | null
  listingCheckedAt: string
  repositoryCountLabel: string
  repositoryOptions: RepositoryOption[]
  selectedRepositories: string[]
  importStatus: string
  importDetail: string
  importRemediation: string | null
  importErrorType: string | null
  importSelectedRepositories: string[]
  importProjectId: string | null
  importProjectDisplayName: string | null
  importProjectPath: string | null
  importMode: string | null
  buttonsDisabled: boolean
}>()

const emit = defineEmits<{
  (event: "selectRepository", payload: { repository_full_names: string[] }): void
  (event: "refreshRepositories"): void
  (event: "importRepository", payload: { repository_full_names: string[] }): void
}>()

const filterQuery = ref("")
const localSelection = ref([...props.selectedRepositories])

watch(
  () => props.selectedRepositories,
  selectedRepositories => {
    localSelection.value = [...selectedRepositories]
  }
)

watch(
  () => props.repositoryOptions,
  repositoryOptions => {
    const availableNames = repositoryOptions.map(repository => repository.fullName)

    localSelection.value = localSelection.value.filter(repositoryFullName =>
      availableNames.includes(repositoryFullName)
    )
  },
  { deep: true }
)

const filteredRepositories = computed(() => {
  const normalizedQuery = filterQuery.value.trim().toLowerCase()

  if (normalizedQuery === "") {
    return props.repositoryOptions
  }

  return props.repositoryOptions.filter(repository =>
    [repository.fullName, repository.owner, repository.name]
      .join(" ")
      .toLowerCase()
      .includes(normalizedQuery)
  )
})

const filteredRepositoryCountLabel = computed(() => {
  const filteredCount = filteredRepositories.value.length
  const totalCount = props.repositoryOptions.length

  if (totalCount === 0) {
    return "No linked repositories are available yet."
  }

  if (filteredCount === totalCount) {
    return `Showing all ${totalCount} linked repositories.`
  }

  return `Showing ${filteredCount} of ${totalCount} linked repositories.`
})

const selectedRepositorySummary = computed(() => {
  if (localSelection.value.length === 0) {
    return "Not selected"
  }

  if (localSelection.value.length === 1) {
    return localSelection.value[0]
  }

  return `${localSelection.value.length} repositories selected`
})

const selectedResultsSummary = computed(() => {
  if (localSelection.value.length === 0) {
    return "Selected: none"
  }

  if (localSelection.value.length === 1) {
    return `Selected: ${localSelection.value[0]}`
  }

  return `Selected: ${localSelection.value.length} repositories`
})

const listingBadgeClass = computed(() => [
  "badge badge-outline text-xs",
  props.listingStatus === "ready" ? "badge-success" : "badge-warning",
])

const importBadgeClass = computed(() => [
  "badge badge-outline text-xs",
  props.importStatus === "ready"
    ? "badge-success"
    : props.importStatus === "blocked"
      ? "badge-warning"
      : "badge-ghost",
])

const importButtonDisabled = computed(
  () => props.buttonsDisabled || localSelection.value.length === 0 || props.repositoryOptions.length === 0
)

const importButtonLabel = computed(() => {
  if (localSelection.value.length === 0) {
    return "Select repositories to import"
  }

  if (localSelection.value.length === 1) {
    return "Import selected repository"
  }

  return `Import ${localSelection.value.length} selected repositories`
})

const repositoryCardClass = (repository: RepositoryOption) => [
  "rounded-xl border p-3 text-left transition",
  localSelection.value.includes(repository.fullName)
    ? "border-primary/60 bg-primary/10"
    : "border-base-300/70 bg-base-200/20 hover:border-primary/40",
]

const toggleRepository = (repositoryFullName: string) => {
  const nextSelection = localSelection.value.includes(repositoryFullName)
    ? localSelection.value.filter(selectedRepository => selectedRepository !== repositoryFullName)
    : [...localSelection.value, repositoryFullName]

  localSelection.value = nextSelection
  emit("selectRepository", { repository_full_names: nextSelection })
}

const importRepository = () => {
  if (importButtonDisabled.value) return
  emit("importRepository", { repository_full_names: localSelection.value })
}
</script>

<template>
  <section class="space-y-4">
    <div class="space-y-2">
      <div class="flex flex-wrap items-center gap-2">
        <h2 id="setup-github-repository-widget-title" class="text-xl font-semibold">
          {{ props.panelTitle }}
        </h2>
        <span id="setup-github-repository-widget-badge" class="badge badge-outline text-xs">
          {{ props.panelBadgeLabel }}
        </span>
      </div>
      <p id="setup-github-repository-widget-summary" class="text-sm font-medium text-base-content/80">
        {{ props.panelSummary }}
      </p>
      <p id="setup-github-repository-widget-detail" class="max-w-2xl text-sm text-base-content/60">
        {{ props.panelDetail }}
      </p>
    </div>

    <div class="flex flex-wrap items-start justify-between gap-3">
      <div class="space-y-1">
        <div class="flex flex-wrap items-center gap-2">
          <h3 class="text-lg font-semibold">Linked GitHub repositories</h3>
          <span id="setup-github-repository-widget-status" :class="listingBadgeClass">
            {{ props.listingStatus === "ready" ? "Ready" : "Needs attention" }}
          </span>
        </div>
        <p id="setup-github-repository-widget-boundary-note" class="text-sm text-base-content/70">
          {{ props.boundaryNote }}
        </p>
      </div>

      <button
        id="setup-github-repository-widget-refresh"
        type="button"
        class="btn btn-sm btn-outline"
        :disabled="props.buttonsDisabled"
        @click="emit('refreshRepositories')"
      >
        Refresh repositories
      </button>
    </div>

    <div class="space-y-4 rounded-xl border border-base-300/70 bg-base-100 p-4">
      <div class="grid gap-3 md:grid-cols-3">
        <article class="rounded-xl border border-base-300/70 bg-base-200/20 p-4 space-y-3">
          <div class="space-y-1">
            <p class="text-xs uppercase text-base-content/60">Saved selection</p>
            <p id="setup-github-repository-widget-selection" class="text-base font-semibold break-words">
              {{ selectedRepositorySummary }}
            </p>
          </div>
        </article>

        <article class="rounded-xl border border-base-300/70 bg-base-200/20 p-4 space-y-3">
          <div class="space-y-1">
            <p class="text-xs uppercase text-base-content/60">Linked access</p>
            <p id="setup-github-repository-widget-count" class="text-sm text-base-content/80">
              {{ props.repositoryCountLabel }}
            </p>
            <p id="setup-github-repository-widget-checked-at" class="text-xs text-base-content/60">
              Refreshed: {{ props.listingCheckedAt }}
            </p>
          </div>
        </article>

        <article class="rounded-xl border border-base-300/70 bg-base-200/20 p-4 space-y-3">
          <div class="space-y-1">
            <p class="text-xs uppercase text-base-content/60">Import state</p>
            <div class="flex flex-wrap items-center gap-2">
              <span id="setup-github-repository-widget-import-status" :class="importBadgeClass">
                {{
                  props.importStatus === "ready"
                    ? "Imported"
                    : props.importStatus === "blocked"
                      ? "Needs attention"
                      : "Not started"
                }}
              </span>
              <span v-if="props.importMode" class="badge badge-outline text-xs">
                {{ props.importMode === "existing" ? "Existing managed repo" : "Created managed repo" }}
              </span>
            </div>
          </div>
        </article>
      </div>

      <div class="space-y-4">
        <div class="flex flex-col gap-3 xl:flex-row xl:items-end">
          <label class="fieldset min-w-0 flex-1">
            <span class="label mb-1">Search linked repositories</span>
            <input
              id="setup-github-repository-widget-search"
              v-model="filterQuery"
              type="text"
              class="input w-full"
              placeholder="owner/repository"
              :disabled="props.buttonsDisabled || props.repositoryOptions.length === 0"
            />
          </label>

          <button
            id="setup-github-repository-widget-import"
            type="button"
            class="btn btn-primary w-full xl:w-auto xl:shrink-0"
            :disabled="importButtonDisabled"
            @click="importRepository"
          >
            {{ importButtonLabel }}
          </button>
        </div>

        <div
          class="rounded-xl border border-base-300/70 bg-base-200/20 px-4 py-3 text-sm text-base-content/80"
        >
          {{ props.listingDetail }}
        </div>

        <div
          v-if="props.listingRemediation"
          id="setup-github-repository-widget-remediation"
          class="rounded-xl border border-warning/40 bg-warning/10 px-4 py-3 text-sm text-base-content/80"
        >
          {{ props.listingRemediation }}
        </div>

        <div
          v-if="props.listingErrorType"
          id="setup-github-repository-widget-error-type"
          class="text-xs uppercase tracking-[0.25em] text-base-content/50"
        >
          {{ props.listingErrorType }}
        </div>

        <div
          v-if="filteredRepositories.length === 0"
          class="rounded-xl border border-dashed border-base-300/70 bg-base-200/10 px-4 py-5 text-sm text-base-content/70"
        >
          No linked repositories match the current filter.
        </div>

        <div v-else class="space-y-3">
          <div
            id="setup-github-repository-widget-results-summary"
            class="flex flex-wrap items-center justify-between gap-2 text-sm text-base-content/70"
          >
            <p>{{ filteredRepositoryCountLabel }}</p>
            <p class="font-medium text-base-content/80">
              {{ selectedResultsSummary }}
            </p>
          </div>

          <div
            id="setup-github-repository-widget-results"
            class="max-h-[28rem] overflow-y-auto pr-1"
          >
            <div class="grid gap-3 xl:grid-cols-2">
              <button
                v-for="repository in filteredRepositories"
                :id="`setup-github-repository-widget-card-${repository.id}`"
                :key="repository.id"
                :class="repositoryCardClass(repository)"
                type="button"
                :aria-pressed="localSelection.includes(repository.fullName)"
                @click="toggleRepository(repository.fullName)"
              >
                <div class="flex items-start justify-between gap-3">
                  <div class="space-y-1">
                    <p class="font-medium">{{ repository.fullName }}</p>
                    <p class="text-xs uppercase tracking-[0.2em] text-base-content/50">
                      {{ repository.owner }}
                    </p>
                  </div>
                  <span
                    class="badge badge-outline text-xs"
                    :class="localSelection.includes(repository.fullName) ? 'badge-primary' : 'badge-ghost'"
                  >
                    {{ localSelection.includes(repository.fullName) ? "Selected" : "Linked" }}
                  </span>
                </div>
                <p class="mt-3 text-sm text-base-content/70">
                  Import {{ repository.name }} as a managed repository and keep GitHub as its source identity.
                </p>
              </button>
            </div>
          </div>
        </div>

        <div class="rounded-xl border border-base-300/70 bg-base-200/20 px-4 py-3 space-y-2">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <p class="font-medium">
              {{ props.importProjectDisplayName ?? "Repository import status" }}
            </p>
            <a
              v-if="props.importProjectPath"
              id="setup-github-repository-widget-open-repo"
              :href="props.importProjectPath"
              class="btn btn-xs btn-outline"
            >
              Open managed repo
            </a>
          </div>
          <p id="setup-github-repository-widget-import-detail" class="text-sm text-base-content/80">
            {{ props.importDetail }}
          </p>
          <p
            v-if="props.importRemediation"
            id="setup-github-repository-widget-import-remediation"
            class="text-sm text-warning"
          >
            {{ props.importRemediation }}
          </p>
          <p
            v-if="props.importErrorType"
            id="setup-github-repository-widget-import-error-type"
            class="text-xs uppercase tracking-[0.25em] text-base-content/50"
          >
            {{ props.importErrorType }}
          </p>
        </div>
      </div>
    </div>
  </section>
</template>
