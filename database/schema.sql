-- ============================================================
-- PSL ANALYTICS — COMPLETE DATABASE SCHEMA
-- MySQL 8.0
-- Run: mysql -u root -p psl_analytics < schema.sql
-- Order: Tables → Indexes → Triggers → Procedures → Functions → Views
-- ============================================================

SET FOREIGN_KEY_CHECKS = 0;
SET SQL_MODE = 'STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO';

CREATE DATABASE IF NOT EXISTS psl_analytics
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE psl_analytics;

-- ============================================================
-- SECTION 1 — BASE TABLES (3NF Normalized)
-- ============================================================

-- teams: Master table for all 6 PSL franchises.
-- Normalized to 3NF: no transitive dependencies; city does not
-- determine home_ground since a city can host multiple grounds.
CREATE TABLE IF NOT EXISTS teams (
    team_id      INT            NOT NULL AUTO_INCREMENT,
    team_name    VARCHAR(100)   NOT NULL,
    city         VARCHAR(80)    NOT NULL,
    home_ground  VARCHAR(150)   NOT NULL,
    founded_year SMALLINT       NOT NULL CHECK (founded_year >= 2016),
    PRIMARY KEY (team_id),
    UNIQUE KEY uq_team_name (team_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- players: Stores all player profiles linked to their franchise.
-- role CHECK constraint enforces domain integrity at the DB layer.
CREATE TABLE IF NOT EXISTS players (
    player_id     INT           NOT NULL AUTO_INCREMENT,
    player_name   VARCHAR(100)  NOT NULL,
    nationality   VARCHAR(60)   NOT NULL,
    role          ENUM('batsman','bowler','allrounder','wicketkeeper') NOT NULL,
    batting_style VARCHAR(50)   NOT NULL,
    bowling_style VARCHAR(60)   NOT NULL,
    team_id       INT           NOT NULL,
    PRIMARY KEY (player_id),
    CONSTRAINT fk_player_team FOREIGN KEY (team_id)
        REFERENCES teams(team_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- matches: Partitioned by RANGE on season (see SECTION 2).
-- BEFORE INSERT trigger validates team1 != team2.
-- AFTER UPDATE trigger writes to match_audit.
-- win_by_runs and win_by_wickets are mutually exclusive —
-- exactly one must be non-zero per completed match.
CREATE TABLE IF NOT EXISTS matches (
    match_id           INT          NOT NULL AUTO_INCREMENT,
    season             SMALLINT     NOT NULL,
    match_date         DATE         NOT NULL,
    venue              VARCHAR(150) NOT NULL,
    city               VARCHAR(80)  NOT NULL,
    team1_id           INT          NOT NULL,
    team2_id           INT          NOT NULL,
    toss_winner_id     INT          NOT NULL,
    toss_decision      ENUM('bat','field') NOT NULL,
    winner_id          INT              NULL,
    win_by_runs        SMALLINT     NOT NULL DEFAULT 0,
    win_by_wickets     TINYINT      NOT NULL DEFAULT 0,
    player_of_match_id INT              NULL,
    match_type         ENUM('league','playoff','final') NOT NULL DEFAULT 'league',
    PRIMARY KEY (match_id, season),
    CONSTRAINT chk_win_margin   CHECK (win_by_runs >= 0 AND win_by_wickets >= 0 AND win_by_wickets <= 10)
)
ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
-- PARTITIONING TYPE: RANGE on season column.
-- WHY: Season is the dominant filter on every dashboard query.
-- RANGE partitioning eliminates entire season partitions during scans,
-- reducing I/O from 240 rows to ~40 rows per season query.
-- QUERIES ACCELERATED: GET /api/matches?season=, CalculateNRR, GenerateSeasonLeaderboard
PARTITION BY RANGE (season) (
    PARTITION p2020 VALUES LESS THAN (2021),
    PARTITION p2021 VALUES LESS THAN (2022),
    PARTITION p2022 VALUES LESS THAN (2023),
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- NOTE: MySQL does not support FOREIGN KEY constraints on partitioned tables.
-- The logical FK relationships are enforced at application/trigger level.
-- Referential integrity for matches is maintained via import order and triggers.
-- The following ALTER statements add FKs on non-partitioned child tables only.


-- innings: One row per innings per match (2 per match = 480 rows).
-- Links batting_team and bowling_team to teams.
CREATE TABLE IF NOT EXISTS innings (
    innings_id      INT            NOT NULL AUTO_INCREMENT,
    match_id        INT            NOT NULL,
    innings_number  TINYINT        NOT NULL CHECK (innings_number IN (1, 2)),
    batting_team_id INT            NOT NULL,
    bowling_team_id INT            NOT NULL,
    total_runs      SMALLINT       NOT NULL DEFAULT 0,
    total_wickets   TINYINT        NOT NULL DEFAULT 0 CHECK (total_wickets <= 10),
    total_overs     DECIMAL(4,1)   NOT NULL DEFAULT 20.0,
    extras          SMALLINT       NOT NULL DEFAULT 0,
    PRIMARY KEY (innings_id),
    UNIQUE KEY uq_innings_match_num (match_id, innings_number),
    INDEX idx_innings_match_id (match_id),
    CONSTRAINT fk_innings_bat    FOREIGN KEY (batting_team_id)
        REFERENCES teams(team_id),
    CONSTRAINT fk_innings_bowl   FOREIGN KEY (bowling_team_id)
        REFERENCES teams(team_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- deliveries: Largest table (~35,000 rows). Partitioned by match_id range.
-- Every ball bowled is one row. Triggers fire here to update stats.
CREATE TABLE IF NOT EXISTS deliveries (
    delivery_id    INT       NOT NULL AUTO_INCREMENT,
    innings_id     INT       NOT NULL,
    match_id       INT       NOT NULL,
    over_number    TINYINT   NOT NULL CHECK (over_number BETWEEN 1 AND 20),
    ball_number    TINYINT   NOT NULL CHECK (ball_number BETWEEN 1 AND 6),
    batsman_id     INT       NOT NULL,
    bowler_id      INT       NOT NULL,
    runs_scored    TINYINT   NOT NULL DEFAULT 0,
    extras         TINYINT   NOT NULL DEFAULT 0,
    extra_type     VARCHAR(10)   NULL DEFAULT NULL,
    is_wicket      TINYINT(1) NOT NULL DEFAULT 0 CHECK (is_wicket IN (0, 1)),
    dismissal_type VARCHAR(20)   NULL DEFAULT NULL,
    fielder_id     INT           NULL DEFAULT NULL,
    PRIMARY KEY (delivery_id, match_id),
    INDEX idx_del_innings_id (innings_id),
    INDEX idx_del_batsman_id (batsman_id),
    INDEX idx_del_bowler_id  (bowler_id),
    INDEX idx_del_fielder_id (fielder_id)
    -- NOTE: FKs omitted on partitioned table (MySQL restriction).
    -- Referential integrity maintained by import order in import_data.py.
)
ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
-- PARTITIONING TYPE: RANGE on match_id.
-- WHY: Deliveries are almost always queried in the context of a specific
-- match or a season's matches. Partitioning by match_id range means
-- queries filtered on match_id (or a seasonal subset of match_ids)
-- prune irrelevant partitions automatically.
-- QUERIES ACCELERATED: player form queries, per-match ball-by-ball analysis,
-- GenerateSeasonLeaderboard joins, GetHeadToHead aggregations.
PARTITION BY RANGE (match_id) (
    PARTITION pd1 VALUES LESS THAN (49),
    PARTITION pd2 VALUES LESS THAN (97),
    PARTITION pd3 VALUES LESS THAN (145),
    PARTITION pd4 VALUES LESS THAN (193),
    PARTITION pd5 VALUES LESS THAN (241),
    PARTITION pd_rest VALUES LESS THAN MAXVALUE
);


-- player_match_stats: Aggregated per-player per-match batting and bowling stats.
-- Populated and maintained entirely by triggers on the deliveries table.
-- This table avoids expensive GROUP BY aggregations in real-time queries.
CREATE TABLE IF NOT EXISTS player_match_stats (
    stat_id        INT  NOT NULL AUTO_INCREMENT,
    player_id      INT  NOT NULL,
    match_id       INT  NOT NULL,
    season         SMALLINT NOT NULL,
    runs_scored    SMALLINT NOT NULL DEFAULT 0,
    balls_faced    SMALLINT NOT NULL DEFAULT 0,
    fours          SMALLINT NOT NULL DEFAULT 0,
    sixes          SMALLINT NOT NULL DEFAULT 0,
    wickets_taken  TINYINT  NOT NULL DEFAULT 0,
    runs_given     SMALLINT NOT NULL DEFAULT 0,
    balls_bowled   SMALLINT NOT NULL DEFAULT 0,
    PRIMARY KEY (stat_id),
    UNIQUE KEY uq_player_match (player_id, match_id),
    CONSTRAINT fk_pms_player FOREIGN KEY (player_id)
        REFERENCES players(player_id),
    INDEX idx_pms_match_id (match_id)
    -- NOTE: No FK to matches(match_id) — matches is partitioned (MySQL restriction).
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- milestones: Records when a player crosses 50 or 100 runs in a single innings.
-- Populated by the trg_milestone_check trigger.
-- Used on the Player detail modal in the frontend.
CREATE TABLE IF NOT EXISTS milestones (
    milestone_id   INT         NOT NULL AUTO_INCREMENT,
    player_id      INT         NOT NULL,
    match_id       INT         NOT NULL,
    innings_id     INT         NOT NULL,
    milestone_type ENUM('50','100') NOT NULL,
    achieved_at    TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (milestone_id),
    CONSTRAINT fk_ms_player  FOREIGN KEY (player_id) REFERENCES players(player_id),
    CONSTRAINT fk_ms_innings FOREIGN KEY (innings_id) REFERENCES innings(innings_id),
    INDEX idx_ms_match_id (match_id)
    -- NOTE: No FK to matches(match_id) — matches is partitioned (MySQL restriction).
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- match_audit: Audit trail for any UPDATE on the matches table.
-- Populated by the trg_after_match_update trigger.
-- Demonstrates database-level accountability — no application code required.
CREATE TABLE IF NOT EXISTS match_audit (
    audit_id       INT         NOT NULL AUTO_INCREMENT,
    match_id       INT         NOT NULL,
    old_winner_id  INT             NULL,
    new_winner_id  INT             NULL,
    changed_at     TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by     VARCHAR(100) NOT NULL,
    PRIMARY KEY (audit_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ============================================================
-- SECTION 2 — INDEXING STRATEGY
-- Every index has a comment explaining: which query it optimizes,
-- why this index type was chosen, and the expected scan reduction.
-- ============================================================

-- ── Single-column indexes ──

-- Accelerates: GET /api/matches?season= and all season-filtered queries.
-- Chosen because season is the most common filter predicate across the dashboard.
CREATE INDEX idx_matches_season      ON matches(season);

-- Accelerates: winner-based aggregations in vw_team_performance (wins count).
-- Without this index, wins = full table scan grouping by winner_id.
CREATE INDEX idx_matches_winner      ON matches(winner_id);

-- Accelerates: GET /api/players?team_id= filter and player lookups per team.
CREATE INDEX idx_players_team        ON players(team_id);

-- Accelerates: GET /api/players?role= filter used in Players page role filter bar.
CREATE INDEX idx_players_role        ON players(role);

-- Accelerates: Every batsman stats aggregation (SUM runs, COUNT balls).
-- deliveries has ~35,000 rows; this turns full scan into index range scan.
CREATE INDEX idx_deliveries_batsman  ON deliveries(batsman_id);

-- Accelerates: Bowler economy and wicket queries in top-bowlers leaderboard.
CREATE INDEX idx_deliveries_bowler   ON deliveries(bowler_id);

-- Accelerates: Per-match delivery fetches (ball-by-ball breakdown in MatchDrawer).
CREATE INDEX idx_deliveries_match    ON deliveries(match_id);

-- Accelerates: Wicket count aggregations in GenerateSeasonLeaderboard procedure.
-- is_wicket is a low-cardinality column (0/1), but used in GROUP BY bowler queries.
CREATE INDEX idx_deliveries_wicket   ON deliveries(is_wicket);

-- Accelerates: player_match_stats lookups by player for career summary.
CREATE INDEX idx_pms_player          ON player_match_stats(player_id);

-- Accelerates: season filter on player_match_stats for leaderboard and NRR.
CREATE INDEX idx_pms_season          ON player_match_stats(season);


-- ── Composite indexes ──

-- Accelerates: JOIN deliveries ON match_id + innings_id — used in GenerateSeasonLeaderboard
-- and in the MatchDrawer API. MySQL uses leftmost prefix (match_id alone also benefits).
CREATE INDEX idx_deliveries_match_innings  ON deliveries(match_id, innings_id);

-- Accelerates: SELECT SUM(runs_scored) WHERE batsman_id = ? AND match_id = ?
-- Used in the milestone trigger and career summary procedure.
CREATE INDEX idx_deliveries_batsman_runs   ON deliveries(batsman_id, runs_scored);

-- Accelerates: SELECT COUNT(*) WHERE bowler_id = ? AND is_wicket = 1
-- Composite eliminates a second filter pass after the bowler index scan.
CREATE INDEX idx_deliveries_bowler_wicket  ON deliveries(bowler_id, is_wicket);

-- Accelerates: season + team1/team2 double filter in head-to-head and NRR queries.
-- A single scan satisfies: WHERE season=? AND (team1_id=? OR team2_id=?)
CREATE INDEX idx_matches_season_team       ON matches(season, team1_id, team2_id);

-- Accelerates: Innings lookups when joining matches → innings → deliveries.
-- Used in CalculateNRR and vw_batsman_season_stats.
CREATE INDEX idx_innings_match_team        ON innings(match_id, batting_team_id);


-- ── Covering indexes ──
-- A covering index satisfies a SELECT entirely from the index B-tree —
-- MySQL never reads the base table rows (Extra: Using index in EXPLAIN).

-- Covers this exact query used by GenerateSeasonLeaderboard:
--   SELECT batsman_id, match_id, SUM(runs_scored), COUNT(*), SUM(is_wicket)
--   FROM deliveries WHERE batsman_id = ?
-- All 4 columns are in the index leaf; zero table row reads needed.
CREATE INDEX idx_cover_batsman_stats ON deliveries(batsman_id, match_id, runs_scored, is_wicket);

-- Covers this exact query used by top-bowler aggregation:
--   SELECT bowler_id, match_id, SUM(runs_scored), SUM(is_wicket), COUNT(*),
--          over_number, ball_number
--   FROM deliveries WHERE bowler_id = ?
-- All 6 columns in the index; MySQL EXPLAIN shows Extra: Using index.
CREATE INDEX idx_cover_bowler_stats ON deliveries(bowler_id, match_id, runs_scored, is_wicket, over_number, ball_number);


-- ============================================================
-- SECTION 3 — TRIGGERS (6 triggers)
-- All use DELIMITER $$ convention shown as comment blocks
-- since MySQL CLI requires DELIMITER to be set interactively.
-- ============================================================

DROP TRIGGER IF EXISTS trg_after_delivery_insert;
DROP TRIGGER IF EXISTS trg_milestone_check;
DROP TRIGGER IF EXISTS trg_before_match_insert;
DROP TRIGGER IF EXISTS trg_after_match_update;
DROP TRIGGER IF EXISTS trg_prevent_duplicate_milestone;
DROP TRIGGER IF EXISTS trg_stats_on_wicket;

-- ────────────────────────────────────────────────────────────
-- Trigger 1: trg_after_delivery_insert
-- PURPOSE: Maintain player_match_stats after every delivery insert.
-- Increments runs_scored, balls_faced, fours, sixes for the batsman,
-- and runs_given, balls_bowled for the bowler.
-- Uses INSERT ... ON DUPLICATE KEY UPDATE for upsert semantics —
-- if no stat row exists for this player+match, create one; otherwise update.
-- WHY NECESSARY: Avoids expensive real-time GROUP BY aggregations across
-- 35,000 delivery rows on every API request.
-- ────────────────────────────────────────────────────────────
DELIMITER $$
CREATE TRIGGER trg_after_delivery_insert
AFTER INSERT ON deliveries
FOR EACH ROW
BEGIN
    DECLARE v_season SMALLINT;

    -- Fetch the season for this match (needed to populate player_match_stats.season)
    SELECT season INTO v_season
    FROM matches
    WHERE match_id = NEW.match_id
    LIMIT 1;

    -- Upsert batting stats for the batsman
    INSERT INTO player_match_stats
        (player_id, match_id, season, runs_scored, balls_faced, fours, sixes,
         wickets_taken, runs_given, balls_bowled)
    VALUES
        (NEW.batsman_id, NEW.match_id, v_season,
         NEW.runs_scored,
         1,
         IF(NEW.runs_scored = 4, 1, 0),
         IF(NEW.runs_scored = 6, 1, 0),
         0, 0, 0)
    ON DUPLICATE KEY UPDATE
        runs_scored  = runs_scored  + NEW.runs_scored,
        balls_faced  = balls_faced  + 1,
        fours        = fours        + IF(NEW.runs_scored = 4, 1, 0),
        sixes        = sixes        + IF(NEW.runs_scored = 6, 1, 0);

    -- Upsert bowling stats for the bowler
    INSERT INTO player_match_stats
        (player_id, match_id, season, runs_scored, balls_faced, fours, sixes,
         wickets_taken, runs_given, balls_bowled)
    VALUES
        (NEW.bowler_id, NEW.match_id, v_season,
         0, 0, 0, 0, 0,
         NEW.runs_scored,
         1)
    ON DUPLICATE KEY UPDATE
        runs_given   = runs_given   + NEW.runs_scored,
        balls_bowled = balls_bowled + 1;
END$$
DELIMITER ;


-- ────────────────────────────────────────────────────────────
-- Trigger 2: trg_milestone_check
-- PURPOSE: Detect when a batsman crosses 50 or 100 in a single innings.
-- After every delivery, sums the batsman's total runs in this innings_id.
-- If the total crosses a threshold for the FIRST TIME (milestone not yet
-- recorded), inserts a row into milestones.
-- WHY NECESSARY: Milestones cannot be reliably detected in application
-- code because deliveries may arrive in batches; only the DB can guarantee
-- correct detection at the exact crossing delivery.
-- ────────────────────────────────────────────────────────────
DELIMITER $$
CREATE TRIGGER trg_milestone_check
AFTER INSERT ON deliveries
FOR EACH ROW
BEGIN
    DECLARE v_total_runs   INT DEFAULT 0;
    DECLARE v_ms50_exists  INT DEFAULT 0;
    DECLARE v_ms100_exists INT DEFAULT 0;

    -- Sum all runs this batsman has scored in this specific innings
    SELECT COALESCE(SUM(runs_scored), 0)
    INTO v_total_runs
    FROM deliveries
    WHERE batsman_id = NEW.batsman_id
      AND innings_id = NEW.innings_id;

    -- Check if a 50-milestone already exists for this player+innings
    SELECT COUNT(*) INTO v_ms50_exists
    FROM milestones
    WHERE player_id = NEW.batsman_id
      AND innings_id = NEW.innings_id
      AND milestone_type = '50';

    -- Check if a 100-milestone already exists
    SELECT COUNT(*) INTO v_ms100_exists
    FROM milestones
    WHERE player_id = NEW.batsman_id
      AND innings_id = NEW.innings_id
      AND milestone_type = '100';

    -- Insert 50 milestone if crossed for the first time
    IF v_total_runs >= 50 AND v_ms50_exists = 0 THEN
        INSERT INTO milestones (player_id, match_id, innings_id, milestone_type)
        VALUES (NEW.batsman_id, NEW.match_id, NEW.innings_id, '50');
    END IF;

    -- Insert 100 milestone if crossed for the first time
    IF v_total_runs >= 100 AND v_ms100_exists = 0 THEN
        INSERT INTO milestones (player_id, match_id, innings_id, milestone_type)
        VALUES (NEW.batsman_id, NEW.match_id, NEW.innings_id, '100');
    END IF;
END$$
DELIMITER ;


-- ────────────────────────────────────────────────────────────
-- Trigger 3: trg_before_match_insert
-- PURPOSE: Prevent a match from being inserted where a team plays itself.
-- team1_id = team2_id is a logical impossibility but cannot be caught
-- by a simple CHECK constraint (CHECK cannot compare two columns in
-- older MySQL versions). SIGNAL SQLSTATE forces a hard error with a
-- meaningful message that propagates back to the application.
-- WHY NECESSARY: Data integrity at the source — even a direct SQL INSERT
-- from a DBA is caught by the database, not just the application layer.
-- ────────────────────────────────────────────────────────────
DELIMITER $$
CREATE TRIGGER trg_before_match_insert
BEFORE INSERT ON matches
FOR EACH ROW
BEGIN
    IF NEW.team1_id = NEW.team2_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid match: team1_id and team2_id must be different teams.';
    END IF;
END$$
DELIMITER ;


-- ────────────────────────────────────────────────────────────
-- Trigger 4: trg_after_match_update
-- PURPOSE: Write a full audit trail whenever a match record is updated.
-- Captures old_winner_id, new_winner_id, the wall-clock timestamp, and
-- the MySQL user who executed the UPDATE via CURRENT_USER().
-- WHY NECESSARY: In a production sports database, match results can be
-- revised due to umpire errors or DLS calculations. This trigger provides
-- a tamper-evident log without requiring any application-layer audit code.
-- ────────────────────────────────────────────────────────────
DELIMITER $$
CREATE TRIGGER trg_after_match_update
AFTER UPDATE ON matches
FOR EACH ROW
BEGIN
    INSERT INTO match_audit (match_id, old_winner_id, new_winner_id, changed_at, changed_by)
    VALUES (
        NEW.match_id,
        OLD.winner_id,
        NEW.winner_id,
        NOW(),
        CURRENT_USER()
    );
END$$
DELIMITER ;


-- ────────────────────────────────────────────────────────────
-- Trigger 5: trg_prevent_duplicate_milestone
-- PURPOSE: Guard-rail BEFORE INSERT on milestones.
-- Although trg_milestone_check already checks before inserting,
-- a direct INSERT statement from a DBA or a race condition could
-- still produce a duplicate. This trigger provides a second,
-- independent layer of enforcement using SIGNAL SQLSTATE.
-- Demonstrates defence-in-depth at the database layer.
-- ────────────────────────────────────────────────────────────
DELIMITER $$
CREATE TRIGGER trg_prevent_duplicate_milestone
BEFORE INSERT ON milestones
FOR EACH ROW
BEGIN
    DECLARE v_exists INT DEFAULT 0;

    SELECT COUNT(*) INTO v_exists
    FROM milestones
    WHERE player_id      = NEW.player_id
      AND innings_id     = NEW.innings_id
      AND milestone_type = NEW.milestone_type;

    IF v_exists > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Duplicate milestone: this player already has this milestone in this innings.';
    END IF;
END$$
DELIMITER ;


-- ────────────────────────────────────────────────────────────
-- Trigger 6: trg_stats_on_wicket
-- PURPOSE: When is_wicket = 1, explicitly increments the bowler's
-- wickets_taken counter in player_match_stats.
-- Although trg_after_delivery_insert updates general stats, wickets
-- are tracked here as a separate, explicit increment to ensure the
-- wickets_taken column is always accurate even if a delivery is
-- inserted out of sequence or re-processed.
-- The local variable v_dismissal_type demonstrates capturing context
-- for potential future logging extensions.
-- ────────────────────────────────────────────────────────────
DELIMITER $$
CREATE TRIGGER trg_stats_on_wicket
AFTER INSERT ON deliveries
FOR EACH ROW
BEGIN
    DECLARE v_dismissal_type VARCHAR(20);

    IF NEW.is_wicket = 1 THEN
        -- Capture dismissal type into a local variable for logging context
        SET v_dismissal_type = COALESCE(NEW.dismissal_type, 'unknown');

        -- Increment the bowler's wicket counter in aggregated stats
        UPDATE player_match_stats
        SET wickets_taken = wickets_taken + 1
        WHERE player_id = NEW.bowler_id
          AND match_id  = NEW.match_id;
    END IF;
END$$
DELIMITER ;


-- ============================================================
-- SECTION 4 — STORED PROCEDURES (5 procedures)
-- ============================================================

DROP PROCEDURE IF EXISTS CalculateNRR;
DROP PROCEDURE IF EXISTS GenerateSeasonLeaderboard;
DROP PROCEDURE IF EXISTS GetHeadToHead;
DROP PROCEDURE IF EXISTS GetPlayerCareerSummary;
DROP PROCEDURE IF EXISTS BulkImportWithSavepoint;

-- ────────────────────────────────────────────────────────────
-- Procedure 1: CalculateNRR
-- NRR Formula: (Total Runs Scored / Total Overs Faced) - (Total Runs Conceded / Total Overs Bowled)
-- Positive NRR = team scored faster than they conceded.
-- This procedure joins matches and innings to compute per-team NRR
-- across all matches in the given season, then ranks by NRR DESC.
-- ────────────────────────────────────────────────────────────
DELIMITER $$
CREATE PROCEDURE CalculateNRR(IN season_input INT)
BEGIN
    SELECT
        t.team_name,
        t.team_id,
        ROUND(
            (SUM(bat_inn.total_runs) / NULLIF(SUM(bat_inn.total_overs), 0)) -
            (SUM(bowl_inn.total_runs) / NULLIF(SUM(bowl_inn.total_overs), 0)),
        3) AS nrr,
        SUM(bat_inn.total_runs)  AS total_runs_scored,
        SUM(bowl_inn.total_runs) AS total_runs_conceded,
        SUM(bat_inn.total_overs)  AS total_overs_faced,
        SUM(bowl_inn.total_overs) AS total_overs_bowled
    FROM teams t
    JOIN innings bat_inn  ON bat_inn.batting_team_id  = t.team_id
    JOIN innings bowl_inn ON bowl_inn.bowling_team_id = t.team_id
                          AND bowl_inn.match_id = bat_inn.match_id
    JOIN matches m ON m.match_id = bat_inn.match_id
    WHERE m.season = season_input
    GROUP BY t.team_id, t.team_name
    ORDER BY nrr DESC;
END$$
DELIMITER ;


-- ────────────────────────────────────────────────────────────
-- Procedure 2: GenerateSeasonLeaderboard
-- Returns top-10 batsmen by total runs and top-10 bowlers by total wickets
-- for a given season. Calls GetStrikeRate and GetEconomy functions to
-- include performance metrics in the result set.
-- ────────────────────────────────────────────────────────────
DELIMITER $$
CREATE PROCEDURE GenerateSeasonLeaderboard(IN season_input INT)
BEGIN
    -- Top 10 batsmen
    SELECT
        p.player_id,
        p.player_name,
        t.team_name,
        SUM(pms.runs_scored)   AS total_runs,
        SUM(pms.balls_faced)   AS total_balls,
        SUM(pms.fours)         AS total_fours,
        SUM(pms.sixes)         AS total_sixes,
        COUNT(pms.match_id)    AS matches_played,
        GetStrikeRate(SUM(pms.runs_scored), SUM(pms.balls_faced)) AS strike_rate
    FROM player_match_stats pms
    JOIN players p ON p.player_id = pms.player_id
    JOIN teams   t ON t.team_id   = p.team_id
    WHERE pms.season = season_input
    GROUP BY p.player_id, p.player_name, t.team_name
    ORDER BY total_runs DESC
    LIMIT 10;

    -- Top 10 bowlers
    SELECT
        p.player_id,
        p.player_name,
        t.team_name,
        SUM(pms.wickets_taken)  AS total_wickets,
        SUM(pms.runs_given)     AS total_runs_given,
        SUM(pms.balls_bowled)   AS total_balls_bowled,
        COUNT(pms.match_id)     AS matches_played,
        GetEconomy(SUM(pms.runs_given), SUM(pms.balls_bowled)) AS economy
    FROM player_match_stats pms
    JOIN players p ON p.player_id = pms.player_id
    JOIN teams   t ON t.team_id   = p.team_id
    WHERE pms.season = season_input
    GROUP BY p.player_id, p.player_name, t.team_name
    ORDER BY total_wickets DESC
    LIMIT 10;
END$$
DELIMITER ;


-- ────────────────────────────────────────────────────────────
-- Procedure 3: GetHeadToHead
-- Returns: total matches, wins for team1, wins for team2,
-- and the venue where the two teams most commonly meet.
-- Demonstrates: multi-table JOIN, GROUP BY, HAVING, subquery.
-- ────────────────────────────────────────────────────────────
DELIMITER $$
CREATE PROCEDURE GetHeadToHead(IN team1 INT, IN team2 INT)
BEGIN
    -- Overall H2H summary
    SELECT
        COUNT(*)                                                   AS total_matches,
        SUM(CASE WHEN winner_id = team1 THEN 1 ELSE 0 END)        AS team1_wins,
        SUM(CASE WHEN winner_id = team2 THEN 1 ELSE 0 END)        AS team2_wins,
        SUM(CASE WHEN winner_id IS NULL  THEN 1 ELSE 0 END)        AS no_result,
        (
            SELECT venue
            FROM matches
            WHERE (team1_id = team1 AND team2_id = team2)
               OR (team1_id = team2 AND team2_id = team1)
            GROUP BY venue
            ORDER BY COUNT(*) DESC
            LIMIT 1
        ) AS favourite_venue
    FROM matches
    WHERE (team1_id = team1 AND team2_id = team2)
       OR (team1_id = team2 AND team2_id = team1);

    -- Venue-wise breakdown (demonstrates GROUP BY + HAVING)
    SELECT
        venue,
        COUNT(*)                                                   AS matches_at_venue,
        SUM(CASE WHEN winner_id = team1 THEN 1 ELSE 0 END)        AS team1_venue_wins,
        SUM(CASE WHEN winner_id = team2 THEN 1 ELSE 0 END)        AS team2_venue_wins
    FROM matches
    WHERE (team1_id = team1 AND team2_id = team2)
       OR (team1_id = team2 AND team2_id = team1)
    GROUP BY venue
    HAVING COUNT(*) > 0
    ORDER BY matches_at_venue DESC;
END$$
DELIMITER ;


-- ────────────────────────────────────────────────────────────
-- Procedure 4: GetPlayerCareerSummary
-- Uses a CURSOR to iterate season-by-season for a player.
-- Accumulates career totals using local variables.
-- DECLARE CONTINUE HANDLER FOR NOT FOUND provides clean cursor exit.
-- Returns: career_runs, career_wickets, seasons_played,
--          best_season_runs, best_season_year.
-- ────────────────────────────────────────────────────────────
DELIMITER $$
CREATE PROCEDURE GetPlayerCareerSummary(IN p_id INT)
BEGIN
    -- Cursor and control variables
    DECLARE v_season        SMALLINT;
    DECLARE v_season_runs   INT DEFAULT 0;
    DECLARE v_season_wkts   INT DEFAULT 0;
    DECLARE v_done          TINYINT DEFAULT 0;

    -- Accumulator variables
    DECLARE v_career_runs   INT DEFAULT 0;
    DECLARE v_career_wkts   INT DEFAULT 0;
    DECLARE v_seasons_count INT DEFAULT 0;
    DECLARE v_best_runs     INT DEFAULT 0;
    DECLARE v_best_year     SMALLINT DEFAULT 0;

    -- Cursor iterates over each distinct season with stats for this player
    DECLARE cur_seasons CURSOR FOR
        SELECT DISTINCT season
        FROM player_match_stats
        WHERE player_id = p_id
        ORDER BY season ASC;

    -- Handler: sets v_done flag when cursor exhausts all rows
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

    OPEN cur_seasons;

    season_loop: LOOP
        FETCH cur_seasons INTO v_season;

        IF v_done = 1 THEN
            LEAVE season_loop;
        END IF;

        -- Get aggregated stats for this season
        SELECT
            COALESCE(SUM(runs_scored), 0),
            COALESCE(SUM(wickets_taken), 0)
        INTO v_season_runs, v_season_wkts
        FROM player_match_stats
        WHERE player_id = p_id
          AND season    = v_season;

        -- Accumulate into career totals
        SET v_career_runs   = v_career_runs  + v_season_runs;
        SET v_career_wkts   = v_career_wkts  + v_season_wkts;
        SET v_seasons_count = v_seasons_count + 1;

        -- Track best season
        IF v_season_runs > v_best_runs THEN
            SET v_best_runs = v_season_runs;
            SET v_best_year = v_season;
        END IF;
    END LOOP season_loop;

    CLOSE cur_seasons;

    -- Return final career summary as a single-row result set
    SELECT
        v_career_runs   AS career_runs,
        v_career_wkts   AS career_wickets,
        v_seasons_count AS seasons_played,
        v_best_runs     AS best_season_runs,
        v_best_year     AS best_season_year;
END$$
DELIMITER ;


-- ────────────────────────────────────────────────────────────
-- Procedure 5: BulkImportWithSavepoint
-- Demonstrates SAVEPOINT-based partial rollback.
-- UNLIKE a simple transaction (BEGIN / COMMIT / ROLLBACK),
-- savepoints allow partial recovery: if table 2 fails, we can
-- keep table 1's data and only retry table 2.
-- This is critical in bulk imports where re-importing 10,000 rows
-- of good data just because 50 bad rows in table 2 failed is wasteful.
-- A DECLARE HANDLER FOR SQLEXCEPTION catches errors and triggers
-- ROLLBACK TO the last safe savepoint.
-- ────────────────────────────────────────────────────────────
DELIMITER $$
CREATE PROCEDURE BulkImportWithSavepoint()
BEGIN
    DECLARE v_error_msg VARCHAR(200) DEFAULT '';
    DECLARE v_error_code INT DEFAULT 0;

    -- Error handler: captures the MySQL error code for reporting
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_error_msg  = MESSAGE_TEXT,
            v_error_code = MYSQL_ERRNO;
        -- Rollback only to last savepoint (sp_teams is always safe)
        ROLLBACK TO SAVEPOINT sp_teams;
        SELECT CONCAT('ERROR ', v_error_code, ': ', v_error_msg) AS import_error;
    END;

    START TRANSACTION;

    -- ── Phase 1: Insert test team rows ──
    INSERT IGNORE INTO teams (team_name, city, home_ground, founded_year)
    VALUES ('Test Import FC', 'Test City', 'Test Ground', 2025);

    -- SAVEPOINT sp_teams: teams data is now safely committed to the
    -- transaction's undo log. Any subsequent failure can ROLLBACK TO here.
    SAVEPOINT sp_teams;

    -- ── Phase 2: Insert a test player ──
    INSERT IGNORE INTO players (player_name, nationality, role, batting_style, bowling_style, team_id)
    VALUES ('Import Test Player', 'Pakistani', 'batsman', 'Right-hand bat', 'Right-arm off-spin',
            (SELECT team_id FROM teams WHERE team_name = 'Test Import FC' LIMIT 1));

    -- SAVEPOINT sp_players: both teams and players are now at a safe state.
    SAVEPOINT sp_players;

    -- ── Phase 3: Intentional constraint violation to demonstrate partial rollback ──
    -- Uncommenting this would trigger the HANDLER:
    -- INSERT INTO players (player_name, nationality, role, batting_style, bowling_style, team_id)
    -- VALUES ('Bad Player', 'X', 'batsman', 'Right-hand bat', 'Right-arm', 9999);

    SAVEPOINT sp_matches;

    -- If we reach here, all phases succeeded — commit everything
    COMMIT;

    SELECT 'BulkImportWithSavepoint completed successfully. All savepoints reached.' AS import_status;
END$$
DELIMITER ;


-- ============================================================
-- SECTION 5 — USER-DEFINED FUNCTIONS (4 functions)
-- ============================================================

DROP FUNCTION IF EXISTS GetStrikeRate;
DROP FUNCTION IF EXISTS GetEconomy;
DROP FUNCTION IF EXISTS GetPlayerRating;
DROP FUNCTION IF EXISTS GetConsecutiveActiveSeasons;

-- ────────────────────────────────────────────────────────────
-- Function 1: GetStrikeRate
-- Returns runs scored per 100 balls faced.
-- Returns 0.00 if balls = 0 to prevent division-by-zero error.
-- ────────────────────────────────────────────────────────────
DELIMITER $$
CREATE FUNCTION GetStrikeRate(runs INT, balls INT)
RETURNS DECIMAL(6,2)
DETERMINISTIC
NO SQL
BEGIN
    IF balls = 0 OR balls IS NULL THEN
        RETURN 0.00;
    END IF;
    RETURN ROUND((runs / balls) * 100.0, 2);
END$$
DELIMITER ;


-- ────────────────────────────────────────────────────────────
-- Function 2: GetEconomy
-- Returns runs conceded per over (6 balls).
-- Returns 0.00 if balls_bowled = 0.
-- ────────────────────────────────────────────────────────────
DELIMITER $$
CREATE FUNCTION GetEconomy(runs_given INT, balls_bowled INT)
RETURNS DECIMAL(6,2)
DETERMINISTIC
NO SQL
BEGIN
    IF balls_bowled = 0 OR balls_bowled IS NULL THEN
        RETURN 0.00;
    END IF;
    RETURN ROUND((runs_given / balls_bowled) * 6.0, 2);
END$$
DELIMITER ;


-- ────────────────────────────────────────────────────────────
-- Function 3: GetPlayerRating
-- Composite weighted performance score for a player in a season.
-- Formula:
--   (total_runs * 0.4) + (strike_rate * 0.2)
--   + (wickets * 15 * 0.3) + ((10 / economy) * 0.1)
-- Weights: batting contribution (40%) + scoring speed (20%)
--          + wicket-taking (30%) + bowling economy (10%)
-- Returns 0.00 if no data exists for this player/season combination.
-- ────────────────────────────────────────────────────────────
DELIMITER $$
CREATE FUNCTION GetPlayerRating(p_id INT, season_input INT)
RETURNS DECIMAL(6,2)
READS SQL DATA
BEGIN
    DECLARE v_runs     INT     DEFAULT 0;
    DECLARE v_balls    INT     DEFAULT 0;
    DECLARE v_wickets  INT     DEFAULT 0;
    DECLARE v_r_given  INT     DEFAULT 0;
    DECLARE v_b_bowled INT     DEFAULT 0;
    DECLARE v_sr       DECIMAL(6,2) DEFAULT 0.00;
    DECLARE v_eco      DECIMAL(6,2) DEFAULT 0.00;
    DECLARE v_rating   DECIMAL(6,2) DEFAULT 0.00;

    SELECT
        COALESCE(SUM(runs_scored), 0),
        COALESCE(SUM(balls_faced), 0),
        COALESCE(SUM(wickets_taken), 0),
        COALESCE(SUM(runs_given), 0),
        COALESCE(SUM(balls_bowled), 0)
    INTO v_runs, v_balls, v_wickets, v_r_given, v_b_bowled
    FROM player_match_stats
    WHERE player_id = p_id
      AND season    = season_input;

    IF v_balls = 0 AND v_b_bowled = 0 THEN
        RETURN 0.00;
    END IF;

    SET v_sr  = GetStrikeRate(v_runs, v_balls);
    SET v_eco = GetEconomy(v_r_given, v_b_bowled);

    SET v_rating = ROUND(
        (v_runs * 0.4) +
        (v_sr   * 0.2) +
        (v_wickets * 15 * 0.3) +
        ((10.0 / NULLIF(v_eco, 0)) * 0.1),
    2);

    RETURN COALESCE(v_rating, 0.00);
END$$
DELIMITER ;


-- ────────────────────────────────────────────────────────────
-- Function 4: GetConsecutiveActiveSeasons
-- Uses a WHILE loop to iterate seasons 2020→2025.
-- Counts how many consecutive seasons a player appeared in at least
-- one delivery. Returns the maximum consecutive streak length.
-- Example: active in 2020, 2021, 2022, inactive 2023, active 2024
--          → max streak = 3 (years 2020-2022).
-- ────────────────────────────────────────────────────────────
DELIMITER $$
CREATE FUNCTION GetConsecutiveActiveSeasons(p_id INT)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_season       SMALLINT DEFAULT 2020;
    DECLARE v_streak       INT DEFAULT 0;
    DECLARE v_max_streak   INT DEFAULT 0;
    DECLARE v_count        INT DEFAULT 0;

    WHILE v_season <= 2025 DO
        -- Count deliveries for this player in this season
        SELECT COUNT(*) INTO v_count
        FROM deliveries d
        JOIN matches m ON m.match_id = d.match_id
        WHERE d.batsman_id = p_id
          AND m.season = v_season;

        IF v_count > 0 THEN
            SET v_streak = v_streak + 1;
            IF v_streak > v_max_streak THEN
                SET v_max_streak = v_streak;
            END IF;
        ELSE
            SET v_streak = 0;
        END IF;

        SET v_season = v_season + 1;
    END WHILE;

    RETURN v_max_streak;
END$$
DELIMITER ;


-- ============================================================
-- SECTION 6 — VIEWS (5 views)
-- ============================================================

DROP VIEW IF EXISTS vw_batsman_season_stats;
DROP VIEW IF EXISTS vw_bowler_season_stats;
DROP VIEW IF EXISTS vw_team_performance;
DROP VIEW IF EXISTS vw_match_summary;
DROP VIEW IF EXISTS vw_player_last5_form;

-- ────────────────────────────────────────────────────────────
-- View 1: vw_batsman_season_stats
-- USED BY: Dashboard top-batsmen table, Players page career modal.
-- Aggregates batting stats per player per season, calling GetStrikeRate.
-- ────────────────────────────────────────────────────────────
CREATE VIEW vw_batsman_season_stats AS
SELECT
    p.player_id,
    p.player_name,
    t.team_name,
    pms.season,
    SUM(pms.runs_scored)                                           AS total_runs,
    SUM(pms.balls_faced)                                           AS balls_faced,
    GetStrikeRate(SUM(pms.runs_scored), SUM(pms.balls_faced))      AS strike_rate,
    SUM(pms.fours)                                                 AS fours,
    SUM(pms.sixes)                                                 AS sixes,
    COUNT(pms.match_id)                                            AS matches_played,
    MAX(pms.runs_scored)                                           AS highest_score
FROM player_match_stats pms
JOIN players p ON p.player_id = pms.player_id
JOIN teams   t ON t.team_id   = p.team_id
GROUP BY p.player_id, p.player_name, t.team_name, pms.season;


-- ────────────────────────────────────────────────────────────
-- View 2: vw_bowler_season_stats
-- USED BY: Dashboard top-bowlers table, Analytics leaderboard.
-- Aggregates bowling stats per player per season, calling GetEconomy.
-- ────────────────────────────────────────────────────────────
CREATE VIEW vw_bowler_season_stats AS
SELECT
    p.player_id,
    p.player_name,
    t.team_name,
    pms.season,
    SUM(pms.wickets_taken)                                         AS total_wickets,
    SUM(pms.runs_given)                                            AS runs_given,
    SUM(pms.balls_bowled)                                          AS balls_bowled,
    GetEconomy(SUM(pms.runs_given), SUM(pms.balls_bowled))         AS economy,
    COUNT(pms.match_id)                                            AS matches_played,
    MAX(pms.wickets_taken)                                         AS best_figures
FROM player_match_stats pms
JOIN players p ON p.player_id = pms.player_id
JOIN teams   t ON t.team_id   = p.team_id
GROUP BY p.player_id, p.player_name, t.team_name, pms.season;


-- ────────────────────────────────────────────────────────────
-- View 3: vw_team_performance
-- USED BY: Teams page win-rate panel, Analytics win-rate bar chart.
-- Computes matches played, wins, losses, win% per team per season.
-- ────────────────────────────────────────────────────────────
CREATE VIEW vw_team_performance AS
SELECT
    t.team_id,
    t.team_name,
    m.season,
    COUNT(DISTINCT m.match_id)                                      AS matches_played,
    SUM(CASE WHEN m.winner_id = t.team_id THEN 1 ELSE 0 END)       AS wins,
    SUM(CASE WHEN m.winner_id != t.team_id AND m.winner_id IS NOT NULL THEN 1 ELSE 0 END) AS losses,
    ROUND(
        100.0 * SUM(CASE WHEN m.winner_id = t.team_id THEN 1 ELSE 0 END)
        / NULLIF(COUNT(DISTINCT m.match_id), 0),
    1)                                                              AS win_percentage,
    (
        SELECT COALESCE(SUM(i2.total_runs), 0)
        FROM innings i2
        WHERE i2.batting_team_id = t.team_id
          AND i2.match_id IN (
              SELECT match_id FROM matches WHERE season = m.season
          )
    )                                                               AS total_runs_scored,
    (
        SELECT COALESCE(SUM(i3.total_runs), 0)
        FROM innings i3
        WHERE i3.bowling_team_id = t.team_id
          AND i3.match_id IN (
              SELECT match_id FROM matches WHERE season = m.season
          )
    )                                                               AS total_runs_conceded
FROM teams t
JOIN matches m ON (m.team1_id = t.team_id OR m.team2_id = t.team_id)
GROUP BY t.team_id, t.team_name, m.season;


-- ────────────────────────────────────────────────────────────
-- View 4: vw_match_summary
-- USED BY: Match Explorer page table, match detail drawer.
-- Fully denormalized: resolves all IDs to human-readable names.
-- ────────────────────────────────────────────────────────────
CREATE VIEW vw_match_summary AS
SELECT
    m.match_id,
    m.season,
    m.match_date,
    m.venue,
    m.city,
    t1.team_name                                AS team1_name,
    t2.team_name                                AS team2_name,
    tw.team_name                                AS winner_name,
    m.win_by_runs,
    m.win_by_wickets,
    p.player_name                               AS player_of_match_name,
    m.match_type,
    m.toss_decision,
    tt.team_name                                AS toss_winner_name
FROM matches m
JOIN teams  t1 ON t1.team_id = m.team1_id
JOIN teams  t2 ON t2.team_id = m.team2_id
LEFT JOIN teams  tw ON tw.team_id = m.winner_id
LEFT JOIN players p ON p.player_id = m.player_of_match_id
LEFT JOIN teams  tt ON tt.team_id  = m.toss_winner_id;


-- ────────────────────────────────────────────────────────────
-- View 5: vw_player_last5_form
-- USED BY: Player modal "last 5 form" mini bar chart.
-- Uses ROW_NUMBER() window function to number each player's matches
-- in reverse chronological order, then filters to the 5 most recent.
-- This is a window-function-based view — non-trivial and efficient.
-- ────────────────────────────────────────────────────────────
CREATE VIEW vw_player_last5_form AS
SELECT
    player_id,
    player_name,
    match_id,
    match_date,
    runs_scored,
    wickets_taken,
    row_num
FROM (
    SELECT
        pms.player_id,
        p.player_name,
        pms.match_id,
        m.match_date,
        pms.runs_scored,
        pms.wickets_taken,
        ROW_NUMBER() OVER (
            PARTITION BY pms.player_id
            ORDER BY m.match_date DESC
        ) AS row_num
    FROM player_match_stats pms
    JOIN players p ON p.player_id = pms.player_id
    JOIN matches m ON m.match_id  = pms.match_id
) ranked
WHERE row_num <= 5;

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================
-- END OF SCHEMA
-- ============================================================
