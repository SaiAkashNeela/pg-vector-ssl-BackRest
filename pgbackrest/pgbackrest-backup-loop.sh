#!/bin/sh
# Runs beside the primary (as the postgres user): creates the pgBackRest stanza
# once Postgres is up, then keeps base backups fresh -- a full one a week, a
# differential the other days. WAL in between is archived continuously by
# archive_command, so any moment since the oldest kept full can be restored.
# Backup age is read from the repository rather than a timer, so frequent
# restarts (every deploy) neither skip nor repeat backups. A base backup reads
# the whole database, so scheduled ones start only in one UTC hour,
# PGBACKREST_BACKUP_HOUR (default 21), to keep that I/O away from busy times;
# only the very first backup, which recovery cannot do without, starts
# straight away.
#
# Start it beside postgres, as the postgres user, once archiving is configured:
#   ( gosu postgres /usr/local/bin/pgbackrest-backup-loop.sh & )
set -u

# 0-23; a leading zero is dropped first, since printf reads "08" as octal.
backup_hour=${PGBACKREST_BACKUP_HOUR:-21}
backup_hour=$(printf '%02d' "${backup_hour#0}")

log() { echo "[pgbackrest] $*"; }

until pg_isready -q -h /var/run/postgresql; do sleep 5; done
# Idempotent: succeeds when the stanza already exists and matches this cluster.
until pgbackrest stanza-create; do
  log "stanza-create failed; retrying in a minute"
  sleep 60
done

while true; do
  info=$(pgbackrest info --output=json 2>/dev/null)
  now=$(date +%s)
  last_full=$(echo "$info" | jq '[.[0].backup[]? | select(.type == "full") | .timestamp.stop] | max // 0' 2>/dev/null)
  last_any=$(echo "$info" | jq '[.[0].backup[]? | .timestamp.stop] | max // 0' 2>/dev/null)
  last_full=${last_full:-0}
  last_any=${last_any:-0}
  if [ "$last_any" -ne 0 ] && [ "$(date -u +%H)" != "$backup_hour" ]; then
    sleep 3600
    continue
  fi
  # Thresholds sit below a day / a week: the hourly check drifts by minutes,
  # and must not miss the one backup-hour window it gets each day.
  if [ $((now - last_full)) -ge 561600 ]; then
    log "starting full backup"
    pgbackrest --type=full backup || log "full backup failed"
  elif [ $((now - last_any)) -ge 72000 ]; then
    log "starting differential backup"
    pgbackrest --type=diff backup || log "differential backup failed"
  fi
  sleep 3600
done
