# Hands‑On Lab: Backups, Point‑in‑Time Recovery, and Replication

# Description

# Objective:
Take a logical backup, configure WAL archiving, perform a point‑in‑time recovery (PITR) after a simulated disaster, and set up a streaming standby replica.

What You Will Do:

Create and verify a logical backup
Configure WAL archiving and take a base backup
Recover a database to an exact point in time
Build and monitor a streaming replication standby

# Instructions:

Read each command carefully before running it
Perform steps in the given order
Treat this lab as both a prevention and recovery exercise

Step 1: Take and Verify a Logical Backup

Back up the bootcamp database and confirm that it can be restored successfully.

mkdir -p ~/backups
pg_dump -Fc -f ~/backups/bootcamp.dump bootcamp
pg_restore --list ~/backups/bootcamp.dump | head
createdb bootcamp_check && pg_restore -d bootcamp_check ~/backups/bootcamp.dump

  

Step 2: Enable WAL Archiving

Configure PostgreSQL to archive WAL files and take a base backup.

 </>Apache Config

# In postgresql.conf:
wal_level = replica
archive_mode = on
archive_command = 'cp %p /home/$USER/backups/wal/%f'



mkdir -p ~/backups/wal
sudo systemctl restart postgresql
pg_basebackup -D ~/backups/base -Ft -z -Xs -P



Step 3: Simulate a Disaster and Recover

Record the current time, delete data, and recover to just before the deletion.

SELECT now();   -- record this time, e.g. 2025-06-01 10:00:00
DELETE FROM students;   -- oops

Recovery outline:

Stop PostgreSQL
Replace the data directory with the base backup
In postgresql.conf set:

</>Apache Config

restore_command = 'cp ~/backups/wal/%f %p'
recovery_target_time = '2025-06-01 10:00:00'


     4. Start PostgreSQL

     5. Verify recovery

SELECT count(*) FROM students;



Step 4: Set Up a Streaming Standby

Create a replication role and build a standby server using pg_basebackup.

-- On the primary:
CREATE ROLE replicator
WITH REPLICATION LOGIN PASSWORD 'reppass';

 </>Apache Config

-- In pg_hba.conf:
host replication replicator 127.0.0.1/32 md5

 </>Shell

# Build the standby (separate data directory)
pg_basebackup -h 127.0.0.1 -U replicator -D ~/standby -R -P



Step 5: Watch Replication Health

From the primary server, observe the replication status and lag.

SELECT application_name, state,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;
Wrap‑Up

You protected a database with backups, recovered it to a precise moment after a simulated failure, and configured a live standby replica.