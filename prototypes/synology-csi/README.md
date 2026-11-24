# synology-csi

Synology CSI driver (upstream `deploy/kubernetes/v1.20` manifests, vendored) plus monitoring for the connection between
the driver and DSM. Storage classes and DSM credentials live in `envs/alpha/_apps/synology-csi/`.

## DSM TLS

The driver logs in to DSM over HTTPS and verifies the certificate. The DSM certificate is signed by DSM's built-in
`Synology Inc. CA` and carries only `DNS:synology`, while the client connects by IP. That is why the client config pins
both `tlsCACert` and `tlsServerName: synology`.

The pinned CA and the served certificate both expire on **2027-06-24**, and DSM regenerates them on some upgrades. When
that happens, CSI logins fail, volume lookups return `NotFound`, and every pod that needs a fresh mount stays in
`ContainerCreating`. Harbor is one of them, so image pulls break cluster-wide. #975 tracks replacing the pinned CA with a
publicly trusted, auto-renewing certificate.

## Monitoring

`ytt/dsm-monitoring.ytt.yaml` adds:

- **blackbox-exporter** with one module per entry in `application.clients`. Each module does a TLS handshake with the
  client's own `ca`, `server_name` and `insecure_skip_verify`, so the probe fails exactly when CSI logins would fail on
  TLS. Changing the client settings updates the probe too.
- **Sidecar metrics.** `--http-endpoint` on csi-provisioner (`:9820`) and csi-attacher (`:9821`), scraped by a
  `VMPodScrape`. The controller runs with `hostNetwork`, so these ports are opened on the node itself.

| Alert                          | Severity | Fires when                                                              |
| ------------------------------ | -------- | ----------------------------------------------------------------------- |
| `DsmTlsProbeFailed`            | critical | the TLS handshake fails, or the exporter is down, for 5m                |
| `SynologyCsiOperationsFailing` | critical | the controller keeps getting non-`OK` gRPC codes for 15m                |
| `DsmCertificateExpiringSoon`   | warning  | the served certificate chain expires in under 14 days                   |

An occasional non-`OK` code is normal (e.g. `NotFound` when unpublishing an already deleted volume), hence the long
`for` on `SynologyCsiOperationsFailing`.

To check that data is arriving, query in vmui:

```promql
probe_success{job="dsm-tls"}
csi_sidecar_operations_seconds_count{driver_name="csi.san.synology.com"}
```

## Refreshing the pinned CA

The CA cannot be read from the TLS handshake: DSM sends only the leaf certificate. It has to be exported from DSM.

1. In DSM, open **Control Panel → Security → Certificate**, select the default certificate, and choose **Export
   certificate**. The archive should contain the CA as `syno-ca-cert.pem`, next to `cert.pem` and `privkey.pem`. The
   file names are unverified; if they differ, the CA is the certificate whose subject is `Synology Inc. CA`. **Never
   commit `privkey.pem`.**

2. Check that the exported CA signs what DSM currently serves, for the name the client verifies:

   ```bash
   openssl s_client -connect 192.168.0.30:5001 </dev/null 2>/dev/null | openssl x509 > leaf.pem
   openssl verify -CAfile syno-ca-cert.pem -verify_hostname synology leaf.pem   # expect: leaf.pem: OK
   openssl x509 -in syno-ca-cert.pem -noout -enddate
   ```

   macOS ships LibreSSL, which lacks `-verify_hostname`; use `nix shell nixpkgs#openssl` instead.

3. Replace `tlsCACert` in `envs/alpha/_apps/synology-csi/app-data.ytt.yaml`, run `myks render alpha synology-csi`, and
   open a PR. The probe picks up the new CA from the same values.

## Removing orphaned LUNs

All storage classes use `reclaimPolicy: Retain`. Deleting a PVC leaves its PV in `Released`, and deleting that PV
leaves the LUN and its iSCSI target on DSM, still taking space. Nothing in the cluster points at them any more, so they
have to be found and deleted on DSM.

A LUN's `uuid` is its PV's `spec.csi.volumeHandle`. The driver names the LUN and the target `k8s-csi-<pv name>` and sets
the LUN description to `<namespace>/<pvc>`. Match by UUID, not by name: a LUN is orphaned when no PV carries its UUID.
Delete any `Released` PVs you mean to drop first, since they still count as references.

