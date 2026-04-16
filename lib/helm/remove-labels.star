load("@ytt:struct", "struct")
load("/util.star", "deep_check")

def managed_by_helm(i, l, r):
  return i == "app.kubernetes.io/managed-by" \
    and l == "Helm"
end

def metadata_labels(i, l, r):
  return i == "metadata" \
    and deep_check(l, "labels")
end

def spec_selector_labels(i, l, r):
  return i == "spec" \
    and deep_check(l, "selector", "matchLabels")
end

def spec_simple_selector_labels(i, l, r):
  return i == "spec" \
    and deep_check(l, "selector")
end

def spec_template_labels(i, l, r):
  return i == "spec" \
    and deep_check(l, "template", "metadata", "labels")
end

m = struct.make(
  managed_by_helm=managed_by_helm,
  metadata_labels=metadata_labels,
  spec_selector_labels=spec_selector_labels,
  spec_simple_selector_labels=spec_simple_selector_labels,
  spec_template_labels=spec_template_labels,
)
