#!/usr/bin/env bash
set -e

pg_ctlcluster 18 main start || true

if ! su postgres -c "psql -Atqc \"SELECT 1 FROM pg_database WHERE datname='bootcamp';\" postgres" | grep -q 1; then
  su postgres -c "createdb bootcamp"
fi

su postgres -c "psql -d bootcamp -v ON_ERROR_STOP=1 -c \"DROP TABLE IF EXISTS students; CREATE TABLE students (id serial PRIMARY KEY, name text NOT NULL); INSERT INTO students (name) VALUES ('Alice'), ('Bob'), ('Carol');\""

if ! grep -qF "wal_level = replica" /etc/postgresql/18/main/postgresql.conf; then
  echo "wal_level = replica" >> /etc/postgresql/18/main/postgresql.conf
fi

if ! grep -qF "archive_mode = on" /etc/postgresql/18/main/postgresql.conf; then
  echo "archive_mode = on" >> /etc/postgresql/18/main/postgresql.conf
fi

if ! grep -qF "archive_command = 'cp %p /var/backups/wal/%f'" /etc/postgresql/18/main/postgresql.conf; then
  echo "archive_command = 'cp %p /var/backups/wal/%f'" >> /etc/postgresql/18/main/postgresql.conf
fi

pg_ctlcluster 18 main restart
sleep 2

TS=$(su postgres -c "psql -d bootcamp -Atqc \"SELECT now();\"")
echo "TS=$TS"

su postgres -c "psql -d bootcamp -c \"DELETE FROM students;\""
su postgres -c "psql -d postgres -c \"SELECT pg_switch_wal();\""

mkdir -p /var/backups/wal /var/backups/recovery_base
rm -rf /var/backups/recovery_base/*
su postgres -c "pg_basebackup -D /var/backups/recovery_base -Ft -z -Xs -P"

rm -rf /var/lib/postgresql/18/recover_dir
mkdir -p /var/lib/postgresql/18/recover_dir
chown postgres:postgres /var/lib/postgresql/18/recover_dir
su postgres -c "tar -xzf /var/backups/recovery_base/base.tar.gz -C /var/lib/postgresql/18/recover_dir"
rm -f /var/lib/postgresql/18/recover_dir/postmaster.pid

printf "restore_command = 'cp /var/backups/wal/%%f %%p'\nrecovery_target_time = '%s'\n" "$TS" > /var/lib/postgresql/18/recover_dir/postgresql.auto.conf
touch /var/lib/postgresql/18/recover_dir/recovery.signal
chown postgres:postgres /var/lib/postgresql/18/recover_dir/recovery.signal

su postgres -c "pg_ctl -D /var/lib/postgresql/18/recover_dir -l /tmp/recover.log -o \"-p 5433\" -w start"
sleep 3
su postgres -c "psql -p 5433 -d bootcamp -Atqc \"SELECT count(*) FROM students;\""
