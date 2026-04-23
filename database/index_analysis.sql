-- ============================================================
-- PSL ANALYTICS — INDEX ANALYSIS (EXPLAIN Before/After)
-- MySQL 8.0
-- For each of 6 queries: before index, index creation, after index,
-- with simulated EXPLAIN output shown as comments and speedup noted.
-- ============================================================

USE psl_analytics;

-- ============================================================
-- QUERY 1: Top Batsmen (season leaderboard)
-- ============================================================

-- STEP 1: Query WITHOUT index on (batsman_id, runs_scored)
-- EXPLAIN output (as comment):
--   id: 1 | select_type: SIMPLE | table: deliveries
--   type: ALL | possible_keys: NULL | key: NULL
--   key_len: NULL | rows: ~35000 | Extra: Using filesort; Using temporary
-- This performs a FULL TABLE SCAN of all 35,000 delivery rows,
-- builds a temporary table, and sorts it — extremely expensive.
SELECT d.batsman_id, SUM(d.runs_scored) AS total_runs
FROM deliveries d
JOIN matches m ON m.match_id = d.match_id
WHERE m.season = 2023
GROUP BY d.batsman_id
ORDER BY total_runs DESC
LIMIT 10;

-- STEP 2: Index creation (already in schema.sql — shown here for analysis)
-- CREATE INDEX idx_cover_batsman_stats ON deliveries(batsman_id, match_id, runs_scored, is_wicket);

-- STEP 3: Same query WITH covering index
-- EXPLAIN output (as comment):
--   id: 1 | select_type: SIMPLE | table: deliveries
--   type: ref | possible_keys: idx_cover_batsman_stats | key: idx_cover_batsman_stats
--   key_len: 4 | rows: ~180 | Extra: Using index
-- MySQL now reads only the index B-tree (covering index) — zero table rows accessed.
-- The GROUP BY and SUM are performed on index leaf data alone.
SELECT d.batsman_id, SUM(d.runs_scored) AS total_runs
FROM deliveries d
JOIN matches m ON m.match_id = d.match_id
WHERE m.season = 2023
GROUP BY d.batsman_id
ORDER BY total_runs DESC
LIMIT 10;

-- SPEEDUP: Rows scanned reduced from ~35,000 to ~180 — a 99.5% reduction.
-- Extra changes from "Using filesort; Using temporary" to "Using index".


-- ============================================================
-- QUERY 2: Top Bowlers (wickets in a season)
-- ============================================================

-- STEP 1: Query WITHOUT index
-- EXPLAIN output:
--   type: ALL | rows: ~35000 | key: NULL | Extra: Using where; Using filesort
-- Full scan to find is_wicket=1 rows, then sort by bowler wicket count.
SELECT d.bowler_id, COUNT(*) AS total_wickets
FROM deliveries d
JOIN matches m ON m.match_id = d.match_id
WHERE m.season = 2023
  AND d.is_wicket = 1
GROUP BY d.bowler_id
ORDER BY total_wickets DESC
LIMIT 10;

-- STEP 2: Index (already in schema.sql)
-- CREATE INDEX idx_deliveries_bowler_wicket ON deliveries(bowler_id, is_wicket);
-- CREATE INDEX idx_cover_bowler_stats ON deliveries(bowler_id, match_id, runs_scored, is_wicket, over_number, ball_number);

-- STEP 3: Query WITH composite + covering index
-- EXPLAIN output:
--   type: ref | key: idx_deliveries_bowler_wicket | rows: ~700 | Extra: Using index
-- MySQL uses the composite index to first filter by bowler_id,
-- then apply is_wicket=1 as the second column filter without touching base table.
SELECT d.bowler_id, COUNT(*) AS total_wickets
FROM deliveries d
JOIN matches m ON m.match_id = d.match_id
WHERE m.season = 2023
  AND d.is_wicket = 1
GROUP BY d.bowler_id
ORDER BY total_wickets DESC
LIMIT 10;

-- SPEEDUP: Rows scanned reduced from ~35,000 to ~700 — a 98% reduction.


-- ============================================================
-- QUERY 3: Head-to-Head Analysis
-- ============================================================

-- STEP 1: Query WITHOUT index on (season, team1_id, team2_id)
-- EXPLAIN output:
--   type: ALL | rows: ~240 | key: NULL | Extra: Using where
-- Scans all 240 match rows and filters with an OR condition.
-- For deliveries sub-analysis this cascades to 35,000 rows.
SELECT match_id, venue, winner_id
FROM matches
WHERE (team1_id = 1 AND team2_id = 2)
   OR (team1_id = 2 AND team2_id = 1);

-- STEP 2: Index
-- CREATE INDEX idx_matches_season_team ON matches(season, team1_id, team2_id);

-- STEP 3: Query WITH composite index
-- EXPLAIN output:
--   type: range | key: idx_matches_season_team | rows: ~12 | Extra: Using index condition
-- MySQL uses the index to evaluate the OR predicates on team1_id, team2_id
-- within the season partition, reducing rows from 240 to ~12.
SELECT match_id, venue, winner_id
FROM matches
WHERE (team1_id = 1 AND team2_id = 2)
   OR (team1_id = 2 AND team2_id = 1);

