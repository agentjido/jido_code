<script setup lang="ts">
// covers: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
// covers: architecture.frontend_stack.server_authored_props_streams_and_events
// covers: architecture.frontend_stack.adoption_is_incremental_per_surface
// covers: architecture.frontend_stack.setup_entry_surface_uses_bounded_live_vue_regions
// covers: setup.onboarding.github_repository_selection_persisted_metadata
// covers: setup.onboarding.github_repository_selection_prefers_live_vue_widget_with_liveview_fallback
// covers: setup.onboarding.github_repository_selection_supports_account_filter_and_matching_search
// covers: setup.onboarding.hybrid_follow_up_regions_keep_sensitive_controls_liveview_owned
import { computed, ref, watch } from "vue";
import { Badge } from "@/vue/components/ui/badge";
import { Button } from "@/vue/components/ui/button";
import { Input } from "@/vue/components/ui/input";

type RepositoryOption = {
  id: string;
  fullName: string;
  owner: string;
  name: string;
};

const props = defineProps<{
  panelTitle: string;
  panelBadgeLabel: string;
  panelSummary: string;
  panelDetail: string;
  boundaryNote: string;
  listingStatus: string;
  listingDetail: string;
  listingRemediation: string | null;
  listingErrorType: string | null;
  listingCheckedAt: string;
  accountOptions: string[];
  repositoryCountLabel: string;
  repositoryOptions: RepositoryOption[];
  selectedRepositories: string[];
  importStatus: string;
  importDetail: string;
  importRemediation: string | null;
  importErrorType: string | null;
  importSelectedRepositories: string[];
  importProjectId: string | null;
  importProjectDisplayName: string | null;
  importProjectPath: string | null;
  importMode: string | null;
  buttonsDisabled: boolean;
}>();

const emit = defineEmits<{
  (
    event: "selectRepository",
    payload: { repository_full_names: string[] }
  ): void;
  (event: "refreshRepositories"): void;
  (
    event: "importRepository",
    payload: { repository_full_names: string[] }
  ): void;
}>();

const filterQuery = ref("");
const accountFilter = ref("");
const localSelection = ref([...props.selectedRepositories]);

watch(
  () => props.selectedRepositories,
  (selectedRepositories) => {
    localSelection.value = [...selectedRepositories];
  }
);

watch(
  () => props.repositoryOptions,
  (repositoryOptions) => {
    const availableNames = repositoryOptions.map(
      (repository) => repository.fullName
    );

    localSelection.value = localSelection.value.filter((repositoryFullName) =>
      availableNames.includes(repositoryFullName)
    );
  },
  { deep: true }
);

watch(
  () => props.accountOptions,
  (accountOptions) => {
    if (
      accountFilter.value !== "" &&
      !accountOptions.includes(accountFilter.value)
    ) {
      accountFilter.value = "";
    }
  }
);

const filteredRepositories = computed(() => {
  const normalizedQuery = filterQuery.value.trim().toLowerCase();
  const selectedAccount = accountFilter.value.trim();

  return props.repositoryOptions.filter(
    (repository) =>
      (selectedAccount === "" || repository.owner === selectedAccount) &&
      (normalizedQuery === "" ||
        [repository.fullName, repository.owner, repository.name]
          .join(" ")
          .toLowerCase()
          .includes(normalizedQuery))
  );
});

const filteredRepositoryCountLabel = computed(() => {
  const filteredCount = filteredRepositories.value.length;
  const totalCount = props.repositoryOptions.length;

  if (totalCount === 0) {
    return "No linked repositories are available yet.";
  }

  if (filteredCount === totalCount) {
    return `Showing all ${totalCount} linked repositories.`;
  }

  return `Showing ${filteredCount} of ${totalCount} linked repositories.`;
});

const selectedRepositorySummary = computed(() => {
  if (localSelection.value.length === 0) {
    return "Not selected";
  }

  if (localSelection.value.length === 1) {
    return localSelection.value[0];
  }

  return `${localSelection.value.length} repositories selected`;
});

const selectedResultsSummary = computed(() => {
  if (localSelection.value.length === 0) {
    return "Selected: none";
  }

  if (localSelection.value.length === 1) {
    return `Selected: ${localSelection.value[0]}`;
  }

  return `Selected: ${localSelection.value.length} repositories`;
});

const listingBadgeToneClass = computed(() =>
  props.listingStatus === "ready"
    ? "border-accent-green/50 bg-accent-green/10 text-accent-green"
    : "border-accent-yellow/50 bg-accent-yellow/10 text-accent-yellow"
);

const importBadgeToneClass = computed(() =>
  props.importStatus === "ready"
    ? "border-accent-green/50 bg-accent-green/10 text-accent-green"
    : props.importStatus === "blocked"
    ? "border-accent-yellow/50 bg-accent-yellow/10 text-accent-yellow"
    : "border-border bg-muted/70 text-muted-foreground"
);

