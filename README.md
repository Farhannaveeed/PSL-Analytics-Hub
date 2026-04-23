# PSL Match Analytics Dashboard
### ADBMS University Project — Full-Stack Cricket Analytics Platform

**Stack:** MySQL 8.0 · Python Flask · React + Tailwind CSS · Recharts · Vite

---

## Setup Instructions

### Step 1 — Generate Data
```bash
python data/generate_data.py
```
Generates 5 CSV files in `/data`: teams (6), players (120), matches (240), innings (480), deliveries (~35,000).
Uses `random.seed(42)` — fully reproducible, zero external dependencies.

### Step 2 — Create MySQL Database
```sql
CREATE DATABASE psl_analytics CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

### Step 3 — Load Schema
```bash
mysql -u root -p psl_analytics < database/schema.sql
```
Creates all tables (with partitions), indexes, triggers, stored procedures, functions, and views.

### Step 4 — Import Data
```bash
python database/import_data.py
```
Update `DB_CONFIG` password in `database/import_data.py` first.
Uses `INSERT IGNORE` — fully idempotent, safe to re-run.

### Step 5 — Start Backend
```bash
cd backend
pip install -r requirements.txt
python app.py
```
API runs at `http://localhost:5000`

### Step 6 — Start Frontend
```bash
cd frontend
npm install
npm run dev
```
Dashboard opens at `http://localhost:5173`

---

## ADBMS Features Implemented

| # | Feature | Type | Location | Purpose |
|---|---------|------|----------|---------|
| 1 | `matches` PARTITION BY RANGE(season) | Table Partitioning | schema.sql | Season-filter query pruning — 6× speedup |
| 2 | `deliveries` PARTITION BY RANGE(match_id) | Table Partitioning | schema.sql | Per-match ball-by-ball query pruning |
| 3 | `idx_cover_batsman_stats` | Covering Index | schema.sql | Batsman leaderboard — 99.5% row reduction |
| 4 | `idx_cover_bowler_stats` | Covering Index | schema.sql | Bowler economy query — zero table row reads |
| 5 | 8 single-column + 5 composite indexes | Indexing Strategy | schema.sql | Every major query optimized |
| 6 | `trg_after_delivery_insert` | AFTER INSERT Trigger | schema.sql | Maintains player_match_stats automatically |
| 7 | `trg_milestone_check` | AFTER INSERT Trigger | schema.sql | Detects 50/100 milestones per innings |
| 8 | `trg_before_match_insert` | BEFORE INSERT Trigger | schema.sql | Validates team1 ≠ team2 with SIGNAL |
| 9 | `trg_after_match_update` | AFTER UPDATE Trigger | schema.sql | Audit trail for match result changes |
| 10 | `trg_prevent_duplicate_milestone` | BEFORE INSERT Trigger | schema.sql | Defence-in-depth duplicate prevention |
| 11 | `trg_stats_on_wicket` | AFTER INSERT Trigger | schema.sql | Explicit wickets_taken counter increment |
| 12 | `CalculateNRR` | Stored Procedure | schema.sql | Net Run Rate computation per season |
| 13 | `GenerateSeasonLeaderboard` | Stored Procedure | schema.sql | Top-10 batsmen + bowlers per season |
| 14 | `GetHeadToHead` | Stored Procedure | schema.sql | H2H stats with venue breakdown |
| 15 | `GetPlayerCareerSummary` | Stored Procedure + CURSOR | schema.sql | Season-by-season career accumulation |
| 16 | `BulkImportWithSavepoint` | Stored Procedure + SAVEPOINT | schema.sql | Partial rollback on bulk import failure |
| 17 | `GetStrikeRate` | User-Defined Function | schema.sql | (runs/balls)×100 with zero-guard |
| 18 | `GetEconomy` | User-Defined Function | schema.sql | (runs/balls)×6 with zero-guard |
| 19 | `GetPlayerRating` | User-Defined Function | schema.sql | Weighted composite performance score |
| 20 | `GetConsecutiveActiveSeasons` | User-Defined Function + WHILE | schema.sql | Max consecutive seasons streak |
| 21 | `vw_batsman_season_stats` | View | schema.sql | Aggregated batting stats per player/season |
| 22 | `vw_bowler_season_stats` | View | schema.sql | Aggregated bowling stats per player/season |
| 23 | `vw_team_performance` | View | schema.sql | Win/loss/NRR per team per season |
| 24 | `vw_match_summary` | View | schema.sql | Denormalized match view for frontend |
| 25 | `vw_player_last5_form` | View + ROW_NUMBER() | schema.sql | Last 5 matches per player via window fn |
| 26 | RANK() OVER PARTITION BY | Window Function | advanced_queries.sql | Season ranking by runs |
| 27 | LAG() OVER | Window Function | advanced_queries.sql | Season-over-season run improvement |
| 28 | SUM() OVER ROWS UNBOUNDED | Window Function | advanced_queries.sql | Cumulative team wins over time |
| 29 | PERCENT_RANK() | Window Function | advanced_queries.sql | Bowler economy percentile |
| 30 | LEAD() OVER | Window Function | advanced_queries.sql | Next innings comparison |
| 31 | WITH RECURSIVE | CTE | advanced_queries.sql | Season gap detection for players |
| 32 | 3-level chained CTE | CTE | advanced_queries.sql | Consistent top-5 performers filter |
| 33 | CTE as named subquery | CTE | advanced_queries.sql | Head-to-head venue breakdown |
| 34 | READ COMMITTED demo | Transaction Isolation | transaction_demo.sql | Dirty read prevention |
| 35 | REPEATABLE READ demo | Transaction Isolation | transaction_demo.sql | Consistent analytics snapshot |
| 36 | SAVEPOINT demo | Transaction Isolation | transaction_demo.sql | Partial rollback on bulk import |
| 37 | SELECT FOR UPDATE demo | Transaction Isolation | transaction_demo.sql | Lost update prevention |
| 38 | Dynamic WHERE with %s params | Safe Dynamic Query | backend/app.py `/api/query` | Conditional AND building, no injection |
| 39 | EXPLAIN before/after analysis | Index Analysis | index_analysis.sql | 6 queries with measured speedup % |
| 40 | 3NF normalization | Schema Design | schema.sql | 8 fully normalized tables |

