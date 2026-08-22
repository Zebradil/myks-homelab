#!/usr/bin/env bash
# Audit (and optionally delete) orphan k8s-csi LUNs on the Synology NAS.
#
# The Synology storage classes use reclaimPolicy: Retain, so deleting a PVC or a PV never calls
# CSI DeleteVolume and the LUN plus its iSCSI target are left behind on the NAS forever. This
# finds those leftovers by matching LUN names against live PVs.
#
# Credentials come from the synology-csi client-info secret in the cluster, so it needs a working
# kubectl context. The DSM calls mirror pkg/dsm/webapi/iscsi.go in SynologyOpenSource/synology-csi.
#
# Read-only unless --delete is passed. Pass --insecure only if DSM serves a certificate that the
# local trust store cannot verify.
set -euo pipefail

DELETE=false
INSECURE=false
curl_opts=(--silent --show-error)

for arg in "$@"; do
  case "$arg" in
    --delete) DELETE=true ;;
    --insecure) INSECURE=true; curl_opts+=(--insecure) ;;
    *) echo "unknown argument: $arg (expected --delete and/or --insecure)" >&2; exit 1 ;;
  esac
done
[[ $INSECURE == false ]] || echo "warning: TLS verification disabled, DSM credentials are exposed to any MITM" >&2

cfg=$(kubectl get secret -n synology-csi client-info-secret \
        -o jsonpath='{.data.client-info\.yml}' | base64 -d)
host=$(yq -r '.clients[0].host' <<<"$cfg")
port=$(yq -r '.clients[0].port' <<<"$cfg")
user=$(yq -r '.clients[0].username' <<<"$cfg")
pass=$(yq -r '.clients[0].password' <<<"$cfg")
for field in host port user pass; do
  [[ -n ${!field} && ${!field} != "null" ]] || { echo "client-info secret has no $field" >&2; exit 1; }
done
scheme=$([[ "$(yq -r '.clients[0].https' <<<"$cfg")" == "true" ]] && echo https || echo http)
base="$scheme://$host:$port/webapi"

# Secrets travel over stdin and a 0600 config file: curl arguments are world-readable in `ps`.
resp=$(printf '%s' "$pass" | curl "${curl_opts[@]}" "$base/auth.cgi" \
         --data-urlencode "api=SYNO.API.Auth" --data-urlencode "method=login" \
         --data-urlencode "version=3" --data-urlencode "account=$user" \
         --data-urlencode "passwd@-" --data-urlencode "format=sid")
jq -e '.success' <<<"$resp" >/dev/null \
  || { echo "DSM login failed: $(jq -c '.error // .' <<<"$resp")" >&2; exit 1; }
sidcfg=$(mktemp) && chmod 600 "$sidcfg"
trap 'rm -f "$sidcfg"' EXIT
printf 'data-urlencode = "_sid=%s"\n' "$(jq -er '.data.sid' <<<"$resp")" >"$sidcfg"
trap 'curl "${curl_opts[@]}" "$base/auth.cgi" --config "$sidcfg" \
        --data-urlencode "api=SYNO.API.Auth" --data-urlencode "method=logout" \
        --data-urlencode "version=1" >/dev/null || true; rm -f "$sidcfg"' EXIT
unset resp pass

api() {
  local out
  out=$(curl "${curl_opts[@]}" "$base/entry.cgi" --config "$sidcfg" "$@")
  jq -e '.success' <<<"$out" >/dev/null \
    || { echo "DSM API error: $(jq -c '.error // .' <<<"$out")" >&2; return 1; }
  printf '%s' "$out"
}

list_targets() {
  api --data-urlencode "api=SYNO.Core.ISCSI.Target" --data-urlencode "method=list" \
      --data-urlencode "version=1" --data-urlencode 'additional=["mapped_lun","connected_sessions"]'
}

# The driver writes "<pvc-namespace>/<pvc-name>" into the LUN description, so it names the PVC an
# orphan came from. It is empty unless external-provisioner runs with --extra-create-metadata.
# The type list mirrors LunList() in the driver, so nothing is missed from the audit.
lun_list() {
  api --data-urlencode "api=SYNO.Core.ISCSI.LUN" --data-urlencode "method=list" \
      --data-urlencode "version=1" \
      --data-urlencode 'types=["BLOCK","FILE","THIN","ADV","SINK","CINDER","CINDER_BLUN","CINDER_BLUN_THICK","BLUN","BLUN_THICK","BLUN_SINK","BLUN_THICK_SINK"]' \
      --data-urlencode "additional=$1"
}

