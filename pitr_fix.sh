#!/usr/bin/env bash
set -e

if [ -d /var/lib/postgresql/18/main ]; then
  if [ -d /var/lib/postgresql/18/main_tar ]; then
    rm -rf /var/lib/postgresql/18/main_tar
  fi
  mv /var/lib/postgresql/18/main /var/lib/postgresql/18/main_tar
fi

mkdir -p /var/lib/postgresql/18/main
chown postgres:postgres /var/lib/postgresql/18/main

tar -xzf /var/lib/postgresql/18/main_tar/base.tar.gz -C /var/lib/postgresql/18/main

echo "restore_command = 'cp /var/backups/wal/%f %p'" > /etc/postgresql/18/main/postgresql.auto.conf
# use the timestamp captured before the simulated delete
printf "recovery_target_time = '%s'\n" "2026-11-05 10:06:23.151841+03" >> /etc/postgresql/18/main/postgresql.auto.conf

# ensure PostgreSQL starts in recovery mode
: > /var/lib/postgresql/18/main/recovery.signal
chown postgres:postgres /var/lib/postgresql/18/main/recovery.signal

pg_ctlcluster 18 main start
sleep 5
su postgres -c "psql -d bootcamp -Atqc 'SELECT count(*) FROM students;'"
