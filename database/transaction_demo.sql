-- ============================================================
-- PSL ANALYTICS — TRANSACTION ISOLATION LEVEL DEMONSTRATIONS
-- MySQL 8.0
-- Each section documents:
--   - The problem scenario
--   - The isolation level used and why
--   - Both Session A and Session B scripts
-- Run each session block in a SEPARATE MySQL connection/tab.
-- ============================================================

USE psl_analytics;

-- ============================================================
-- DEMO 1: READ COMMITTED — Preventing Dirty Reads
-- ============================================================
--
-- SCENARIO:
--   Session A is in the middle of updating Babar Azam's total runs
--   in player_match_stats. The UPDATE has started but NOT yet committed.
--   Session B wants to read that player's stats for a dashboard render.
--
-- PROBLEM WITHOUT ISOLATION:
--   READ UNCOMMITTED (the lowest isolation level) would allow Session B
--   to read Session A's not-yet-committed data (a "dirty read").
--   If Session A then ROLLBACKs, Session B displayed phantom/incorrect data.
--
-- SOLUTION:
--   READ COMMITTED prevents Session B from seeing any row changes until
--   Session A explicitly commits. Session B always reads the last committed
--   version of the row, never in-progress changes.
--
-- WHY READ COMMITTED and not REPEATABLE READ here?
--   Dashboard reads are one-shot queries — they don't need a consistent
--   snapshot across multiple reads. READ COMMITTED gives fresh data after
--   every commit with less lock overhead than REPEATABLE READ.
-- ============================================================

-- ── SESSION A (run in connection 1) ──────────────────────────
-- Step A1: Set isolation level for this session
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Step A2: Begin the update transaction
BEGIN;

-- Step A3: Update Babar Azam's stats (player_id=1 as example)
UPDATE player_match_stats
SET runs_scored = runs_scored + 50
WHERE player_id = 1
  AND match_id  = 1;

-- *** DO NOT COMMIT YET — switch to Session B now ***

-- Step A5 (after Session B reads): Commit the change
COMMIT;


-- ── SESSION B (run in connection 2) ──────────────────────────
-- Step B1: Set the same isolation level
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Step B2: Read Babar's stats WHILE Session A's transaction is open
--          With READ COMMITTED, this returns the PRE-UPDATE value.
--          Session B does NOT see Session A's dirty (uncommitted) data.
BEGIN;

SELECT player_id, runs_scored
FROM player_match_stats
WHERE player_id = 1
  AND match_id  = 1;
-- Expected: returns ORIGINAL runs_scored (without the +50 yet)
-- If isolation level were READ UNCOMMITTED: would show +50 prematurely

COMMIT;

-- Step B3: Read again AFTER Session A commits
BEGIN;

SELECT player_id, runs_scored
FROM player_match_stats
WHERE player_id = 1
  AND match_id  = 1;
-- Expected: NOW shows the updated value (+50) because A has committed

COMMIT;
-- CONCLUSION: READ COMMITTED prevented the dirty read perfectly.


-- ============================================================
-- DEMO 2: REPEATABLE READ — Consistent Snapshot for Analytics
-- ============================================================
--
-- SCENARIO:
--   Session A is computing season-total aggregations across multiple
--   SELECT queries (e.g., first computing NRR, then computing leaderboard).
--   This multi-query report must see a CONSISTENT snapshot of the database.
--   Session B is concurrently inserting new delivery rows.
--
-- PROBLEM WITHOUT ISOLATION:
--   With READ COMMITTED, Session A's second SELECT might include NEW rows
--   inserted and committed by Session B between the two reads — the two
--   parts of the report become inconsistent (non-repeatable reads).
--   This is called a "non-repeatable read" anomaly.
--
-- SOLUTION:
--   REPEATABLE READ (MySQL InnoDB default) gives Session A a consistent
--   snapshot taken at the START of its transaction. All reads within
--   that transaction see the same data regardless of concurrent commits.
--
-- WHY REPEATABLE READ and not SERIALIZABLE?
--   SERIALIZABLE would prevent phantom reads too, but requires range locks
--   that dramatically reduce concurrency. For analytics workloads that are
--   read-only, REPEATABLE READ's MVCC snapshot is sufficient and much faster.
-- ============================================================