luns=$(lun_list '["status","description"]' 2>/dev/null) || {
  echo "note: DSM would not return the description field, listing without it" >&2
  luns=$(lun_list '["status"]')
}
targets=$(list_targets)

# A LUN is named k8s-csi-<pv-name>; with no matching PV in the cluster it is an orphan.
pvs=$(kubectl get pv -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | sort -u)
[[ -n $pvs ]] || { echo "kubectl listed no PVs; every LUN would look orphaned. Check the context." >&2; exit 1; }

# shellcheck disable=SC2016  # jq filter, $vars are jq's own and must not expand in the shell
report='
  ($pvs | split("\n")) as $live
  | ($t.data.targets // []) as $tg
  | .data.luns[]
  | select(.name | startswith("k8s-csi-")) | . as $l
  | (($l.name | ltrimstr("k8s-csi-")) as $pv | $live | index($pv) | not) as $orphan
  | ($tg | map(select(any(.mapped_luns[]?; .lun_uuid == $l.uuid)))) as $mine
  | (($mine | map(.connected_sessions | length) | add) // 0) as $sessions
'

jq -r --argjson t "$targets" --arg pvs "$pvs" "$report"'
  | [ (if $orphan then "ORPHAN" else "in-use" end), $l.name, $l.uuid,
      (($l.size/1073741824 | floor | tostring) + "Gi"), ($l.status // "-"),
      (($l.description // "") | if . == "" then "-" else . end),
      ("target=" + ($mine | map(.target_id | tostring) | join(",") | if . == "" then "none" else . end)),
      ("sessions=" + ($sessions | tostring)) ] | @tsv' <<<"$luns" \
  | sort | column -t -s$'\t'

[[ $DELETE == true ]] || { echo; echo "read-only. rerun with --delete to remove the ORPHAN rows"; exit 0; }

candidates=$(jq -r --argjson t "$targets" --arg pvs "$pvs" "$report"'
  | select($orphan and $sessions == 0)
  | [ $l.uuid, $l.name, (($l.description // "") | if . == "" then "-" else . end) ] | @tsv' <<<"$luns")
managed=$(jq -r '[.data.luns[] | select(.name | startswith("k8s-csi-"))] | length' <<<"$luns")
orphaned=$(jq -r --argjson t "$targets" --arg pvs "$pvs" "$report"' | select($orphan) | $l.uuid' <<<"$luns" | grep -c . || true)

# Every managed LUN reading as an orphan means the LUN-name-to-PV match broke (DSM truncating long
# names, say), not that the cluster lost every volume at once.
if (( managed > 0 && orphaned == managed )); then
  echo "all $managed k8s-csi LUNs look orphaned; the name/PV match is broken. Refusing to delete." >&2
  exit 1
fi
[[ -n $candidates ]] || { echo; echo "nothing to delete"; exit 0; }

echo
read -r -p "permanently delete $(grep -c . <<<"$candidates") LUN(s) and their data? type DELETE to confirm: " answer </dev/tty
[[ $answer == "DELETE" ]] || { echo "aborted"; exit 1; }

# Only drop a target if this LUN was its sole mapping, matching what the CSI driver's own
# DeleteVolume does. Sessions are re-read per LUN: the audit above is a snapshot and a pod can
# attach in between.
while IFS=$'\t' read -r uuid name description; do
  read -r sessions tids < <(jq -r --arg u "$uuid" '
    [ .data.targets[]? | select(any(.mapped_luns[]?; .lun_uuid == $u)) ] as $mine
    | [ (($mine | map(.connected_sessions | length) | add) // 0 | tostring),
        ($mine | map(select((.mapped_luns | length) == 1) | .target_id | tostring) | join(" ")) ]
    | @tsv' <<<"$(list_targets)")
  if [[ $sessions != "0" ]]; then
    echo "skipping LUN $name ($uuid) [$description]: $sessions active iSCSI session(s)"
    continue
  fi
  echo "deleting LUN $name ($uuid) [$description]"
  api --data-urlencode "api=SYNO.Core.ISCSI.LUN" --data-urlencode "method=delete" \
      --data-urlencode "version=1" --data-urlencode "uuid=\"$uuid\"" >/dev/null
  for tid in $tids; do
    echo "  deleting target $tid"
    api --data-urlencode "api=SYNO.Core.ISCSI.Target" --data-urlencode "method=delete" \
        --data-urlencode "version=1" --data-urlencode "target_id=\"$tid\"" >/dev/null
  done
done <<<"$candidates"
