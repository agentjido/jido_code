# covers: package.jido_code.version_controlled_quality_surfaces
%Doctor.Config{
  ignore_modules: [
    ~r/^JidoCode\.Folio\..*\.Jido\./
  ],
  ignore_paths: [],
  min_module_doc_coverage: 0,
  min_module_spec_coverage: 0,
  min_overall_doc_coverage: 60,
  min_overall_moduledoc_coverage: 80,
  min_overall_spec_coverage: 80,
  exception_moduledoc_required: false,
  raise: false,
  reporter: Doctor.Reporters.Full,
  struct_type_spec_required: false,
  umbrella: false
}