-- ── SESSION A (run in connection 1) ──────────────────────────
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- Step A1: Start a long-running analytics transaction
BEGIN;

-- Step A2: First read — compute total runs for season 2023
SELECT SUM(total_runs) AS total_season_runs
FROM innings i
JOIN matches m ON m.match_id = i.match_id
WHERE m.season = 2023;
-- Records the result: say 8,450 total runs

-- *** Session B NOW inserts a new innings row (see below) ***

-- Step A3: Second read — same query WITHIN the same transaction
SELECT SUM(total_runs) AS total_season_runs
FROM innings i
JOIN matches m ON m.match_id = i.match_id
WHERE m.season = 2023;
-- REPEATABLE READ guarantee: returns SAME 8,450 — Session B's insert is invisible
-- READ COMMITTED would have returned 8,450 + new rows (inconsistency!)

COMMIT;


-- ── SESSION B (run in connection 2) ──────────────────────────
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Step B1: Insert a new test innings row WHILE Session A is reading
BEGIN;

INSERT INTO innings (match_id, innings_number, batting_team_id, bowling_team_id,
                     total_runs, total_wickets, total_overs, extras)
VALUES (1, 2, 1, 2, 185, 7, 20.0, 10);

COMMIT;
-- Session A will NOT see this row due to REPEATABLE READ snapshot.
-- Clean up:
DELETE FROM innings WHERE total_runs = 185 AND batting_team_id = 1 AND innings_number = 2;


-- ============================================================
-- DEMO 3: SAVEPOINT and Partial Rollback
-- ============================================================
--
-- SCENARIO:
--   Bulk data import: inserting data into 3 tables in sequence.
--   Table 1 (teams) succeeds.
--   Table 2 (players) fails due to a foreign key violation (bad team_id).
--   Without SAVEPOINTs, ROLLBACK undoes ALL work including the successful
--   teams insert. With SAVEPOINTs, we roll back ONLY to before Table 2,
--   keeping Table 1's data, fix the error, and retry.
--
-- WHY SAVEPOINT over simple transaction?
--   In a 10,000-row bulk import, a single bad row in table 2 should not
--   force re-import of thousands of good rows in table 1.
--   SAVEPOINTs allow surgical recovery at precise checkpoints.
-- ============================================================

-- Full savepoint demonstration script (single session)
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Create a test handler procedure inline:
DROP PROCEDURE IF EXISTS demo_savepoint_import;
DELIMITER $$
CREATE PROCEDURE demo_savepoint_import()
BEGIN
    DECLARE v_error   TINYINT DEFAULT 0;
    DECLARE v_msg     VARCHAR(200) DEFAULT '';

    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        SET v_error = 1;
    END;

    START TRANSACTION;

    -- ── Phase 1: Teams (will succeed) ──
    INSERT IGNORE INTO teams (team_name, city, home_ground, founded_year)
    VALUES ('Demo Team Alpha', 'Demo City', 'Demo Ground', 2025);

    -- SAVEPOINT sp1: Table 1 is now safely recorded in the undo log.
    SAVEPOINT sp1;
    SELECT 'SAVEPOINT sp1 set — teams insert successful' AS status;

    -- ── Phase 2: Player with INVALID team_id (will fail) ──
    SAVEPOINT sp2;  -- set before the risky operation

    SET v_error = 0;
    INSERT INTO players (player_name, nationality, role, batting_style, bowling_style, team_id)
    VALUES ('Bad Import Player', 'Pakistani', 'batsman', 'Right-hand bat', 'Right-arm', 99999);
    -- team_id=99999 does not exist → FK violation → HANDLER fires

    IF v_error = 1 THEN
        -- Partial rollback: only undo back to sp2 (sp1 / teams data is KEPT)
        ROLLBACK TO SAVEPOINT sp2;
        SELECT CONCAT('Phase 2 FAILED: ', v_msg, '. Rolled back to sp2. Teams data preserved.') AS status;

        -- Retry Phase 2 with corrected team_id
        SET v_error = 0;
        INSERT INTO players (player_name, nationality, role, batting_style, bowling_style, team_id)
        VALUES ('Fixed Import Player', 'Pakistani', 'batsman', 'Right-hand bat', 'Right-arm', 1);

        IF v_error = 0 THEN
            SAVEPOINT sp2_retry;
            SELECT 'Phase 2 RETRY succeeded. SAVEPOINT sp2_retry set.' AS status;
        END IF;
    END IF;

    -- ── Phase 3: Continue with matches etc. ──
    SAVEPOINT sp3;
    SELECT 'All phases complete. Committing entire transaction.' AS status;

    COMMIT;
