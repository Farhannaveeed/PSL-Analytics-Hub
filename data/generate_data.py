"""
generate_data.py
----------------
Generates all 5 PSL Analytics CSV files with realistic data for seasons 2020-2025.
Uses only Python standard library (csv, random, datetime).
Run: python generate_data.py  (from the /data directory)
random.seed(42) ensures identical output on every run.
"""

import csv
import random
import os
from datetime import date, timedelta

random.seed(42)

OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))

# ─────────────────────────────────────────────
# REFERENCE DATA
# ─────────────────────────────────────────────

TEAMS = [
    (1, "Karachi Kings",      "Karachi",   "National Stadium Karachi",   2016),
    (2, "Lahore Qalandars",   "Lahore",    "Gaddafi Stadium Lahore",     2016),
    (3, "Quetta Gladiators",  "Quetta",    "Bugti Stadium Quetta",       2016),
    (4, "Peshawar Zalmi",     "Peshawar",  "Arbab Niaz Stadium",         2016),
    (5, "Islamabad United",   "Islamabad", "Pindi Cricket Stadium",      2016),
    (6, "Multan Sultans",     "Multan",    "Multan Cricket Stadium",     2018),
]

PAKISTANI_NAMES = [
    "Babar Azam", "Mohammad Rizwan", "Shaheen Afridi", "Fakhar Zaman",
    "Shadab Khan", "Hasan Ali", "Iftikhar Ahmed", "Asif Ali",
    "Mohammad Hafeez", "Sarfaraz Ahmed", "Shoaib Malik", "Imad Wasim",
    "Wahab Riaz", "Usman Shinwari", "Hussain Talat", "Khushdil Shah",
    "Danish Aziz", "Sohail Khan", "Kamran Akmal", "Ahmed Shehzad",
    "Rohail Nazir", "Zaman Khan", "Arshad Iqbal", "Mohammad Nawaz",
    "Salman Agha", "Faheem Ashraf", "Abid Ali", "Sharjeel Khan",
    "Azam Khan", "Qasim Akram", "Saud Shakeel", "Mohammad Wasim Jr",
    "Naseem Shah", "Haris Rauf", "Mohammad Amir", "Rumman Raees",
    "Mohammad Abbas", "Yasir Shah", "Umar Akmal", "Raza Hasan",
    "Anwar Ali", "Sohail Tanvir", "Umaid Asif", "Sameen Gul",
    "Zahid Mahmood", "Amad Butt", "Abbas Afridi", "Shahnawaz Dahani",
    "Ihsanullah", "Aamir Jamal", "Tayyab Tahir", "Shoaib Akhtar Jr",
    "Bismillah Khan", "Kareem Janat", "Usman Khan", "Faisal Akram",
    "Noman Ali", "Saim Ayub", "Mohammad Huraira", "Arafat Minhas",
]

INTERNATIONAL_NAMES = [
    # England
    "Jason Roy", "Jos Buttler", "Ben Stokes", "Liam Livingstone",
    "Sam Billings", "Alex Hales", "Dawid Malan", "Chris Jordan",
    # Australia
    "David Warner", "Steve Smith", "Glenn Maxwell", "Mitchell Starc",
    "Pat Cummins", "Marcus Stoinis", "Matthew Wade", "Nathan Coulter-Nile",
    # West Indies
    "Chris Gayle", "Kieron Pollard", "Andre Russell", "Sunil Narine",
    "Dwayne Bravo", "Nicholas Pooran", "Shimron Hetmyer", "Darren Sammy",
    # New Zealand
    "Martin Guptill", "Colin Munro", "James Neesham", "Trent Boult",
    "Tim Southee", "Lockie Ferguson", "Colin de Grandhomme", "Devon Conway",
    # South Africa
    "AB de Villiers", "Faf du Plessis", "Rilee Rossouw", "Imran Tahir",
    "Dale Steyn", "Kagiso Rabada", "Quinton de Kock", "David Miller",
    # Bangladesh/Afghanistan extras
    "Shakib Al Hasan", "Tamim Iqbal", "Rashid Khan", "Mohammad Nabi",
    "Mujeeb Ur Rahman", "Hazratullah Zazai", "Najibullah Zadran", "Asghar Afghan",
    # Sri Lanka
    "Kusal Perera", "Thisara Perera", "Angelo Mathews", "Lasith Malinga",
    "Dushmantha Chameera", "Bhanuka Rajapaksa", "Wanindu Hasaranga", "Chamika Karunaratne",
    # Ireland / Scotland extras
    "Paul Stirling", "Kevin O'Brien", "George Munsey", "Richie Berrington",
]

