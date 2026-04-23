-- ============================================================
-- PSL ANALYTICS — ADVANCED QUERIES
-- Window Functions + CTEs (MySQL 8.0)
-- ============================================================

USE psl_analytics;

-- ============================================================
-- WINDOW FUNCTION QUERIES
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- Query 1: Season Ranking by Runs
-- CONCEPT: RANK() OVER (PARTITION BY ... ORDER BY ...)
-- EXPLANATION: RANK() assigns a position to each batsman WITHIN
-- each season partition, ordered by total_runs DESC. Batsmen with
-- equal runs share the same rank (with gaps), unlike ROW_NUMBER().
-- The outer subquery filters to only rank <= 3 to show top 3 per season.
-- Without window functions this would require a correlated subquery
-- or a self-join — both significantly more expensive.
-- ────────────────────────────────────────────────────────────
SELECT season, player_name, team_name, total_runs, season_rank
FROM (
    SELECT
        pms.season,
        p.player_name,
        t.team_name,
        SUM(pms.runs_scored) AS total_runs,
        RANK() OVER (
            PARTITION BY pms.season
            ORDER BY SUM(pms.runs_scored) DESC
        ) AS season_rank
    FROM player_match_stats pms
    JOIN players p ON p.player_id = pms.player_id
    JOIN teams   t ON t.team_id   = p.team_id
    GROUP BY pms.season, p.player_id, p.player_name, t.team_name
) ranked
WHERE season_rank <= 3
ORDER BY season, season_rank;


-- ────────────────────────────────────────────────────────────
-- Query 2: Season-over-Season Run Growth
-- CONCEPT: LAG() OVER (PARTITION BY player_id ORDER BY season)
-- EXPLANATION: LAG(total_runs, 1, 0) returns the total_runs from
-- the PREVIOUS row in the partition (previous season). The default
-- value 0 is used when there is no previous row (first season).
-- run_change = this season runs - previous season runs.
-- Positive = improvement; negative = decline.
-- This cannot be achieved without window functions without a
-- complex self-join on player_id with season offset.
-- ────────────────────────────────────────────────────────────
SELECT
    p.player_name,
    t.team_name,
    pms.season,
    SUM(pms.runs_scored) AS total_runs,
    LAG(SUM(pms.runs_scored), 1, 0) OVER (
        PARTITION BY pms.player_id
        ORDER BY pms.season
    ) AS prev_season_runs,
    SUM(pms.runs_scored) - LAG(SUM(pms.runs_scored), 1, 0) OVER (
        PARTITION BY pms.player_id
        ORDER BY pms.season
    ) AS run_change
FROM player_match_stats pms
JOIN players p ON p.player_id = pms.player_id
JOIN teams   t ON t.team_id   = p.team_id
GROUP BY pms.player_id, p.player_name, t.team_name, pms.season
ORDER BY p.player_name, pms.season;


