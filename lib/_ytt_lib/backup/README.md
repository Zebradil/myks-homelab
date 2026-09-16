# backup

Nightly restic backup of one app to S3-compatible storage, as a `backup` CronJob plus its `backup` Secret.

The pod runs four steps in order, each of them a hard failure:

1. `dump` (supplied by the app) writes a consistent copy of whatever can't be copied live — a SQLite `VACUUM INTO`, a
   `pg_dump`, an exporter — into the `/backup` emptyDir.
2. `backup` runs `restic backup /backup <paths>`, where `paths` are volumes that are safe to copy file by file.
3. `forget` applies the retention policy and prunes, repacking at most `maxRepackSize` per run.
4. `check` verifies `checkReadDataSubset` of the pack files against their hashes, so bit rot surfaces before a
   restore does rather than during one.

A failed run fires `KubeJobFailed`; no successful run for 36h fires `BackupStale`; a missing CronJob fires
`BackupMissing` (`prototypes/victoria-metrics-k8s-stack/ytt/backup-rules.ytt.yaml`). The first two rely on the CronJob
being named `backup`, the third on the app's namespace being listed in that file.

## Choosing the storage

The credentials in the cluster can delete snapshots, because `forget --prune` runs next to `backup`. Anything that
compromises the app's namespace can therefore destroy its backups as well as read them, and the same age keys decrypt
both the cluster secrets and `backup.sops.yaml`. Pick a provider that can enforce retention on the bucket — object
versioning plus object lock in governance or compliance mode, covering at least the 12 months the retention policy
keeps — so a delete issued with the cluster's key is a tombstone rather than data loss. Without that this is a second
copy, not a recovery guarantee.

## Adding an app

Each app gets its own restic repository, password and bucket-scoped S3 key, so one compromised namespace exposes only
its own backups.

1. Create `static/backup.sops.yaml` in the app with `restic-repository` (`s3:https://<endpoint>/<bucket>/<app>`),
   `restic-password`, `aws-access-key-id` and `aws-secret-access-key`. Store the password wherever the age private key
   is kept: it has to survive the cluster, and it must not live in Vaultwarden, which is one of the things being
   backed up.
2. Initialise the repository once from a workstation; the job does not create it:

   ```bash
   eval "$(sops decrypt static/backup.sops.yaml | yq -r '
     "export RESTIC_REPOSITORY=\(."restic-repository" | @sh) RESTIC_PASSWORD=\(."restic-password" | @sh)
       AWS_ACCESS_KEY_ID=\(."aws-access-key-id" | @sh) AWS_SECRET_ACCESS_KEY=\(."aws-secret-access-key" | @sh)"')"
   restic init
   ```

3. Call the library from the app's ytt, see `prototypes/vaultwarden/ytt/backup.ytt.yaml`. Keys the schema types as
   `any` (`secretEnv`, `dump`, `affinityPodLabels`, `podSecurityContext`) need `#@overlay/replace`. A
   `podSecurityContext` that sets `runAsUser` has to set `fsGroup` too, or restic cannot write its cache emptyDir.
4. Add the namespace to `backed_up` in `prototypes/victoria-metrics-k8s-stack/ytt/backup-rules.ytt.yaml`.
5. Trigger a first run with `kubectl -n <app> create job --from=cronjob/backup backup-manual` and check
   `restic snapshots`.

## Sizing

The defaults are set for an app the size of Vaultwarden. For anything larger, raise `timeoutSeconds` to cover the
first full backup — it bounds the whole run, not just the wait for a node, and a job that outgrows it fails every
night — and `scratchSizeLimit` to fit the dump, which is held on the node's disk. `maxRepackSize` and
`checkReadDataSubset` trade nightly egress against how fast garbage is reclaimed and the repository verified.

RWO volumes can only be mounted on the node that already runs the app, so pass the app's pod labels as
`affinityPodLabels`. While the app is scaled down the job can't be scheduled and fails once `timeoutSeconds` is up.