1. On a workstation, record the LUNs and targets still in use:

   ```bash
   kubectl get pv -o json | jq -r '.items[] | select(.spec.csi.driver=="csi.san.synology.com") | .spec.csi.volumeHandle' > handles.txt
   kubectl get pv -o json | jq -r '.items[] | select(.spec.csi.driver=="csi.san.synology.com") | .metadata.name' > pv-names.txt
   ```

2. In an admin shell on the NAS, list LUNs and targets. `synowebapi` needs root, and its first output line is a log
   line, hence the `sed`:

   ```bash
   sudo synowebapi --exec api=SYNO.Core.ISCSI.LUN method=list version=1 > luns.json 2>&1
   sudo synowebapi --exec api=SYNO.Core.ISCSI.Target method=list version=1 \
     additional='["mapped_lun","connected_sessions"]' > targets.json 2>&1
   sed -i 1d luns.json targets.json
   ```

3. Copy both files next to the workstation lists and find the orphans:

   ```bash
   jq -r --rawfile h handles.txt '($h | split("\n")) as $hs | .data.luns[]
     | select(.uuid as $u | $hs | index($u) | not)
     | [.uuid, .name, .description, "\(.size / 1073741824 | floor)G"] | @tsv' luns.json
   jq -r --rawfile n pv-names.txt '($n | split("\n")) as $ns | .data.targets[]
     | (.name | sub("^k8s-csi-"; "")) as $pv | select($ns | index($pv) | not)
     | [.target_id, .name, ((.mapped_luns // []) | map(.lun_uuid) | join(",")), "sessions=\(.connected_sessions | length)"]
     | @tsv' targets.json
   ```

   Check the description of each LUN listed, and that every target listed has `sessions=0`. A target may have no LUN
   left; it is deleted the same way.

4. Delete each target, then its LUN. Deleting the target also removes the mapping. Both IDs are JSON strings, hence
   the inner quotes:

   ```bash
   sudo synowebapi --exec api=SYNO.Core.ISCSI.Target method=delete version=1 target_id='"<target_id>"'
   sudo synowebapi --exec api=SYNO.Core.ISCSI.LUN method=delete version=1 uuid='"<uuid>"'
   ```

   Each call prints `"success" : true`. This cannot be undone.

5. Repeat steps 2 and 3: both lists should come back empty, with one LUN and one target per PV.

## Testing the alert with an invalid CA

Do not put an invalid CA into `tlsCACert`: that breaks real CSI logins, which is the outage this alert exists for.
Editing the live blackbox ConfigMap does not work either, because ArgoCD self-heal reverts it within seconds.

`test/` holds a separate probe that ArgoCD does not manage. It uses `test/invalid-ca.pem`, a throwaway self-signed CA
with the same organisation as the DSM one. Its series share `job="dsm-tls"`, so the real `DsmTlsProbeFailed` rule
applies, and they carry `test="invalid-ca"` so they stay separate from the real probe.

1. Check locally that the CA is rejected:

   ```bash
   openssl verify -CAfile prototypes/synology-csi/test/invalid-ca.pem -verify_hostname synology leaf.pem
   # expect: error 20 at 0 depth lookup: unable to get local issuer certificate
   ```

2. Deploy the test probe:

   ```bash
   kubectl apply -k prototypes/synology-csi/test
   ```

3. `probe_success{job="dsm-tls", test="invalid-ca"}` should drop to `0` after one scrape. The exporter logs
   `x509: certificate signed by unknown authority`.

4. After 5 minutes, `DsmTlsProbeFailed` with `test="invalid-ca"` fires. It is critical, so it pages the high-severity
   Telegram topic.

5. Clean up:

   ```bash
   kubectl delete -k prototypes/synology-csi/test
   ```

To regenerate the test CA:

```bash
openssl req -x509 -newkey rsa:2048 -nodes -keyout /dev/null -days 36500 \
  -subj "/C=TW/L=Taipel/O=Synology Inc./CN=Synology Inc. CA (invalid, for alert tests)" \
  -out prototypes/synology-csi/test/invalid-ca.pem
```
