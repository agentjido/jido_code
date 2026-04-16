/**
 * LLM component hooks for Phoenix LiveView.
 *
 * Provides interactive behavior for:
 * - ModelSelector: Provider tab selection and model filtering
 * - ModelPicker: Dropdown model selection
 */

export const ModelSelector = {
  mounted() {
    this.el.addEventListener("js:select_provider", (e) => {
      this.handleProviderSelect(e.detail.provider);
    });

    // Initialize with selected provider if any
    const providerInput = this.el.querySelector(
      "input[type='hidden'][$id$='-provider-input']"
    );
    if (providerInput && providerInput.value) {
      this.handleProviderSelect(providerInput.value);
    }
  },

  updated() {
    // Re-attach event listeners after update
  },

  handleProviderSelect(provider) {
    const modelList = this.el.querySelector("[id$='-model-list']");
    if (!modelList) return;

    // Filter models by provider
    const allModels = this.el.querySelectorAll(".model-option");
    allModels.forEach((option) => {
      const modelProvider = option.dataset.provider;
      if (!provider || modelProvider === provider) {
        option.style.display = "";
      } else {
        option.style.display = "none";
      }
    });
  }
};

export const ModelPicker = {
  mounted() {
    // Handle dropdown behavior
    const dropdown = this.el;
    const toggle = dropdown.querySelector("label");

    if (toggle) {
      toggle.addEventListener("click", (e) => {
        e.stopPropagation();
        dropdown.classList.toggle("dropdown-open");
      });

      // Close dropdown when clicking outside
      document.addEventListener("click", (e) => {
        if (!dropdown.contains(e.target)) {
          dropdown.classList.remove("dropdown-open");
        }
      });
    }
  }
};

// Export all hooks as a single object for LiveView
export const getLLMHooks = () => ({
  ModelSelector,
  ModelPicker
});

export default { ModelSelector, ModelPicker };