END$$
DELIMITER ;

CALL demo_savepoint_import();


-- ============================================================
-- DEMO 4: SELECT FOR UPDATE — Preventing Lost Updates
-- ============================================================
--
-- SCENARIO:
--   Two concurrent processes (e.g., two backend workers) both want to
--   increment a team's win count at the same time.
--
-- WITHOUT LOCKING (Lost Update Anomaly):
--   Session A: SELECT wins FROM team_wins WHERE team_id=1  → gets 10
--   Session B: SELECT wins FROM team_wins WHERE team_id=1  → gets 10
--   Session A: UPDATE team_wins SET wins=11 WHERE team_id=1
--   Session B: UPDATE team_wins SET wins=11 WHERE team_id=1
--   RESULT: wins = 11, but it should be 12 — ONE WIN IS LOST.
--
-- WITH SELECT FOR UPDATE:
--   Session A: SELECT ... FOR UPDATE  → acquires exclusive row lock
--   Session B: SELECT ... FOR UPDATE  → BLOCKS until Session A commits
--   Session A commits wins=11, lock released
--   Session B reads wins=11, writes wins=12
--   RESULT: wins = 12 — CORRECT.
--
-- WHY SELECT FOR UPDATE and not just UPDATE?
--   When business logic requires reading + computing before writing
--   (e.g., read wins, apply bonus logic, then write), SELECT FOR UPDATE
--   guarantees no other session can modify the row between your read and write.
-- ============================================================

-- ── SESSION A (run in connection 1) ──────────────────────────
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN;

-- Acquire exclusive lock on the team row
SELECT wins
FROM vw_team_performance
WHERE team_id = 1 AND season = 2023
FOR UPDATE;

-- *** Session B attempts to read now — it BLOCKS here ***

-- Simulate business logic: increment wins
UPDATE player_match_stats
SET runs_scored = runs_scored  -- placeholder; real scenario updates a wins table
WHERE player_id = 1 AND match_id = 1;

COMMIT;
-- Session B is now UNBLOCKED and reads the updated value


-- ── SESSION B (run in connection 2) ──────────────────────────
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN;

-- This SELECT FOR UPDATE will BLOCK until Session A commits
-- Without FOR UPDATE, Session B reads stale data concurrently → lost update
SELECT wins
FROM vw_team_performance
WHERE team_id = 1 AND season = 2023
FOR UPDATE;
-- After Session A commits, Session B gets the LATEST value here

COMMIT;

-- ── DEMONSTRATION OF THE LOST UPDATE WITHOUT LOCKING ──────────
-- To see the problem: remove FOR UPDATE from both sessions.
-- Both sessions read wins=10 simultaneously.
-- Both write wins=11. Second write silently overwrites the first.
-- Net result: only +1 applied instead of +2.
-- SELECT FOR UPDATE is the canonical MySQL solution.