NATIONALITIES_MAP = {
    "Jason Roy": "English",       "Jos Buttler": "English",
    "Ben Stokes": "English",      "Liam Livingstone": "English",
    "Sam Billings": "English",    "Alex Hales": "English",
    "Dawid Malan": "English",     "Chris Jordan": "English",
    "David Warner": "Australian", "Steve Smith": "Australian",
    "Glenn Maxwell": "Australian","Mitchell Starc": "Australian",
    "Pat Cummins": "Australian",  "Marcus Stoinis": "Australian",
    "Matthew Wade": "Australian", "Nathan Coulter-Nile": "Australian",
    "Chris Gayle": "West Indian", "Kieron Pollard": "West Indian",
    "Andre Russell": "West Indian","Sunil Narine": "West Indian",
    "Dwayne Bravo": "West Indian","Nicholas Pooran": "West Indian",
    "Shimron Hetmyer": "West Indian","Darren Sammy": "West Indian",
    "Martin Guptill": "New Zealander","Colin Munro": "New Zealander",
    "James Neesham": "New Zealander","Trent Boult": "New Zealander",
    "Tim Southee": "New Zealander","Lockie Ferguson": "New Zealander",
    "Colin de Grandhomme": "New Zealander","Devon Conway": "New Zealander",
    "AB de Villiers": "South African","Faf du Plessis": "South African",
    "Rilee Rossouw": "South African","Imran Tahir": "South African",
    "Dale Steyn": "South African","Kagiso Rabada": "South African",
    "Quinton de Kock": "South African","David Miller": "South African",
    "Shakib Al Hasan": "Bangladeshi","Tamim Iqbal": "Bangladeshi",
    "Rashid Khan": "Afghan",      "Mohammad Nabi": "Afghan",
    "Mujeeb Ur Rahman": "Afghan", "Hazratullah Zazai": "Afghan",
    "Najibullah Zadran": "Afghan","Asghar Afghan": "Afghan",
    "Kusal Perera": "Sri Lankan", "Thisara Perera": "Sri Lankan",
    "Angelo Mathews": "Sri Lankan","Lasith Malinga": "Sri Lankan",
    "Dushmantha Chameera": "Sri Lankan","Bhanuka Rajapaksa": "Sri Lankan",
    "Wanindu Hasaranga": "Sri Lankan","Chamika Karunaratne": "Sri Lankan",
    "Paul Stirling": "Irish",     "Kevin O'Brien": "Irish",
    "George Munsey": "Scottish",  "Richie Berrington": "Scottish",
}

VENUES = [
    ("National Stadium Karachi",  "Karachi"),
    ("Gaddafi Stadium Lahore",    "Lahore"),
    ("Pindi Cricket Stadium",     "Rawalpindi"),
    ("Multan Cricket Stadium",    "Multan"),
    ("Arbab Niaz Stadium",        "Peshawar"),
]

DISMISSAL_TYPES = ["bowled", "caught", "lbw", "run out", "stumped"]
DISMISSAL_WEIGHTS = [0.25, 0.45, 0.15, 0.10, 0.05]

EXTRA_TYPES = ["wide", "no-ball", "bye", "leg-bye", None]
EXTRA_WEIGHTS = [0.40, 0.25, 0.15, 0.20, 0.00]   # None handled separately


# ─────────────────────────────────────────────
# STEP 1 — TEAMS
# ─────────────────────────────────────────────

def generate_teams():
    print("Generating teams... ", end="", flush=True)
    path = os.path.join(OUTPUT_DIR, "teams.csv")
    rows = []
    for t in TEAMS:
        rows.append({
            "team_id":     t[0],
            "team_name":   t[1],
            "city":        t[2],
            "home_ground": t[3],
            "founded_year":t[4],
        })
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["team_id","team_name","city","home_ground","founded_year"])
        writer.writeheader()
        writer.writerows(rows)
    print(f"done. ({len(rows)} rows)")
    return rows


# ─────────────────────────────────────────────
# STEP 2 — PLAYERS  (120 total)
# ─────────────────────────────────────────────

