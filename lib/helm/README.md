# Helm Chart Labels Removal Overlay

This directory contains overlay functions for removing Helm chart labels from
rendered Kubernetes manifests. These labels typically change with every Helm
chart version and can pollute git diffs. Since versions of manifest sources can
be tracked via ArgoCD and git, these labels provide little value while making
change tracking more difficult.

## What Labels Are Removed

The overlay removes the following Helm-related labels from various locations in
Kubernetes manifests:

- `chart`
- `helm.sh/chart`
- `app.kubernetes.io/version`
- `app.kubernetes.io/managed-by: Helm`

## Where Labels Are Removed From

The overlay functions handle labels in multiple locations:

1. Metadata labels (`metadata.labels`)
2. Spec selector match labels (`spec.selector.matchLabels`)
3. Simple spec selectors (`spec.selector`)
4. Pod template labels (`spec.template.metadata.labels`)

Additionally, the overlay will remove empty label objects to keep the manifests
clean.

## Usage

To remove Helm labels from your manifests, create a file in the `ytt` directory
of your prototype or application (e.g.,
`prototypes/your-package/ytt/unhelm.ytt.yaml`) with the following content:

````yaml
#@ load("@ytt:overlay", "overlay")
#@ load("/helm/remove-labels.lib.yaml", "apply_overlays")
#@overlay/match by=overlay.all, expects="1+"
--- #@overlay/replace via=apply_overlays
```

This overlay will be applied to all matching resources in your rendered
manifests, removing the specified Helm-related labels while preserving other
important labels.
````
