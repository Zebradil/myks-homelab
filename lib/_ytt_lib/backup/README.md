# backup

Nightly restic backup of one app to S3-compatible storage, as a `backup` CronJob plus its `backup` Secret.

The pod runs three steps in order:

1. `dump` (supplied by the app) writes a consistent copy of whatever can't be copied live — a SQLite `VACUUM INTO`, a
   `pg_dump`, an exporter — into the `/backup` emptyDir.
2. `backup` runs `restic backup /backup <paths>`, where `paths` are volumes that are safe to copy file by file.
3. `forget` applies the retention policy and prunes.

A failed run fires `KubeJobFailed`; no successful run for 36h fires `BackupStale`
(`prototypes/victoria-metrics-k8s-stack/ytt/backup-rules.ytt.yaml`). Both rely on the CronJob being named `backup`.

## Adding an app

Each app gets its own restic repository, password and bucket-scoped S3 key, so one compromised namespace exposes only
its own backups.

1. Create `static/backup.sops.yaml` in the app with `restic-repository` (`s3:https://<endpoint>/<bucket>/<app>`),
   `restic-password`, `aws-access-key-id` and `aws-secret-access-key`. Keep a copy of the password outside the cluster
   and outside Vaultwarden.
2. Initialise the repository once from a workstation; the job does not create it:

   ```bash
   eval "$(sops decrypt static/backup.sops.yaml | yq -r '
     "export RESTIC_REPOSITORY=\(."restic-repository" | @sh) RESTIC_PASSWORD=\(."restic-password" | @sh)
       AWS_ACCESS_KEY_ID=\(."aws-access-key-id" | @sh) AWS_SECRET_ACCESS_KEY=\(."aws-secret-access-key" | @sh)"')"
   restic init
   ```

3. Call the library from the app's ytt, see `prototypes/vaultwarden/ytt/backup.ytt.yaml`. Keys the schema types as
   `any` (`secretEnv`, `dump`, `affinityPodLabels`, `podSecurityContext`) need `#@overlay/replace`.
4. Trigger a first run with `kubectl -n <app> create job --from=cronjob/backup backup-manual` and check
   `restic snapshots`.

RWO volumes can only be mounted on the node that already runs the app, so pass the app's pod labels as
`affinityPodLabels`. While the app is scaled down the job can't be scheduled and fails after an hour.
