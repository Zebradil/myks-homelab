#!/usr/bin/env bash

# This script is used to ignore version changes in git diff.
# It replaces values of specific fields in the given file with a placeholder.
# Add more fields to the list if needed.

yq '(.metadata.labels | select(has("app.kubernetes.io/version"))                           | .["app.kubernetes.io/version"]) = "dummy" |
    (.metadata.labels | select(has("helm.sh/chart"))                                       | .["helm.sh/chart"])             = "dummy" |
    (.spec.template.spec.containers[]                                                      | .image)                         = "dummy" |
    (.spec.template.spec.initContainers[]                                                  | .image)                         = "dummy" |
    (.spec.template.metadata.labels | select(has("app.kubernetes.io/version"))             | .["app.kubernetes.io/version"]) = "dummy" |
    (.spec.template.metadata.labels | select(has("chart"))                                 | .["chart"])                     = "dummy" |
    (.spec.template.metadata.labels | select(has("helm.sh/chart"))                         | .["helm.sh/chart"])             = "dummy" |
    (.metadata.labels | select(has("chart"))                                               | .["chart"])                     = "dummy"' \
  "$1"
