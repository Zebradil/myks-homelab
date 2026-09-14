# harbor

## Backup

`ytt/backup.ytt.yaml` dumps the `registry` database nightly with `lib/_ytt_lib/backup`. A snapshot holds a single file,
`/backup/registry.sql`. Credentials and the restic password live in `static/backup.sops.yaml`.

Registry blobs, Redis and Trivy are not backed up: blobs are mostly upstream-cache content that can be pulled again,
and the other two are disposable.

### Checking a backup

With the restic environment exported (see `lib/_ytt_lib/backup/README.md`):

```bash
restic snapshots --host harbor
restic dump latest --host harbor /backup/registry.sql | rg -c '^COPY '
```

### Restoring

The dump is plain SQL without `CREATE DATABASE`, so it goes into an empty `registry` database:

1. Stop everything connected to the database, otherwise `DROP DATABASE` fails:

   ```bash
   kubectl -n harbor scale deployment harbor-core harbor-jobservice harbor-exporter --replicas=0
   ```

2. Recreate the database and load the dump:

   ```bash
   restic dump latest --host harbor /backup/registry.sql > registry.sql
   kubectl -n harbor exec -i harbor-database-0 -- psql -U postgres -c 'DROP DATABASE registry' -c 'CREATE DATABASE registry'
   kubectl -n harbor exec -i harbor-database-0 -- psql -U postgres -d registry -v ON_ERROR_STOP=1 < registry.sql
   ```

3. Scale `harbor-core`, `harbor-jobservice` and `harbor-exporter` back up.
