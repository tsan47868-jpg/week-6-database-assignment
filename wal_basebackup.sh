#!/usr/bin/env bash
set -e

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
su postgres -c "pg_basebackup -D /var/backups/base -Ft -z -Xs -P"

echo "--- backup dir ---"
ls -ld /var/backups /var/backups/wal

echo "--- generated files ---"
ls -l /var/backups

echo "--- config tail ---"
tail -n 20 /etc/postgresql/18/main/postgresql.conf
