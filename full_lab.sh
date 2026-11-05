#!/usr/bin/env bash
set -e

mkdir -p /var/backups/wal /var/backups/base
chown -R postgres:postgres /var/backups

if ! su postgres -c "psql -Atqc \"SELECT 1 FROM pg_database WHERE datname='bootcamp';\" postgres" | grep -q 1; then
  su postgres -c "createdb bootcamp"
fi

su postgres -c "psql -d bootcamp -v ON_ERROR_STOP=1 -c \"DROP TABLE IF EXISTS students; CREATE TABLE students (id serial PRIMARY KEY, name text NOT NULL); INSERT INTO students (name) VALUES ('Alice'), ('Bob'), ('Carol');\""

su postgres -c "pg_dump -Fc -f /var/backups/bootcamp.dump bootcamp"
su postgres -c "pg_restore --list /var/backups/bootcamp.dump | head"

su postgres -c "dropdb --if-exists bootcamp_check"
if ! su postgres -c "psql -Atqc \"SELECT 1 FROM pg_database WHERE datname='bootcamp_check';\" postgres" | grep -q 1; then
  su postgres -c "createdb bootcamp_check"
fi

su postgres -c "pg_restore -d bootcamp_check /var/backups/bootcamp.dump"

if ! grep -qF "wal_level = replica" /etc/postgresql/18/main/postgresql.conf; then
  echo "wal_level = replica" >> /etc/postgresql/18/main/postgresql.conf
fi
if ! grep -qF "archive_mode = on" /etc/postgresql/18/main/postgresql.conf; then
  echo "archive_mode = on" >> /etc/postgresql/18/main/postgresql.conf
fi
if ! grep -qF "archive_command = 'cp %p /var/backups/wal/%f'" /etc/postgresql/18/main/postgresql.conf; then
  echo "archive_command = 'cp %p /var/backups/wal/%f'" >> /etc/postgresql/18/main/postgresql.conf
fi
if ! grep -qF "max_wal_senders = 10" /etc/postgresql/18/main/postgresql.conf; then
  echo "max_wal_senders = 10" >> /etc/postgresql/18/main/postgresql.conf
fi
if ! grep -qF "wal_keep_size = 1GB" /etc/postgresql/18/main/postgresql.conf; then
  echo "wal_keep_size = 1GB" >> /etc/postgresql/18/main/postgresql.conf
fi

pg_ctlcluster 18 main restart
sleep 2

rm -rf /var/backups/base
mkdir -p /var/backups/base /var/backups/wal
chown -R postgres:postgres /var/backups
su postgres -c "/usr/lib/postgresql/18/bin/pg_basebackup -D /var/backups/base -Ft -z -Xs -P"

TS=$(su postgres -c "psql -d bootcamp -Atqc \"SELECT now();\"")

echo "TARGET_TS=$TS"

su postgres -c "psql -d bootcamp -c \"DELETE FROM students;\""
su postgres -c "psql -d postgres -c \"SELECT pg_switch_wal();\""

rm -rf /var/lib/postgresql/18/recover
mkdir -p /var/lib/postgresql/18/recover
chown postgres:postgres /var/lib/postgresql/18/recover
su postgres -c "tar -xzf /var/backups/base/base.tar.gz -C /var/lib/postgresql/18/recover"
chmod 700 /var/lib/postgresql/18/recover
find /var/lib/postgresql/18/recover -type d -exec chmod 700 {} +
chown -R postgres:postgres /var/lib/postgresql/18/recover
if [ -f /var/backups/base/pg_wal.tar.gz ]; then
  su postgres -c "tar -xzf /var/backups/base/pg_wal.tar.gz -C /var/lib/postgresql/18/recover"
fi
cat > /var/lib/postgresql/18/recover/postgresql.conf <<EOF
listen_addresses = '127.0.0.1'
port = 5433
unix_socket_directories = '/var/run/postgresql'
shared_buffers = 128MB
wal_level = replica
archive_mode = on
archive_command = 'cp %p /var/backups/wal/%f'
restore_command = 'cp /var/backups/wal/%f %p'
recovery_target_time = '$TS'
max_wal_senders = 10
wal_keep_size = 1GB
EOF
cp /etc/postgresql/18/main/pg_hba.conf /var/lib/postgresql/18/recover/pg_hba.conf
mkdir -p /var/lib/postgresql/18/recover/conf.d
chown -R postgres:postgres /var/lib/postgresql/18/recover
rm -f /var/lib/postgresql/18/recover/postmaster.pid
: > /var/lib/postgresql/18/recover/recovery.signal
chown postgres:postgres /var/lib/postgresql/18/recover/recovery.signal
su postgres -c "/usr/lib/postgresql/18/bin/pg_ctl -D /var/lib/postgresql/18/recover -l /tmp/recover.log -o \"-p 5433 -c config_file=/var/lib/postgresql/18/recover/postgresql.conf\" -w start"
sleep 5
su postgres -c "/usr/lib/postgresql/18/bin/psql -p 5433 -d bootcamp -Atqc \"SELECT count(*) FROM students;\""

# Standby setup
if ! su postgres -c "psql -d postgres -Atqc \"SELECT 1 FROM pg_roles WHERE rolname='replicator';\"" | grep -q 1; then
  su postgres -c "psql -d postgres -c \"CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'reppass';\""
fi

if ! grep -qF "host replication replicator 127.0.0.1/32 md5" /etc/postgresql/18/main/pg_hba.conf; then
  echo "host replication replicator 127.0.0.1/32 md5" >> /etc/postgresql/18/main/pg_hba.conf
fi

pg_ctlcluster 18 main reload

rm -rf /var/lib/postgresql/18/standby
mkdir -p /var/lib/postgresql/18/standby
chown postgres:postgres /var/lib/postgresql/18/standby
su postgres -c "/usr/lib/postgresql/18/bin/pg_basebackup -h 127.0.0.1 -U replicator -D /var/lib/postgresql/18/standby -R -P"
chown -R postgres:postgres /var/lib/postgresql/18/standby
su postgres -c "/usr/lib/postgresql/18/bin/pg_ctl -D /var/lib/postgresql/18/standby -l /tmp/standby.log -o \"-p 5434\" -w start"
sleep 5
su postgres -c "/usr/lib/postgresql/18/bin/psql -d postgres -Atqc \"SELECT application_name, state, pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes FROM pg_stat_replication;\""