-- ────────────────────────────────────────────────────────────
-- Query 3: Cumulative Team Wins
-- CONCEPT: SUM() OVER with ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
-- EXPLANATION: This running-total frame gives a cumulative sum of wins
-- from the first season up to (and including) the current season row
-- for each team. The PARTITION BY team_id resets the running total
-- per team. ORDER BY season ensures chronological accumulation.
-- Shows total wins a team has accrued across the entire PSL history.
-- ────────────────────────────────────────────────────────────
SELECT
    t.team_name,
    m.season,
    COUNT(CASE WHEN m.winner_id = t.team_id THEN 1 END) AS wins_this_season,
    SUM(COUNT(CASE WHEN m.winner_id = t.team_id THEN 1 END)) OVER (
        PARTITION BY t.team_id
        ORDER BY m.season
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_wins
FROM teams t
JOIN matches m ON (m.team1_id = t.team_id OR m.team2_id = t.team_id)
GROUP BY t.team_id, t.team_name, m.season
ORDER BY t.team_name, m.season;


-- ────────────────────────────────────────────────────────────
-- Query 4: Bowler Economy Percentile
-- CONCEPT: PERCENT_RANK() OVER (PARTITION BY season ORDER BY economy ASC)
-- EXPLANATION: PERCENT_RANK() returns a value between 0 and 1 indicating
-- what fraction of rows have a strictly lower value. A bowler at
-- percentile 0.10 has a LOWER (better) economy than 90% of bowlers —
-- they are in the top 10% of economical bowlers in that season.
-- ASC ordering means the most economical bowler is at percentile 0.00.
-- ────────────────────────────────────────────────────────────
SELECT
    p.player_name,
    t.team_name,
    pms.season,
    GetEconomy(SUM(pms.runs_given), SUM(pms.balls_bowled)) AS economy,
    ROUND(
        PERCENT_RANK() OVER (
            PARTITION BY pms.season
            ORDER BY GetEconomy(SUM(pms.runs_given), SUM(pms.balls_bowled)) ASC
        ) * 100, 1
    ) AS economy_percentile
FROM player_match_stats pms
JOIN players p ON p.player_id = pms.player_id
JOIN teams   t ON t.team_id   = p.team_id
WHERE pms.balls_bowled > 0
GROUP BY pms.player_id, p.player_name, t.team_name, pms.season
ORDER BY pms.season, economy_percentile;


-- ────────────────────────────────────────────────────────────
-- Query 5: Next Innings Comparison using LEAD
-- CONCEPT: LEAD() OVER (PARTITION BY batting_team_id ORDER BY match_date)
-- EXPLANATION: LEAD(total_runs, 1, 0) returns the total_runs of the
-- NEXT innings row for the same batting team, ordered by match date.
-- run_difference shows how this innings compares to the team's VERY
-- NEXT innings (positive = they scored more next time; negative = less).
-- This is a forward-looking analysis impossible with standard joins.
-- ────────────────────────────────────────────────────────────
SELECT
    t.team_name,
    m.match_date,
    i.innings_number,
    i.total_runs,
    LEAD(i.total_runs, 1, 0) OVER (
        PARTITION BY i.batting_team_id
        ORDER BY m.match_date
    ) AS next_innings_runs,
    i.total_runs - LEAD(i.total_runs, 1, 0) OVER (
        PARTITION BY i.batting_team_id
        ORDER BY m.match_date
    ) AS run_difference
FROM innings i
JOIN matches m ON m.match_id  = i.match_id
JOIN teams   t ON t.team_id   = i.batting_team_id
ORDER BY t.team_name, m.match_date;


-- ============================================================
-- CTE QUERIES
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- Query 6: Recursive Season Generator — Gap Detection
-- CONCEPT: WITH RECURSIVE CTE
-- EXPLANATION: The recursive CTE generates all seasons from 2020
-- to 2025 as a virtual table. The LEFT JOIN against match appearances
-- then identifies seasons where a player was ABSENT (no deliveries).
-- This detects gaps in player participation without needing a
-- pre-existing calendar table. Change @target_player_id to test any player.
-- ────────────────────────────────────────────────────────────
SET @target_player_id = 1;

WITH RECURSIVE season_cte (season) AS (
    -- Anchor: starting season
    SELECT 2020
    UNION ALL
    -- Recursive: increment season until 2025
    SELECT season + 1
    FROM season_cte
    WHERE season < 2025
),
player_appearances AS (
    SELECT DISTINCT m.season
    FROM deliveries d
    JOIN matches m ON m.match_id = d.match_id
    WHERE d.batsman_id = @target_player_id
       OR d.bowler_id  = @target_player_id
)
SELECT
    sc.season,
    CASE
        WHEN pa.season IS NULL THEN 'ABSENT'
        ELSE 'ACTIVE'
    END AS participation_status
FROM season_cte sc
LEFT JOIN player_appearances pa ON pa.season = sc.season
ORDER BY sc.season;


-- ────────────────────────────────────────────────────────────
-- Query 7: Chained CTE — Top Performers Across Multiple Seasons
-- CONCEPT: Multi-level CTE chaining
-- EXPLANATION: Three CTEs are chained:
--   CTE1 (season_stats): computes total runs per player per season.
--   CTE2 (ranked): ranks players WITHIN each season using RANK().
--   CTE3 (consistent_top5): counts how many seasons each player
--         finished in the top 5, then filters to players who did
--         so in at least 3 different seasons.
-- This is a three-step analytical pipeline expressed cleanly as
-- chained CTEs — far more readable than nested subqueries.
-- ────────────────────────────────────────────────────────────
WITH season_stats AS (
    SELECT
        pms.player_id,
        p.player_name,
        t.team_name,
        pms.season,
        SUM(pms.runs_scored) AS total_runs
    FROM player_match_stats pms
    JOIN players p ON p.player_id = pms.player_id
    JOIN teams   t ON t.team_id   = p.team_id
    GROUP BY pms.player_id, p.player_name, t.team_name, pms.season
),
ranked AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY season ORDER BY total_runs DESC) AS season_rank
    FROM season_stats
),
consistent_top5 AS (
    SELECT
        player_id,
        player_name,
        team_name,
        COUNT(DISTINCT season) AS top5_seasons,
        SUM(total_runs)        AS career_runs
    FROM ranked
    WHERE season_rank <= 5
    GROUP BY player_id, player_name, team_name
    HAVING COUNT(DISTINCT season) >= 3
)
SELECT *
FROM consistent_top5
ORDER BY top5_seasons DESC, career_runs DESC;


-- ────────────────────────────────────────────────────────────
-- Query 8: Head-to-Head CTE with Venue Breakdown
-- CONCEPT: CTE as a named subquery / derived table alias
-- EXPLANATION: The CTE (h2h_matches) isolates all matches between
-- Karachi Kings (team_id=1) and Lahore Qalandars (team_id=2).
-- The outer query then groups by venue to show which ground each
-- team dominates. Using a CTE makes the team-filter logic reusable
-- and avoids repeating the OR condition across multiple subqueries.
-- Change the team IDs to analyse any two teams.
-- ────────────────────────────────────────────────────────────
WITH h2h_matches AS (
    SELECT
        m.match_id,
        m.venue,
        m.season,
        m.winner_id,
        m.team1_id,
        m.team2_id
    FROM matches m
    WHERE (m.team1_id = 1 AND m.team2_id = 2)
       OR (m.team1_id = 2 AND m.team2_id = 1)
)
SELECT
    h.venue,
    COUNT(*)                                              AS total_matches,
    SUM(CASE WHEN h.winner_id = 1 THEN 1 ELSE 0 END)    AS karachi_wins,
    SUM(CASE WHEN h.winner_id = 2 THEN 1 ELSE 0 END)    AS lahore_wins,
    SUM(CASE WHEN h.winner_id IS NULL THEN 1 ELSE 0 END) AS no_result
FROM h2h_matches h
GROUP BY h.venue
ORDER BY total_matches DESC;
