# vaultwarden

## Backup

`ytt/backup.ytt.yaml` backs up the `data` PVC nightly with `lib/_ytt_lib/backup`. A snapshot contains:

- `/backup/db.sqlite3` — consistent copy of the database made by `vaultwarden backup`
- `/data/...` — RSA keys, `config.json`, attachments and sends; the live `db.sqlite3*` and `icon_cache` are excluded

Credentials and the restic password live in `static/backup.sops.yaml`.

### Checking a backup

With the restic environment exported (see `lib/_ytt_lib/backup/README.md`):

```bash
restic snapshots --host vaultwarden
restic dump latest --host vaultwarden /backup/db.sqlite3 > db.sqlite3
sqlite3 db.sqlite3 'PRAGMA integrity_check; SELECT count(*) FROM ciphers;'
```

### Restoring

1. Stop the app, so the PVC is free and the database is not written during the restore. ArgoCD self-heal is off, so the
   scale-down sticks:

   ```bash
   kubectl -n vaultwarden scale deployment vaultwarden --replicas=0
   ```

2. Restore the snapshot into the PVC and put the database copy in place:

   ```bash
   kubectl -n vaultwarden apply -f - <<'EOF'
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: restore
   spec:
     backoffLimit: 0
     template:
       spec:
         restartPolicy: Never
         securityContext: {runAsUser: 1000, runAsGroup: 1000, runAsNonRoot: true, fsGroup: 1000}
         containers:
           - name: restore
             image: restic/restic:0.19.1
             command: [/bin/sh, -c]
             args:
               - |
                 set -eu
                 restic restore latest --host vaultwarden --target /tmp/restore
                 cp -a /tmp/restore/data/. /data/
                 cp /tmp/restore/backup/db.sqlite3 /data/db.sqlite3
                 rm -f /data/db.sqlite3-wal /data/db.sqlite3-shm
             env: [{name: RESTIC_CACHE_DIR, value: /tmp/cache}]
             envFrom: [{secretRef: {name: backup}}]
             volumeMounts:
               - {name: data, mountPath: /data}
               - {name: tmp, mountPath: /tmp}
         volumes:
           - {name: data, persistentVolumeClaim: {claimName: data}}
           - {name: tmp, emptyDir: {}}
   EOF
   kubectl -n vaultwarden wait --for=condition=complete job/restore --timeout=10m
   kubectl -n vaultwarden delete job restore
   ```

3. Start the app again with `kubectl -n vaultwarden scale deployment vaultwarden --replicas=1`.

Restoring into an empty PVC works the same way. `restic restore` overwrites files but does not delete ones missing from
the snapshot.