def generate_players():
    print("Generating players... ", end="", flush=True)

    # Roles with realistic proportions summing to 120
    roles_pool = (
        ["batsman"] * 48 +
        ["bowler"] * 36 +
        ["allrounder"] * 24 +
        ["wicketkeeper"] * 12
    )
    random.shuffle(roles_pool)

    batting_styles = ["Right-hand bat", "Left-hand bat"]
    bowling_styles = [
        "Right-arm fast", "Right-arm fast-medium", "Right-arm medium",
        "Right-arm off-spin", "Left-arm orthodox", "Left-arm wrist-spin",
        "Right-arm leg-spin", "Left-arm fast",
    ]

    # Build combined name + nationality list
    all_names = []
    for name in PAKISTANI_NAMES:
        all_names.append((name, "Pakistani"))
    for name in INTERNATIONAL_NAMES:
        nationality = NATIONALITIES_MAP.get(name, "International")
        all_names.append((name, nationality))

    # Shuffle and trim to exactly 120
    random.shuffle(all_names)
    all_names = all_names[:120]

    team_ids = [1, 2, 3, 4, 5, 6]
    rows = []
    for idx, (name, nationality) in enumerate(all_names):
        player_id = idx + 1
        role = roles_pool[idx]
        team_id = team_ids[idx % 6]
        bat_style = random.choice(batting_styles)
        bowl_style = random.choice(bowling_styles)
        rows.append({
            "player_id":     player_id,
            "player_name":   name,
            "nationality":   nationality,
            "role":          role,
            "batting_style": bat_style,
            "bowling_style": bowl_style,
            "team_id":       team_id,
        })

    path = os.path.join(OUTPUT_DIR, "players.csv")
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "player_id","player_name","nationality","role",
            "batting_style","bowling_style","team_id"
        ])
        writer.writeheader()
        writer.writerows(rows)
    print(f"done. ({len(rows)} rows)")
    return rows


# ─────────────────────────────────────────────
# STEP 3 — MATCHES  (240 total, 40 per season)
# ─────────────────────────────────────────────

def generate_matches(players):
    print("Generating matches... ", end="", flush=True)

    # Build team → player id list for POTM selection
    team_players = {t[0]: [] for t in TEAMS}
    for p in players:
        team_players[p["team_id"]].append(p["player_id"])

    team_ids = [t[0] for t in TEAMS]
    rows = []
    match_id = 1

    for season in range(2020, 2026):
        # Season runs ~Feb 20 to ~Mar 25
        season_start = date(season, 2, 20)

        # 40 matches spread over 33 days
        match_dates = []
        for i in range(40):
            match_dates.append(season_start + timedelta(days=random.randint(0, 33)))
        match_dates.sort()

        # Build bidirectional pairs (each team plays every other team home + away)
        pairs = []
        for i in range(len(team_ids)):
            for j in range(i + 1, len(team_ids)):
                pairs.append((team_ids[i], team_ids[j]))
                pairs.append((team_ids[j], team_ids[i]))
        # 6 teams → 30 bidirectional pairs; pad to 32 by repeating 2 random pairs
        random.shuffle(pairs)
        league_pairs = pairs[:]  # 30 pairs
        while len(league_pairs) < 32:
            league_pairs.append(random.choice(pairs))  # repeat a pair for double-header

        # 4 playoff pairs: 2 semifinals + 2 qualifier matches
        playoff_pairs = [
            (team_ids[0], team_ids[1]),
            (team_ids[2], team_ids[3]),
            (team_ids[0], team_ids[3]),
            (team_ids[1], team_ids[2]),
        ]

        # 4 final stage pairs: eliminator + qualifier-2 + reserve + grand final
        final_pairs = [
            (team_ids[0], team_ids[1]),  # eliminator
            (team_ids[2], team_ids[3]),  # qualifier 2
            (team_ids[0], team_ids[2]),  # qualifier final
            (team_ids[1], team_ids[3]),  # grand final
        ]

        all_pairs = (
            [(p, "league")  for p in league_pairs] +
            [(p, "playoff") for p in playoff_pairs] +
            [(p, "final")   for p in final_pairs]
        )

        for idx, ((t1, t2), mtype) in enumerate(all_pairs):
            mdate = match_dates[idx % 40]
            venue_info = random.choice(VENUES)
            venue, city = venue_info

            toss_winner = random.choice([t1, t2])
            toss_decision = random.choice(["bat", "field"])

            # Determine winner — slight home advantage logic
            winner = random.choice([t1, t2])

            # Win type
            if random.random() < 0.55:
                # Won by runs
                win_by_runs = random.randint(5, 65)
                win_by_wickets = 0
            else:
                win_by_runs = 0
                win_by_wickets = random.randint(1, 8)

            # Player of match from winner's squad
            potm_pool = team_players.get(winner, [])
            potm = random.choice(potm_pool) if potm_pool else 1

            rows.append({
                "match_id":           match_id,
                "season":             season,
                "match_date":         mdate.isoformat(),
                "venue":              venue,
                "city":               city,
                "team1_id":           t1,
                "team2_id":           t2,
                "toss_winner_id":     toss_winner,
                "toss_decision":      toss_decision,
                "winner_id":          winner,
                "win_by_runs":        win_by_runs,
                "win_by_wickets":     win_by_wickets,
                "player_of_match_id": potm,
                "match_type":         mtype,
            })
            match_id += 1

    path = os.path.join(OUTPUT_DIR, "matches.csv")
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "match_id","season","match_date","venue","city",
            "team1_id","team2_id","toss_winner_id","toss_decision",
            "winner_id","win_by_runs","win_by_wickets",
            "player_of_match_id","match_type"
        ])
        writer.writeheader()
        writer.writerows(rows)
    print(f"done. ({len(rows)} rows)")
    return rows