const importButtonDisabled = computed(
  () =>
    props.buttonsDisabled ||
    localSelection.value.length === 0 ||
    props.repositoryOptions.length === 0
);

const importButtonLabel = computed(() => {
  if (localSelection.value.length === 0) {
    return "Select repositories to import";
  }

  if (localSelection.value.length === 1) {
    return "Import selected repository";
  }

  return `Import ${localSelection.value.length} selected repositories`;
});

const repositoryCardClass = (repository: RepositoryOption) => [
  "rounded-xl border p-3 text-left transition",
  localSelection.value.includes(repository.fullName)
    ? "border-primary/60 bg-primary/10"
    : "border-border/70 bg-muted/40 hover:border-primary/40",
];

const toggleRepository = (repositoryFullName: string) => {
  const nextSelection = localSelection.value.includes(repositoryFullName)
    ? localSelection.value.filter(
        (selectedRepository) => selectedRepository !== repositoryFullName
      )
    : [...localSelection.value, repositoryFullName];

  localSelection.value = nextSelection;
  emit("selectRepository", { repository_full_names: nextSelection });
};

const importRepository = () => {
  if (importButtonDisabled.value) return;
  emit("importRepository", { repository_full_names: localSelection.value });
};
</script>

<template>
  <section class="space-y-4">
    <div class="space-y-2">
      <div class="flex flex-wrap items-center gap-2">
        <h2
          id="setup-github-repository-widget-title"
          class="text-xl font-semibold"
        >
          {{ props.panelTitle }}
        </h2>
        <Badge
          id="setup-github-repository-widget-badge"
          variant="outline"
        >
          {{ props.panelBadgeLabel }}
        </Badge>
      </div>
      <p
        id="setup-github-repository-widget-summary"
        class="text-sm font-medium text-foreground"
      >
        {{ props.panelSummary }}
      </p>
      <p
        id="setup-github-repository-widget-detail"
        class="max-w-2xl text-sm text-muted-foreground"
      >
        {{ props.panelDetail }}
      </p>
    </div>

    <div class="flex flex-wrap items-start justify-between gap-3">
      <div class="space-y-1">
        <div class="flex flex-wrap items-center gap-2">
          <h3 class="text-lg font-semibold">Linked GitHub repositories</h3>
          <Badge
            id="setup-github-repository-widget-status"
            variant="outline"
            :class="listingBadgeToneClass"
          >
            {{ props.listingStatus === "ready" ? "Ready" : "Needs attention" }}
          </Badge>
        </div>
        <p
          id="setup-github-repository-widget-boundary-note"
          class="text-sm text-muted-foreground"
        >
          {{ props.boundaryNote }}
        </p>
      </div>

      <Button
        id="setup-github-repository-widget-refresh"
        variant="outline"
        size="sm"
        :disabled="props.buttonsDisabled"
        @click="emit('refreshRepositories')"
      >
        Refresh repositories
      </Button>
    </div>

    <div class="space-y-4 rounded-xl border border-border/70 bg-card p-4">
      <div class="grid gap-3 md:grid-cols-3">
        <article
          class="rounded-xl border border-border/70 bg-muted/40 p-4 space-y-3"
        >
          <div class="space-y-1">
            <p class="text-xs uppercase text-muted-foreground">
              Saved selection
            </p>
            <p
              id="setup-github-repository-widget-selection"
              class="text-base font-semibold break-words"
            >
              {{ selectedRepositorySummary }}
            </p>
          </div>
        </article>

        <article
          class="rounded-xl border border-border/70 bg-muted/40 p-4 space-y-3"
        >
          <div class="space-y-1">
            <p class="text-xs uppercase text-muted-foreground">Linked access</p>
            <p
              id="setup-github-repository-widget-count"
              class="text-sm text-foreground"
            >
              {{ props.repositoryCountLabel }}
            </p>
            <p
              id="setup-github-repository-widget-checked-at"
              class="text-xs text-muted-foreground"
            >
              Refreshed: {{ props.listingCheckedAt }}
            </p>
          </div>
        </article>

        <article
          class="rounded-xl border border-border/70 bg-muted/40 p-4 space-y-3"
        >
          <div class="space-y-1">
            <p class="text-xs uppercase text-muted-foreground">Import state</p>
            <div class="flex flex-wrap items-center gap-2">
              <Badge
                id="setup-github-repository-widget-import-status"
                variant="outline"
                :class="importBadgeToneClass"
              >
                {{
                  props.importStatus === "ready"
                    ? "Imported"
                    : props.importStatus === "blocked"
                    ? "Needs attention"
                    : "Not started"
                }}
              </Badge>
              <Badge v-if="props.importMode" variant="outline">
                {{
                  props.importMode === "existing"
                    ? "Existing managed repo"
                    : "Created managed repo"
                }}
              </Badge>
            </div>
          </div>
        </article>
      </div>

      <div class="space-y-4">
        <div
          class="grid gap-3 xl:grid-cols-[minmax(0,14rem)_minmax(0,1fr)_auto] xl:items-end"
        >
          <label class="min-w-0 space-y-1">
            <span class="text-sm font-medium">GitHub account</span>
            <select
              id="setup-github-repository-widget-account-filter"
              v-model="accountFilter"
              class="ui-select w-full"
              :disabled="
                props.buttonsDisabled || props.repositoryOptions.length === 0
              "
            >
              <option value="">All accounts</option>
              <option
                v-for="account in props.accountOptions"
                :key="account"
                :value="account"
              >
                {{ account }}
              </option>
            </select>
          </label>

          <label class="min-w-0 space-y-1">
            <span class="text-sm font-medium">Search linked repositories</span>
            <Input
              id="setup-github-repository-widget-search"
              v-model="filterQuery"
              type="text"
              placeholder="owner/repository"
              :disabled="
                props.buttonsDisabled || props.repositoryOptions.length === 0
              "
            />
          </label>

          <Button
            id="setup-github-repository-widget-import"
            class="w-full xl:w-auto xl:shrink-0"
            :disabled="importButtonDisabled"
            @click="importRepository"
          >
            {{ importButtonLabel }}
          </Button>
        </div>

        <div
          class="rounded-xl border border-border/70 bg-muted/40 px-4 py-3 text-sm text-foreground"
        >
          {{ props.listingDetail }}
        </div>

        <div
          v-if="props.listingRemediation"
          id="setup-github-repository-widget-remediation"
          class="rounded-xl border border-accent-yellow/40 bg-accent-yellow/10 px-4 py-3 text-sm text-foreground"
        >
          {{ props.listingRemediation }}
        </div>

        <div
          v-if="props.listingErrorType"
          id="setup-github-repository-widget-error-type"
          class="text-xs uppercase tracking-[0.25em] text-muted-foreground"
        >
          {{ props.listingErrorType }}
        </div>

        <div
          v-if="filteredRepositories.length === 0"
          class="rounded-xl border border-dashed border-border/70 bg-muted/30 px-4 py-5 text-sm text-muted-foreground"
        >
          No linked repositories match the current filter.
        </div>

        <div v-else class="space-y-3">
          <div
            id="setup-github-repository-widget-results-summary"
            class="flex flex-wrap items-center justify-between gap-2 text-sm text-muted-foreground"
          >
            <p>{{ filteredRepositoryCountLabel }}</p>
            <p class="font-medium text-foreground">
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
                    <p
                      class="text-xs uppercase tracking-[0.2em] text-muted-foreground"
                    >
                      {{ repository.owner }}
                    </p>
                  </div>
                  <Badge
                    variant="outline"
                    :class="
                      localSelection.includes(repository.fullName)
                        ? 'border-primary/50 bg-primary/10 text-primary'
                        : 'border-border bg-muted/70 text-muted-foreground'
                    "
                  >
                    {{
                      localSelection.includes(repository.fullName)
                        ? "Selected"
                        : "Linked"
                    }}
                  </Badge>
                </div>
                <p class="mt-3 text-sm text-muted-foreground">
                  Import {{ repository.name }} as a managed repository and keep
                  GitHub as its source identity.
                </p>
              </button>
            </div>
          </div>
        </div>

        <div
          class="rounded-xl border border-border/70 bg-muted/40 px-4 py-3 space-y-2"
        >
          <div class="flex flex-wrap items-center justify-between gap-2">
            <p class="font-medium">
              {{ props.importProjectDisplayName ?? "Repository import status" }}
            </p>
            <Button
              v-if="props.importProjectPath"
              id="setup-github-repository-widget-open-repo"
              as="a"
              :href="props.importProjectPath"
              variant="outline"
              size="sm"
            >
              Open managed repo
            </Button>
          </div>
          <p
            id="setup-github-repository-widget-import-detail"
            class="text-sm text-foreground"
          >
            {{ props.importDetail }}
          </p>
          <p
            v-if="props.importRemediation"
            id="setup-github-repository-widget-import-remediation"
            class="text-sm text-accent-yellow"
          >
            {{ props.importRemediation }}
          </p>
          <p
            v-if="props.importErrorType"
            id="setup-github-repository-widget-import-error-type"
            class="text-xs uppercase tracking-[0.25em] text-muted-foreground"
          >
            {{ props.importErrorType }}
          </p>
        </div>
      </div>
    </div>
  </section>
</template>
