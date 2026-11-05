#!/usr/bin/env bash
set -e

service postgresql start || true

if ! su postgres -c "psql -Atqc 'SELECT 1 FROM pg_database WHERE datname='\''bootcamp'\'';' postgres" | grep -q 1; then
  su postgres -c "createdb bootcamp"
fi

su postgres -c "psql -d bootcamp -v ON_ERROR_STOP=1 -c \"DROP TABLE IF EXISTS students; CREATE TABLE students (id serial PRIMARY KEY, name text NOT NULL); INSERT INTO students (name) VALUES ('Alice'), ('Bob'), ('Carol');\""

mkdir -p /var/backups/wal
chown -R postgres:postgres /var/backups
rm -rf /var/backups/base

su postgres -c "pg_dump -Fc -f /var/backups/bootcamp.dump bootcamp"
echo "--- pg_restore list ---"
su postgres -c "pg_restore --list /var/backups/bootcamp.dump | head"

if ! su postgres -c "psql -Atqc 'SELECT 1 FROM pg_database WHERE datname='\''bootcamp_check'\'';' postgres" | grep -q 1; then
  su postgres -c "createdb bootcamp_check"
fi

su postgres -c "pg_restore -d bootcamp_check /var/backups/bootcamp.dump"
echo "--- counts ---"
su postgres -c "psql -d bootcamp -Atqc 'SELECT count(*) FROM students;'"
su postgres -c "psql -d bootcamp_check -Atqc 'SELECT count(*) FROM students;'"
