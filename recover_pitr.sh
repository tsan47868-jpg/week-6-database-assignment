#!/usr/bin/env bash
set -e

TARGET_TS=$(su postgres -c "psql -Atqc 'SELECT now();' bootcamp")
echo "TARGET_TS=${TARGET_TS}"

su postgres -c "psql -d bootcamp -c 'DELETE FROM students;'"

pg_ctlcluster 18 main stop

if [ -d /var/lib/postgresql/18/main ]; then
  mv /var/lib/postgresql/18/main /var/lib/postgresql/18/main_broken
fi

cp -a /var/backups/base/. /var/lib/postgresql/18/main/
chown -R postgres:postgres /var/lib/postgresql/18/main

cat > /etc/postgresql/18/main/postgresql.auto.conf <<EOF
restore_command = 'cp /var/backups/wal/%f %p'
recovery_target_time = '${TARGET_TS}'
EOF

# ensure recovery is enabled in a fresh data directory
: > /var/lib/postgresql/18/main/recovery.signal
chown postgres:postgres /var/lib/postgresql/18/main/recovery.signal

pg_ctlcluster 18 main start
sleep 5
su postgres -c "psql -d bootcamp -Atqc 'SELECT count(*) FROM students;'"
