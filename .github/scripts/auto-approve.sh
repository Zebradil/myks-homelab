#!/usr/bin/env bash

set -euo pipefail

VALIDATION_MSG="Environment variable must be set"

: "${GITHUB_WORKSPACE:?$VALIDATION_MSG}"
: "${GITHUB_BASE_REF:?$VALIDATION_MSG}"
: "${GITHUB_HEAD_REF:?$VALIDATION_MSG}"
: "${PR_NUMBER:?$VALIDATION_MSG}"
: "${PR_STATE:?$VALIDATION_MSG}"
: "${PR_DRAFT:?$VALIDATION_MSG}"
# This is boolean, but also can be null, do not error on empty value
: "${PR_MERGEABLE?$VALIDATION_MSG}"

function gh_api() {
  gh api \
    --header "Accept: application/vnd.github+json" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

function get_approval_id() {
  user_id=$(gh api user --jq '.id')
  gh_api "/repos/{owner}/{repo}/pulls/$PR_NUMBER/reviews" \
    --jq ".[] | select(.user.id == $user_id and .state == \"APPROVED\") | .id"
}

function decide() {
  OK=🟢
  NO=🔴

  if [[ $PR_STATE == closed ]]; then
    echo "::notice::$NO Pull request is closed"
    return 1
  fi
  echo "::notice::$OK Pull request is open"

  if [[ $PR_DRAFT == true ]]; then
    echo "::notice::$NO Pull request is a draft"
    return 1
  fi
  echo "::notice::$OK Pull request is not a draft"

  if [[ $PR_MERGEABLE == false ]]; then
    echo "::notice::$NO Pull request is not mergeable"
    return 1
  fi
  echo "::notice::$OK Pull request is mergeable"

  export GIT_CONFIG_SYSTEM="$GITHUB_WORKSPACE/hack/git/gitconfig"
  gh pr checkout "$PR_NUMBER"
  # `git diff --exit-code` returns 1 even if the command returns no output. This is why changes are detected
  # by checking its output instead of its exit code.
  DIFF=$(git diff "origin/$GITHUB_BASE_REF...origin/$GITHUB_HEAD_REF" -- rendered)
  if [[ -n $DIFF ]]; then
    echo "::group::Diff"
    echo "$DIFF"
    echo "::endgroup::"
    echo "::notice::$NO Significant changes in rendered manifests"
    return 1
  fi
  echo "::notice::$OK No significant changes in rendered manifests"

  return 0
}

APPROVAL_ID=$(get_approval_id)

if decide; then
  echo "::notice::Approving the pull request..."
  if [[ -n $APPROVAL_ID ]]; then
    echo "::notice::Approval already exists, nothing to do"
  else
    gh pr review --approve --body "LGTM"
    echo "::notice::Approved!"
  fi
else
  echo "::notice::Dismissing the approval..."
  if [[ -n $APPROVAL_ID ]]; then
    gh_api --method PUT \
      "/repos/{owner}/{repo}/pulls/$PR_NUMBER/reviews/$APPROVAL_ID/dismissals" \
      --raw-field message="Review dismissed (TODO: add details)"
    echo "::notice::Dismissed!"
  else
    echo "::notice::No approval to dismiss"
  fi
fi