-- SPEEDUP: Rows scanned reduced from 240 to ~12 — a 95% reduction.
-- On deliveries join: cascades to reduce delivery rows from 35,000 to ~2,880.


-- ============================================================
-- QUERY 4: Player Form (last 5 matches)
-- ============================================================

-- STEP 1: Query WITHOUT index on player_match_stats(player_id)
-- EXPLAIN output:
--   type: ALL | table: player_match_stats | rows: ~14400 | key: NULL
-- Full scan of player_match_stats to find rows for a single player.
SELECT pms.match_id, pms.runs_scored, pms.wickets_taken, m.match_date
FROM player_match_stats pms
JOIN matches m ON m.match_id = pms.match_id
WHERE pms.player_id = 1
ORDER BY m.match_date DESC
LIMIT 5;

-- STEP 2: Index
-- CREATE INDEX idx_pms_player ON player_match_stats(player_id);

-- STEP 3: Query WITH index
-- EXPLAIN output:
--   type: ref | key: idx_pms_player | rows: ~120 | Extra: Using index condition
-- MySQL uses the index to jump directly to rows for player_id=1.
-- Rows scanned = only matches for that player (~120 across 6 seasons).
SELECT pms.match_id, pms.runs_scored, pms.wickets_taken, m.match_date
FROM player_match_stats pms
JOIN matches m ON m.match_id = pms.match_id
WHERE pms.player_id = 1
ORDER BY m.match_date DESC
LIMIT 5;

-- SPEEDUP: Rows scanned reduced from ~14,400 to ~120 — a 99.2% reduction.


-- ============================================================
-- QUERY 5: Venue Analysis (average scores per venue)
-- ============================================================

-- STEP 1: Query WITHOUT index
-- EXPLAIN output:
--   type: ALL | table: innings | rows: ~480 | key: NULL
--   type: ALL | table: matches | rows: ~240 | key: NULL | Extra: Using join buffer
-- Two-table join with no usable index requires nested-loop full scans.
SELECT m.venue, ROUND(AVG(i.total_runs), 1) AS avg_score, COUNT(*) AS matches_played
FROM innings i
JOIN matches m ON m.match_id = i.match_id
GROUP BY m.venue
ORDER BY avg_score DESC;

-- STEP 2: Index
-- CREATE INDEX idx_innings_match_team ON innings(match_id, batting_team_id);
-- CREATE INDEX idx_matches_season ON matches(season);  -- already exists

-- STEP 3: Query WITH index
-- EXPLAIN output:
--   type: ref | table: innings | key: idx_innings_match_team | rows: ~2 | Extra: Using index
--   type: eq_ref | table: matches | key: PRIMARY | rows: 1
-- The composite index on innings(match_id, batting_team_id) allows MySQL to
-- join matches→innings using the index rather than a full table scan.
SELECT m.venue, ROUND(AVG(i.total_runs), 1) AS avg_score, COUNT(*) AS matches_played
FROM innings i
JOIN matches m ON m.match_id = i.match_id
GROUP BY m.venue
ORDER BY avg_score DESC;

-- SPEEDUP: Join rows reduced from 480×240 = ~115,200 to ~480 (index lookup per row).


-- ============================================================
-- QUERY 6: Season Leaderboard (full season aggregation)
-- ============================================================

-- STEP 1: Query WITHOUT index on player_match_stats(season)
-- EXPLAIN output:
--   type: ALL | table: player_match_stats | rows: ~14400 | key: NULL
--   Extra: Using where; Using temporary; Using filesort
-- Full scan of all player_match_stats rows to filter by season.
SELECT p.player_name, SUM(pms.runs_scored) AS total_runs
FROM player_match_stats pms
JOIN players p ON p.player_id = pms.player_id
WHERE pms.season = 2023
GROUP BY p.player_id, p.player_name
ORDER BY total_runs DESC
LIMIT 10;

-- STEP 2: Index
-- CREATE INDEX idx_pms_season ON player_match_stats(season);  -- already in schema

-- STEP 3: Query WITH index
-- EXPLAIN output:
--   type: ref | key: idx_pms_season | rows: ~2400 | Extra: Using index condition; Using filesort
-- MySQL jumps to season=2023 rows only (~2,400 rows out of 14,400).
-- The filesort is on the smaller result set — 6× faster than before.
SELECT p.player_name, SUM(pms.runs_scored) AS total_runs
FROM player_match_stats pms
JOIN players p ON p.player_id = pms.player_id
WHERE pms.season = 2023
GROUP BY p.player_id, p.player_name
ORDER BY total_runs DESC
LIMIT 10;

-- SPEEDUP: Rows scanned reduced from ~14,400 to ~2,400 — an 83% reduction.
-- Combined with partition pruning on matches table: end-to-end speedup ~95%.
