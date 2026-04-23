"""
app.py
------
PSL Analytics — Flask REST API
All endpoints return JSON. CORS enabled for React dev server.
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
from db import (
    execute_query,
    call_procedure,
    call_function,
    get_isolation_level,
)

app = Flask(__name__)
CORS(app)


# ─────────────────────────────────────────────
# UTILITY
# ─────────────────────────────────────────────

def ok(data):
    return jsonify({"status": "ok", "data": data}), 200


def err(msg, code=500):
    return jsonify({"status": "error", "message": str(msg)}), code


# ─────────────────────────────────────────────
# BASIC ENDPOINTS
# ─────────────────────────────────────────────

@app.route("/api/teams", methods=["GET"])
def get_teams():
    try:
        rows = execute_query("SELECT * FROM teams ORDER BY team_id")
        return ok(rows)
    except Exception as e:
        return err(e)


@app.route("/api/players", methods=["GET"])
def get_players():
    try:
        team_id = request.args.get("team_id")
        role    = request.args.get("role")

        sql    = "SELECT p.*, t.team_name FROM players p JOIN teams t ON t.team_id = p.team_id WHERE 1=1"
        params = []

        if team_id:
            sql += " AND p.team_id = %s"
            params.append(int(team_id))
        if role:
            sql += " AND p.role = %s"
            params.append(role)

        sql += " ORDER BY p.player_name"
        rows = execute_query(sql, params)
        return ok(rows)
    except Exception as e:
        return err(e)


@app.route("/api/matches", methods=["GET"])
def get_matches():
    try:
        season  = request.args.get("season")
        team_id = request.args.get("team_id")

        sql    = "SELECT * FROM vw_match_summary WHERE 1=1"
        params = []

        if season:
            sql += " AND season = %s"
            params.append(int(season))
        if team_id:
            sql += " AND (team1_name = (SELECT team_name FROM teams WHERE team_id=%s) OR team2_name = (SELECT team_name FROM teams WHERE team_id=%s))"
            params.extend([int(team_id), int(team_id)])

        sql += " ORDER BY match_date DESC"
        rows = execute_query(sql, params)
        return ok(rows)
    except Exception as e:
        return err(e)


# ─────────────────────────────────────────────
# ANALYTICAL ENDPOINTS
# ─────────────────────────────────────────────

@app.route("/api/stats/top-batsmen", methods=["GET"])
def top_batsmen():
    try:
        season = int(request.args.get("season", 2023))
        results = call_procedure("GenerateSeasonLeaderboard", [season])
        data = results[0] if results else []
        return ok(data)
    except Exception as e:
        return err(e)


@app.route("/api/stats/top-bowlers", methods=["GET"])
def top_bowlers():
    try:
        season = int(request.args.get("season", 2023))
        results = call_procedure("GenerateSeasonLeaderboard", [season])
        data = results[1] if len(results) > 1 else []
        return ok(data)
    except Exception as e:
        return err(e)


@app.route("/api/stats/team-winrate", methods=["GET"])
def team_winrate():
    try:
        season = request.args.get("season")
        sql    = "SELECT * FROM vw_team_performance"
        params = []
        if season:
            sql += " WHERE season = %s"
            params.append(int(season))
        sql += " ORDER BY win_percentage DESC"
        rows = execute_query(sql, params)
        return ok(rows)
    except Exception as e:
        return err(e)


@app.route("/api/stats/venue-analysis", methods=["GET"])
def venue_analysis():
    try:
        rows = execute_query("""
            SELECT
                venue,
                city,
                COUNT(*)                        AS total_matches,
                ROUND(AVG(win_by_runs), 1)      AS avg_win_by_runs,
                ROUND(AVG(win_by_wickets), 1)   AS avg_win_by_wickets,
                SUM(CASE WHEN win_by_runs > 0 THEN 1 ELSE 0 END) AS bat_first_wins,
                SUM(CASE WHEN win_by_wickets > 0 THEN 1 ELSE 0 END) AS chase_wins
            FROM vw_match_summary
            GROUP BY venue, city
            ORDER BY total_matches DESC
        """)
        # Also get average score per venue
        avg_scores = execute_query("""
            SELECT m.venue, ROUND(AVG(i.total_runs), 1) AS avg_score
            FROM innings i
            JOIN matches m ON m.match_id = i.match_id
            GROUP BY m.venue
        """)
        score_map = {r["venue"]: r["avg_score"] for r in avg_scores}
        for r in rows:
            r["avg_score"] = score_map.get(r["venue"], 0)
        return ok(rows)
    except Exception as e:
        return err(e)


@app.route("/api/stats/player-form", methods=["GET"])
def player_form():
    try:
        player_id = request.args.get("player_id")
        if not player_id:
            return err("player_id is required", 400)
        rows = execute_query(
            "SELECT * FROM vw_player_last5_form WHERE player_id = %s ORDER BY match_date DESC",
            [int(player_id)]
        )
        return ok(rows)
    except Exception as e:
        return err(e)


@app.route("/api/stats/head-to-head", methods=["GET"])
def head_to_head():
    try:
        team1 = request.args.get("team1")
        team2 = request.args.get("team2")
        if not team1 or not team2:
            return err("team1 and team2 are required", 400)
        results = call_procedure("GetHeadToHead", [int(team1), int(team2)])
        return ok({
            "summary":       results[0] if results else [],
            "venue_breakdown": results[1] if len(results) > 1 else [],
        })
    except Exception as e:
        return err(e)


@app.route("/api/stats/leaderboard", methods=["GET"])
def leaderboard():
    try:
        season = int(request.args.get("season", 2023))
        results = call_procedure("GenerateSeasonLeaderboard", [season])
        return ok({
            "batsmen": results[0] if results else [],
            "bowlers": results[1] if len(results) > 1 else [],
        })
    except Exception as e:
        return err(e)


@app.route("/api/stats/boundaries", methods=["GET"])
def boundaries():
    try:
        season = request.args.get("season")
        sql = """
            SELECT
                t.team_name,
                SUM(CASE WHEN d.runs_scored = 4 THEN 1 ELSE 0 END) AS fours,
                SUM(CASE WHEN d.runs_scored = 6 THEN 1 ELSE 0 END) AS sixes
            FROM deliveries d
            JOIN matches m ON m.match_id = d.match_id
            JOIN innings i ON i.innings_id = d.innings_id
            JOIN teams t ON t.team_id = i.batting_team_id
        """
        params = []
        if season:
            sql += " WHERE m.season = %s"
            params.append(int(season))
        sql += " GROUP BY t.team_name ORDER BY (fours + sixes) DESC"
        rows = execute_query(sql, params)
        return ok(rows)
    except Exception as e:
        return err(e)


@app.route("/api/stats/player-rating", methods=["GET"])
def player_rating():
    try:
        player_id = request.args.get("player_id")
        season    = request.args.get("season", 2023)
        if not player_id:
            return err("player_id is required", 400)
        rating = call_function("GetPlayerRating", [int(player_id), int(season)])
        player = execute_query(
            "SELECT player_name, role FROM players WHERE player_id = %s",
            [int(player_id)]
        )
        return ok({
            "player_id": int(player_id),
            "season":    int(season),
            "rating":    float(rating) if rating is not None else 0.0,
            "player":    player[0] if player else {},
        })
    except Exception as e:
        return err(e)


@app.route("/api/stats/nrr", methods=["GET"])
def nrr():
    try:
        season = int(request.args.get("season", 2023))
        results = call_procedure("CalculateNRR", [season])
        data = results[0] if results else []
        return ok(data)
    except Exception as e:
        return err(e)


@app.route("/api/stats/career", methods=["GET"])
def career():
    try:
        player_id = request.args.get("player_id")
        if not player_id:
            return err("player_id is required", 400)
        results = call_procedure("GetPlayerCareerSummary", [int(player_id)])
        data = results[0][0] if results and results[0] else {}
        player = execute_query(
            "SELECT player_name, nationality, role, batting_style, bowling_style, "
            "t.team_name FROM players p JOIN teams t ON t.team_id=p.team_id WHERE p.player_id=%s",
            [int(player_id)]
        )
        return ok({
            "career": data,
            "profile": player[0] if player else {},
        })
    except Exception as e:
        return err(e)


# ─────────────────────────────────────────────
# WINDOW FUNCTION ENDPOINTS
# ─────────────────────────────────────────────

@app.route("/api/stats/window/season-ranking", methods=["GET"])
def window_season_ranking():
    try:
        season = int(request.args.get("season", 2023))
        rows = execute_query("""
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
                WHERE pms.season = %s
                GROUP BY pms.season, p.player_id, p.player_name, t.team_name
            ) ranked
            WHERE season_rank <= 10
            ORDER BY season_rank
        """, [season])
        return ok(rows)
    except Exception as e:
        return err(e)


@app.route("/api/stats/window/player-growth", methods=["GET"])
def window_player_growth():
    try:
        player_id = request.args.get("player_id")
        if not player_id:
            return err("player_id is required", 400)
        rows = execute_query("""
            SELECT
                pms.season,
                p.player_name,
                SUM(pms.runs_scored) AS total_runs,
                LAG(SUM(pms.runs_scored), 1, 0) OVER (
                    PARTITION BY pms.player_id ORDER BY pms.season
                ) AS prev_season_runs,
                SUM(pms.runs_scored) - LAG(SUM(pms.runs_scored), 1, 0) OVER (
                    PARTITION BY pms.player_id ORDER BY pms.season
                ) AS run_change
            FROM player_match_stats pms
            JOIN players p ON p.player_id = pms.player_id
            WHERE pms.player_id = %s
            GROUP BY pms.player_id, p.player_name, pms.season
            ORDER BY pms.season
        """, [int(player_id)])
        return ok(rows)
    except Exception as e:
        return err(e)


# ─────────────────────────────────────────────
# TRANSACTION ISOLATION LEVEL ENDPOINT
# ─────────────────────────────────────────────

@app.route("/api/db/isolation-level", methods=["GET"])
def isolation_level():
    try:
        level = get_isolation_level()
        return ok({"isolation_level": level})
    except Exception as e:
        return err(e)


# ─────────────────────────────────────────────
# DYNAMIC QUERY ENDPOINT
# Demonstrates safe, conditional WHERE clause construction.
# Parameters: metric, season, team_id, player_id
# Each provided parameter appends an AND condition to a list.
# The list is joined with AND and appended to the base query.
# ALL values go through %s parameterized placeholders — NEVER f-strings.
# ─────────────────────────────────────────────

@app.route("/api/query", methods=["GET"])
def dynamic_query():
    try:
        metric    = request.args.get("metric", "batsmen")
        season    = request.args.get("season")
        team_id   = request.args.get("team_id")
        player_id = request.args.get("player_id")

        # Base query — always safe, no user input interpolated
        base_sql = """
            SELECT
                p.player_id,
                p.player_name,
                t.team_name,
                pms.season,
                SUM(pms.runs_scored)   AS total_runs,
                SUM(pms.wickets_taken) AS total_wickets,
                SUM(pms.balls_faced)   AS balls_faced,
                SUM(pms.balls_bowled)  AS balls_bowled
            FROM player_match_stats pms
            JOIN players p ON p.player_id = pms.player_id
            JOIN teams   t ON t.team_id   = p.team_id
        """

        # Conditional WHERE clause construction — ADBMS demonstration
        conditions = []
        params     = []

        # Each block appends a condition string and a safe param value
        if season:
            conditions.append("pms.season = %s")
            params.append(int(season))

        if team_id:
            conditions.append("p.team_id = %s")
            params.append(int(team_id))

        if player_id:
            conditions.append("p.player_id = %s")
            params.append(int(player_id))

        if metric == "batsmen":
            conditions.append("pms.balls_faced > 0")
        elif metric == "bowlers":
            conditions.append("pms.balls_bowled > 0")

        # Join all conditions safely
        if conditions:
            base_sql += " WHERE " + " AND ".join(conditions)

        base_sql += " GROUP BY p.player_id, p.player_name, t.team_name, pms.season"

        if metric == "batsmen":
            base_sql += " ORDER BY total_runs DESC"
        else:
            base_sql += " ORDER BY total_wickets DESC"

        base_sql += " LIMIT 50"

        rows = execute_query(base_sql, params)
        return ok(rows)
    except Exception as e:
        return err(e)


# ─────────────────────────────────────────────
# INNINGS DATA FOR MATCH DRAWER
# ─────────────────────────────────────────────

@app.route("/api/innings/<int:match_id>", methods=["GET"])
def get_innings(match_id):
    try:
        rows = execute_query("""
            SELECT
                i.*,
                t.team_name AS batting_team_name
            FROM innings i
            JOIN teams t ON t.team_id = i.batting_team_id
            WHERE i.match_id = %s
            ORDER BY i.innings_number
        """, [match_id])
        return ok(rows)
    except Exception as e:
        return err(e)


# ─────────────────────────────────────────────
# SEASON SUMMARY FOR DASHBOARD STAT CARDS
# ─────────────────────────────────────────────

@app.route("/api/summary", methods=["GET"])
def summary():
    try:
        total_matches = execute_query("SELECT COUNT(*) AS n FROM matches")[0]["n"]
        total_players = execute_query("SELECT COUNT(*) AS n FROM players")[0]["n"]
        total_runs    = execute_query("SELECT COALESCE(SUM(total_runs),0) AS n FROM innings")[0]["n"]
        seasons       = execute_query("SELECT COUNT(DISTINCT season) AS n FROM matches")[0]["n"]
        return ok({
            "total_matches": total_matches,
            "total_players": total_players,
            "total_runs":    int(total_runs),
            "seasons_covered": seasons,
        })
    except Exception as e:
        return err(e)


# ─────────────────────────────────────────────
# SEASON TREND (total runs per season)
# ─────────────────────────────────────────────

@app.route("/api/stats/season-trend", methods=["GET"])
def season_trend():
    try:
        rows = execute_query("""
            SELECT m.season, SUM(i.total_runs) AS total_runs
            FROM innings i
            JOIN matches m ON m.match_id = i.match_id
            GROUP BY m.season
            ORDER BY m.season
        """)
        return ok(rows)
    except Exception as e:
        return err(e)


if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5000)
