<script setup lang="ts">
// covers: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
// covers: architecture.frontend_stack.server_authored_props_streams_and_events
// covers: architecture.frontend_stack.adoption_is_incremental_per_surface
// covers: setup.onboarding.github_repository_selection_persisted_metadata
import { computed, ref, watch } from "vue"

type RepositoryOption = {
  id: string
  fullName: string
  owner: string
  name: string
}

const props = defineProps<{
  listingStatus: string
  listingDetail: string
  listingRemediation: string | null
  listingErrorType: string | null
  listingCheckedAt: string
  repositoryCountLabel: string
  repositoryOptions: RepositoryOption[]
  selectedRepository: string | null
  importStatus: string
  importDetail: string
  importRemediation: string | null
  importErrorType: string | null
  importSelectedRepository: string | null
  importProjectId: string | null
  importProjectDisplayName: string | null
  importProjectPath: string | null
  importMode: string | null
  buttonsDisabled: boolean
}>()

const emit = defineEmits<{
  (event: "selectRepository", payload: { repository_full_name: string }): void
  (event: "refreshRepositories"): void
  (event: "importRepository", payload: { repository_full_name: string }): void
}>()

const filterQuery = ref("")
const localSelection = ref(props.selectedRepository ?? props.repositoryOptions[0]?.fullName ?? "")

watch(
  () => props.selectedRepository,
  selectedRepository => {
    const fallbackSelection = props.repositoryOptions[0]?.fullName ?? ""
    localSelection.value = selectedRepository ?? fallbackSelection
  }
)

watch(
  () => props.repositoryOptions,
  repositoryOptions => {
    const availableNames = repositoryOptions.map(repository => repository.fullName)

    if (!availableNames.includes(localSelection.value)) {
      localSelection.value = props.selectedRepository ?? repositoryOptions[0]?.fullName ?? ""
    }
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

const selectedRepositorySummary = computed(() => {
  if (localSelection.value !== "") {
    return localSelection.value
  }

  return "Choose one of the linked repositories below."
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
  () => props.buttonsDisabled || localSelection.value === "" || props.repositoryOptions.length === 0
)

const repositoryCardClass = (repository: RepositoryOption) => [
  "rounded-xl border p-3 text-left transition",
  repository.fullName === localSelection.value
    ? "border-primary/60 bg-primary/10"
    : "border-base-300/70 bg-base-200/20 hover:border-primary/40",
]

const selectRepository = (repositoryFullName: string) => {
  localSelection.value = repositoryFullName
  emit("selectRepository", { repository_full_name: repositoryFullName })
}

const importRepository = () => {
  if (importButtonDisabled.value) return
  emit("importRepository", { repository_full_name: localSelection.value })
}
</script>

<template>
  <section class="space-y-4">
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div class="space-y-1">
        <div class="flex flex-wrap items-center gap-2">
          <h3 class="text-lg font-semibold">Linked GitHub repositories</h3>
          <span id="setup-github-repository-widget-status" :class="listingBadgeClass">
            {{ props.listingStatus === "ready" ? "Ready" : "Needs attention" }}
          </span>
        </div>
        <p class="text-sm text-base-content/70">
          LiveView still owns the saved selection and import state; this widget only makes repository choice easier to scan and resume.
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

    <div class="grid gap-3 lg:grid-cols-[minmax(0,14rem)_minmax(0,1fr)]">
      <article class="rounded-xl border border-base-300/70 bg-base-200/20 p-4 space-y-3">
        <div class="space-y-1">
          <p class="text-xs uppercase text-base-content/60">Saved selection</p>
          <p id="setup-github-repository-widget-selection" class="text-base font-semibold">
            {{ selectedRepositorySummary }}
          </p>
        </div>

        <div class="space-y-1">
          <p class="text-xs uppercase text-base-content/60">Linked access</p>
          <p id="setup-github-repository-widget-count" class="text-sm text-base-content/80">
            {{ props.repositoryCountLabel }}
          </p>
          <p id="setup-github-repository-widget-checked-at" class="text-xs text-base-content/60">
            Refreshed: {{ props.listingCheckedAt }}
          </p>
        </div>

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
              {{ props.importMode === "existing" ? "Existing repo" : "New repo" }}
            </span>
          </div>
        </div>
      </article>

      <div class="space-y-4 rounded-xl border border-base-300/70 bg-base-100 p-4">
        <div class="grid gap-3 md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_auto]">
          <label class="fieldset">
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

          <label class="fieldset">
            <span class="label mb-1">GitHub repository</span>
            <select
              id="setup-github-repository-widget-select"
              class="select w-full"
              :disabled="props.buttonsDisabled || filteredRepositories.length === 0"
              :value="localSelection"
              @change="selectRepository(($event.target as HTMLSelectElement).value)"
            >
              <option value="">Choose a repository</option>
              <option
                v-for="repository in filteredRepositories"
                :key="repository.id"
                :value="repository.fullName"
              >
                {{ repository.fullName }}
              </option>
            </select>
          </label>

          <button
            id="setup-github-repository-widget-import"
            type="button"
            class="btn btn-primary md:self-end"
            :disabled="importButtonDisabled"
            @click="importRepository"
          >
            Import selected repository
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

        <div v-else class="grid gap-3 xl:grid-cols-2">
          <button
            v-for="repository in filteredRepositories.slice(0, 6)"
            :id="`setup-github-repository-widget-card-${repository.id}`"
            :key="repository.id"
            :class="repositoryCardClass(repository)"
            type="button"
            @click="selectRepository(repository.fullName)"
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
                :class="repository.fullName === localSelection ? 'badge-primary' : 'badge-ghost'"
              >
                {{ repository.fullName === localSelection ? "Selected" : "Linked" }}
              </span>
            </div>
            <p class="mt-3 text-sm text-base-content/70">
              Import {{ repository.name }} as a managed repository and keep GitHub as its source identity.
            </p>
          </button>
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