# ─────────────────────────────────────────────
# STEP 4 — INNINGS  (480 rows, 2 per match)
# ─────────────────────────────────────────────

def generate_innings(matches):
    print("Generating innings... ", end="", flush=True)

    rows = []
    innings_id = 1

    for m in matches:
        t1 = m["team1_id"]
        t2 = m["team2_id"]
        winner = m["winner_id"]

        # First innings batting team
        if m["toss_decision"] == "bat":
            bat1 = m["toss_winner_id"]
        else:
            bat1 = t2 if m["toss_winner_id"] == t1 else t1

        bowl1 = t2 if bat1 == t1 else t1

        # First innings total
        inn1_runs = random.randint(140, 220)
        inn1_wkts = random.randint(3, 10)

        # Second innings: must be consistent with match winner
        bat2 = bowl1
        bowl2 = bat1

        if winner == bat2:
            # Chasing team wins — score exceeds first innings
            inn2_runs = inn1_runs + random.randint(1, 20)
            if m["win_by_wickets"] > 0:
                inn2_wkts = 10 - m["win_by_wickets"]
            else:
                inn2_wkts = random.randint(3, 9)
        else:
            # Defending team wins — chasing team falls short
            gap = m["win_by_runs"] if m["win_by_runs"] > 0 else random.randint(5, 40)
            inn2_runs = max(50, inn1_runs - gap)
            inn2_wkts = random.randint(7, 10)

        extras1 = random.randint(5, 20)
        extras2 = random.randint(5, 20)

        rows.append({
            "innings_id":      innings_id,
            "match_id":        m["match_id"],
            "innings_number":  1,
            "batting_team_id": bat1,
            "bowling_team_id": bowl1,
            "total_runs":      inn1_runs,
            "total_wickets":   inn1_wkts,
            "total_overs":     20.0,
            "extras":          extras1,
        })
        innings_id += 1

        rows.append({
            "innings_id":      innings_id,
            "match_id":        m["match_id"],
            "innings_number":  2,
            "batting_team_id": bat2,
            "bowling_team_id": bowl2,
            "total_runs":      inn2_runs,
            "total_wickets":   inn2_wkts,
            "total_overs":     20.0,
            "extras":          extras2,
        })
        innings_id += 1

    path = os.path.join(OUTPUT_DIR, "innings.csv")
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "innings_id","match_id","innings_number",
            "batting_team_id","bowling_team_id",
            "total_runs","total_wickets","total_overs","extras"
        ])
        writer.writeheader()
        writer.writerows(rows)
    print(f"done. ({len(rows)} rows)")
    return rows


# ─────────────────────────────────────────────
# STEP 5 — DELIVERIES  (~35,000 rows)
# ─────────────────────────────────────────────

def weighted_runs():
    """Returns runs per ball using PSL-realistic distribution."""
    roll = random.random()
    if roll < 0.35:
        return 0
    elif roll < 0.65:
        return 1
    elif roll < 0.75:
        return 2
    elif roll < 0.80:
        return 3
    elif roll < 0.90:
        return 4
    else:
        return 6


