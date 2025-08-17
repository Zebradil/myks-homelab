# Paperless-ng : myks prototype

## Postgres upgrade

Upgrading Postgres between major versions requires manual intervention.
Here are the steps:

1. Make sure the database is not accessed:
   ```shell
   kubectl scale --replicas=0 --namespace paperless deployment/paperless
   ```
2. Enter the running postgresql container and make a dump of the database:
   ```shell
   kubectl exec -it --namespace paperless postgresql-0 -- bash
   cd /bitnami/postgresql
   PGASSWORD=$(cat $POSTGRES_POSTGRES_PASSWORD_FILE) pg_dumpall -U $POSTGRES_USER \
     > dump-$(cat data/PG_VERSION)-$(date +%Y%m%d-%H%M%S).sql
   ```
   Exit the container.
3. Now you need to stop the postgresql process and remove the old data directory.
   To do this, patche the statefulset to use a custom wait command:
   ```shell
    kubectl patch statefulset postgresql \
      --namespace paperless \
      --type=merge \
      --patch '{"spec":{"template":{"spec":{"containers":[{"name":"postgresql","command":["bash","-c","tail -f /dev/null"]}]}}}}'
   ```
4. Delete the existing pod to trigger a new one with the patched command:
   ```shell
   kubectl delete pod --namespace paperless postgresql-0
   ```
5. Now you can enter the new pod and remove the old data directory:
   ```shell
   kubectl exec -it --namespace paperless postgresql-0 -- bash
   cd /bitnami/postgresql
   mv data data-$(cat PG_VERSION)-$(date +%Y%m%d-%H%M%S)
   ```
   Exit the container.
6. Update the postgresql image to the new version in the statefulset and remove the command:
   ```shell
   kubectl patch statefulset postgresql \
     --namespace paperless \
     --type=json \
     --patch '[{"op": "remove", "path": "/spec/template/spec/containers/0/command"},
         {"op": "replace", "path": "/spec/template/spec/containers/0/image",
           "value": "docker.io/bitnami/postgresql:<NEW_VERSION>"}]'
   ```
   Replace `NEW_VERSION` with the desired version.
7. Delete the existing pod to trigger a new one with the original command:
   ```shell
   kubectl delete pod --namespace paperless postgresql-0
   ```
8. Now you can enter the new pod and restore the database from the dump:
   ```shell
   kubectl exec -it --namespace paperless postgresql-0 -- bash
   cd /bitnami/postgresql
   PGPASSWORD=$(cat $POSTGRES_POSTGRES_PASSWORD_FILE) psql -U $POSTGRES_USER \
     -f <PATH_TO_DUMP_FILE>
   ```
   Replace `<PATH_TO_DUMP_FILE>` with the path to the dump file you created earlier
9. Finally, scale the paperless deployment back up:
   ```shell
   kubectl scale --replicas=1 --namespace paperless deployment/paperless
   ```