---

## API Reference

| Method | Endpoint | Parameters | Description |
|--------|----------|------------|-------------|
| GET | `/api/teams` | — | All 6 PSL franchises |
| GET | `/api/players` | `team_id`, `role` | Players with optional filters |
| GET | `/api/matches` | `season`, `team_id` | Match list via vw_match_summary |
| GET | `/api/innings/:match_id` | — | 2 innings rows for a match |
| GET | `/api/summary` | — | Dashboard stat card totals |
| GET | `/api/stats/top-batsmen` | `season` | GenerateSeasonLeaderboard result set 1 |
| GET | `/api/stats/top-bowlers` | `season` | GenerateSeasonLeaderboard result set 2 |
| GET | `/api/stats/leaderboard` | `season` | Both batsmen + bowlers combined |
| GET | `/api/stats/team-winrate` | `season?` | vw_team_performance |
| GET | `/api/stats/venue-analysis` | — | Venue stats + avg scores |
| GET | `/api/stats/player-form` | `player_id` | vw_player_last5_form |
| GET | `/api/stats/head-to-head` | `team1`, `team2` | GetHeadToHead procedure |
| GET | `/api/stats/boundaries` | `season?` | Fours/sixes per team |
| GET | `/api/stats/player-rating` | `player_id`, `season` | GetPlayerRating function |
| GET | `/api/stats/nrr` | `season` | CalculateNRR procedure |
| GET | `/api/stats/career` | `player_id` | GetPlayerCareerSummary procedure |
| GET | `/api/stats/season-trend` | — | Total runs per season 2020–2025 |
| GET | `/api/stats/window/season-ranking` | `season` | RANK() window query |
| GET | `/api/stats/window/player-growth` | `player_id` | LAG() window query |
| GET | `/api/db/isolation-level` | — | SELECT @@transaction_isolation |
| GET | `/api/query` | `metric`, `season`, `team_id`, `player_id` | Dynamic WHERE clause endpoint |

### Example Responses

```json
// GET /api/stats/nrr?season=2023
{
  "status": "ok",
  "data": [
    { "team_name": "Lahore Qalandars", "team_id": 2, "nrr": 0.412, ... },
    { "team_name": "Islamabad United", "team_id": 5, "nrr": 0.238, ... }
  ]
}

// GET /api/stats/player-rating?player_id=1&season=2023
{
  "status": "ok",
  "data": {
    "player_id": 1,
    "season": 2023,
    "rating": 84.35,
    "player": { "player_name": "Babar Azam", "role": "batsman" }
  }
}

// GET /api/query?metric=batsmen&season=2023&team_id=1
{
  "status": "ok",
  "data": [ { "player_name": "...", "total_runs": 312, ... } ]
}
```

---

## Project Structure

```
psl-analytics/
├── data/
│   └── generate_data.py          ← Run first; generates all 5 CSVs
│
├── database/
│   ├── schema.sql                 ← Complete DB schema (tables→indexes→triggers→procs→funcs→views)
│   ├── advanced_queries.sql       ← 5 window function + 3 CTE queries
│   ├── transaction_demo.sql       ← 4 isolation level demonstration scripts
│   ├── index_analysis.sql         ← EXPLAIN before/after for 6 queries
│   └── import_data.py             ← CSV → MySQL batch importer
│
├── backend/
│   ├── app.py                     ← All 20 Flask REST endpoints
│   ├── db.py                      ← MySQL pool, execute_query, call_procedure, call_function
│   └── requirements.txt
│
├── frontend/
│   ├── src/
│   │   ├── api/                   ← client.js + stats.js (all API calls)
│   │   ├── components/            ← Sidebar, StatCard, PlayerModal, MatchDrawer
│   │   ├── pages/                 ← Dashboard, Teams, Players, Matches, Analytics, Advanced
│   │   ├── App.jsx                ← React Router v6 routes
│   │   ├── main.jsx
│   │   └── index.css              ← Tailwind + global styles
│   ├── package.json
│   ├── vite.config.js
│   └── tailwind.config.js
│
└── README.md
```

---

## Notes

- Update `DB_CONFIG` passwords in both `database/import_data.py` and `backend/db.py` before running.
- The `schema.sql` FK references on the partitioned `matches` table use composite PKs `(match_id, season)` — ensure your MySQL version supports this (MySQL 8.0 required).
- All Flask endpoints use parameterized `%s` queries — no raw string interpolation with user input anywhere.
- The Advanced DB Panel fetches **live data** from Flask endpoints — no hardcoded mock data (except the EXPLAIN before/after comparison cards which are display-only from `index_analysis.sql`).