def generate_deliveries(innings_rows, players):
    print("Generating deliveries... ", end="", flush=True)

    # Build team → player list
    team_players = {t[0]: [] for t in TEAMS}
    for p in players:
        team_players[p["team_id"]].append(p["player_id"])

    rows = []
    delivery_id = 1

    for inn in innings_rows:
        iid      = inn["innings_id"]
        mid      = inn["match_id"]
        bat_team = inn["batting_team_id"]
        bowl_team= inn["bowling_team_id"]

        bat_squad  = team_players.get(bat_team, [1])
        bowl_squad = team_players.get(bowl_team, [1])
        field_squad= bowl_squad  # fielders come from bowling team

        # Pick batsmen (top-order first, ~11 distinct)
        batsmen_order = list(bat_squad)
        random.shuffle(batsmen_order)
        batsmen_order = batsmen_order[:11] if len(batsmen_order) >= 11 else batsmen_order

        # 5 bowlers rotating per innings
        bowlers = list(bowl_squad)
        random.shuffle(bowlers)
        bowlers = bowlers[:5] if len(bowlers) >= 5 else bowlers

        wickets_fallen = 0
        current_batsman_idx = 0   # index into batsmen_order
        on_strike_batsman = batsmen_order[0] if batsmen_order else 1

        for over_num in range(1, 21):           # overs 1–20
            bowler_id = bowlers[(over_num - 1) % len(bowlers)]

            for ball_num in range(1, 7):         # balls 1–6
                runs = weighted_runs()
                is_wicket = 0
                dismissal = None
                fielder_id = None
                extra_runs = 0
                extra_type = None

                # ~1 wicket per 20 balls (probability ≈ 0.05)
                if (wickets_fallen < 10 and
                        random.random() < 0.05 and
                        current_batsman_idx < len(batsmen_order) - 1):
                    is_wicket = 1
                    runs = 0
                    dismissal = random.choices(DISMISSAL_TYPES, weights=DISMISSAL_WEIGHTS, k=1)[0]
                    fielder_pool = [p for p in field_squad if p != bowler_id]
                    fielder_id = random.choice(fielder_pool) if fielder_pool else None
                    wickets_fallen += 1
                    current_batsman_idx += 1
                    on_strike_batsman = batsmen_order[current_batsman_idx]

                # Extras (~8% of deliveries)
                if random.random() < 0.08:
                    extra_type = random.choices(
                        ["wide", "no-ball", "bye", "leg-bye"],
                        weights=[0.40, 0.25, 0.15, 0.20], k=1
                    )[0]
                    extra_runs = 1

                rows.append({
                    "delivery_id":    delivery_id,
                    "innings_id":     iid,
                    "match_id":       mid,
                    "over_number":    over_num,
                    "ball_number":    ball_num,
                    "batsman_id":     on_strike_batsman,
                    "bowler_id":      bowler_id,
                    "runs_scored":    runs,
                    "extras":         extra_runs,
                    "extra_type":     extra_type if extra_type else "",
                    "is_wicket":      is_wicket,
                    "dismissal_type": dismissal if dismissal else "",
                    "fielder_id":     fielder_id if fielder_id else "",
                })
                delivery_id += 1

    path = os.path.join(OUTPUT_DIR, "deliveries.csv")
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "delivery_id","innings_id","match_id","over_number","ball_number",
            "batsman_id","bowler_id","runs_scored","extras","extra_type",
            "is_wicket","dismissal_type","fielder_id"
        ])
        writer.writeheader()
        writer.writerows(rows)
    print(f"done. ({len(rows)} rows)")
    return rows


# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────

if __name__ == "__main__":
    print("=" * 55)
    print("  PSL Analytics — Data Generator")
    print("  random.seed(42) — fully reproducible")
    print("=" * 55)

    teams_rows    = generate_teams()
    players_rows  = generate_players()
    matches_rows  = generate_matches(players_rows)
    innings_rows  = generate_innings(matches_rows)
    delivery_rows = generate_deliveries(innings_rows, players_rows)

    print()
    print("=" * 55)
    print("  SUMMARY")
    print("=" * 55)
    print(f"  teams.csv      : {len(teams_rows):>7} rows")
    print(f"  players.csv    : {len(players_rows):>7} rows")
    print(f"  matches.csv    : {len(matches_rows):>7} rows")
    print(f"  innings.csv    : {len(innings_rows):>7} rows")
    print(f"  deliveries.csv : {len(delivery_rows):>7} rows")
    print("=" * 55)
    print("All files written to:", OUTPUT_DIR)
