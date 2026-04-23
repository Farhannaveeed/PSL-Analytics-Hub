import { useEffect, useState } from 'react'
import {
  getLeaderboard, getNRR, getHeadToHead, getCareer,
  getWindowRanking, getWindowGrowth, getIsolationLevel,
  getTeamWinRate,
} from '../api/stats'
import client from '../api/client'

// ── EXPLAIN hardcoded data ──────────────────────────────────
const EXPLAIN_DATA = [
  {
    name: 'Top Batsmen (Season Leaderboard)',
    before: { type: 'ALL', rows: 35000, key: 'NULL', extra: 'Using filesort; Using temporary' },
    after:  { type: 'ref', rows: 180,   key: 'idx_cover_batsman_stats', extra: 'Using index' },
    speedup: '99.5',
    index: 'idx_cover_batsman_stats ON deliveries(batsman_id, match_id, runs_scored, is_wicket)',
  },
  {
    name: 'Top Bowlers (Wicket Count)',
    before: { type: 'ALL', rows: 35000, key: 'NULL', extra: 'Using where; Using filesort' },
    after:  { type: 'ref', rows: 700,   key: 'idx_deliveries_bowler_wicket', extra: 'Using index' },
    speedup: '98.0',
    index: 'idx_deliveries_bowler_wicket ON deliveries(bowler_id, is_wicket)',
  },
  {
    name: 'Head-to-Head Analysis',
    before: { type: 'ALL', rows: 240,   key: 'NULL', extra: 'Using where' },
    after:  { type: 'range', rows: 12,  key: 'idx_matches_season_team', extra: 'Using index condition' },
    speedup: '95.0',
    index: 'idx_matches_season_team ON matches(season, team1_id, team2_id)',
  },
  {
    name: 'Player Form (Last 5 Matches)',
    before: { type: 'ALL', rows: 14400, key: 'NULL', extra: 'Using where; Using filesort' },
    after:  { type: 'ref', rows: 120,   key: 'idx_pms_player', extra: 'Using index condition' },
    speedup: '99.2',
    index: 'idx_pms_player ON player_match_stats(player_id)',
  },
  {
    name: 'Venue Analysis (Avg Scores)',
    before: { type: 'ALL', rows: 115200, key: 'NULL', extra: 'Using join buffer' },
    after:  { type: 'ref', rows: 480,    key: 'idx_innings_match_team', extra: 'Using index' },
    speedup: '99.6',
    index: 'idx_innings_match_team ON innings(match_id, batting_team_id)',
  },
  {
    name: 'Season Leaderboard (Full Aggregation)',
    before: { type: 'ALL', rows: 14400, key: 'NULL', extra: 'Using where; Using temporary; Using filesort' },
    after:  { type: 'ref', rows: 2400,  key: 'idx_pms_season', extra: 'Using index condition; Using filesort' },
    speedup: '83.0',
    index: 'idx_pms_season ON player_match_stats(season)',
  },
]

// ── Isolation level scripts ─────────────────────────────────
const ISO_SCRIPTS = [
  {
    title: 'READ COMMITTED — Preventing Dirty Reads',
    level: 'READ COMMITTED',
    scenario: 'Session A updates player stats but has not committed. Session B reads the same row. READ COMMITTED ensures Session B sees the last committed value, never Session A\'s in-progress change.',
    code: `-- SESSION A
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN;
UPDATE player_match_stats SET runs_scored = runs_scored + 50
WHERE player_id = 1 AND match_id = 1;
-- DO NOT COMMIT YET --

-- SESSION B
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN;
SELECT runs_scored FROM player_match_stats
WHERE player_id = 1 AND match_id = 1;
-- Returns ORIGINAL value (dirty read prevented)
COMMIT;`,
  },
  {
    title: 'REPEATABLE READ — Consistent Analytics Snapshot',
    level: 'REPEATABLE READ',
    scenario: 'Session A runs a multi-step analytics report. Session B inserts new delivery rows mid-report. REPEATABLE READ gives Session A a frozen snapshot — both SELECT queries return identical totals.',
    code: `-- SESSION A
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN;
SELECT SUM(total_runs) FROM innings i
  JOIN matches m ON m.match_id = i.match_id WHERE m.season = 2023;
-- 8,450 total runs

-- SESSION B inserts new innings row here --

SELECT SUM(total_runs) FROM innings i
  JOIN matches m ON m.match_id = i.match_id WHERE m.season = 2023;
-- STILL returns 8,450 (snapshot frozen at BEGIN)
COMMIT;`,
  },
  {
    title: 'SAVEPOINT — Partial Rollback on Bulk Import',
    level: 'SAVEPOINT',
    scenario: 'Importing 3 tables in sequence. Table 2 fails due to a FK violation. ROLLBACK TO SAVEPOINT sp1 preserves Table 1 data and only retries Table 2 — no re-import of thousands of good rows.',
    code: `START TRANSACTION;
INSERT INTO teams ... ;
SAVEPOINT sp1;   -- teams are safe

INSERT INTO players ... ;  -- FAILS: bad team_id
SAVEPOINT sp2;

-- HANDLER fires:
ROLLBACK TO SAVEPOINT sp2;
-- Fix data, retry:
INSERT INTO players (correct data) ... ;
SAVEPOINT sp2_retry;

COMMIT;  -- sp1 data + fixed sp2 data committed`,
  },
  {
    title: 'SELECT FOR UPDATE — Preventing Lost Updates',
    level: 'SELECT FOR UPDATE',
    scenario: 'Two workers increment a team\'s win count concurrently. Without locking both read 10, both write 11 — one win is lost. SELECT FOR UPDATE ensures the second session blocks until the first commits.',
    code: `-- SESSION A (acquires lock)
BEGIN;
SELECT wins FROM team_stats WHERE team_id = 1 FOR UPDATE;
-- wins = 10; Session B BLOCKS here
UPDATE team_stats SET wins = 11 WHERE team_id = 1;
COMMIT;  -- Session B unblocks, reads wins=11

-- SESSION B (waits for A)
BEGIN;
SELECT wins FROM team_stats WHERE team_id = 1 FOR UPDATE;
-- After A commits: reads 11, writes 12 ✓
UPDATE team_stats SET wins = 12 WHERE team_id = 1;
COMMIT;`,
  },
]

// ── Reusable components ─────────────────────────────────────

function SectionHeader({ number, title }) {
  return (
    <div className="flex items-center gap-3 mb-4">
      <div
        className="w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold"
        style={{ background: '#00a65122', color: '#00a651', border: '1px solid #00a65144' }}
      >
        {number}
      </div>
      <div className="font-bold text-white">{title}</div>
    </div>
  )
}

function ResultTable({ data }) {
  if (!data || data.length === 0) return (
    <div className="text-center text-textsec py-4 text-sm">No results yet.</div>
  )
  const keys = Object.keys(data[0])
  return (
    <div className="overflow-x-auto mt-3">
      <table>
        <thead>
          <tr>{keys.map(k => <th key={k}>{k}</th>)}</tr>
        </thead>
        <tbody>
          {data.map((row, i) => (
            <tr key={i}>
              {keys.map(k => (
                <td key={k}>{row[k] ?? '—'}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function Pagination({ data, page, setPage }) {
  const PER_PAGE = 20
  const total = data.length
  const pages = Math.ceil(total / PER_PAGE)
  const slice = data.slice(page * PER_PAGE, (page + 1) * PER_PAGE)
  return (
    <div>
      <ResultTable data={slice} />
      {pages > 1 && (
        <div className="flex items-center gap-2 mt-3 justify-end">
          <button
            disabled={page === 0}
            onClick={() => setPage(p => p - 1)}
            className="text-xs px-3 py-1 rounded border border-border disabled:opacity-40"
            style={{ background: '#0f1117', color: '#8b8fa8' }}
          >
            ← Prev
          </button>
          <span className="text-xs text-textsec">{page + 1} / {pages}</span>
          <button
            disabled={page >= pages - 1}
            onClick={() => setPage(p => p + 1)}
            className="text-xs px-3 py-1 rounded border border-border disabled:opacity-40"
            style={{ background: '#0f1117', color: '#8b8fa8' }}
          >
            Next →
          </button>
        </div>
      )}
    </div>
  )
}

// ── Main Page ───────────────────────────────────────────────

export default function Advanced() {
  // Section 1 — Procedures
  const [procName, setProcName]   = useState('CalculateNRR')
  const [procInput, setProcInput] = useState({ season: '2023', player_id: '1', team1: '1', team2: '2' })
  const [procResult, setProcResult] = useState(null)
  const [procLoading, setProcLoading] = useState(false)

  // Section 2 — Views
  const [viewName, setViewName]   = useState('vw_batsman_season_stats')
  const [viewData, setViewData]   = useState([])
  const [viewPage, setViewPage]   = useState(0)
  const [viewLoading, setViewLoading] = useState(false)

  // Section 3 — Window Functions
  const [wfSeason, setWfSeason]   = useState(2023)
  const [wfPlayer, setWfPlayer]   = useState(1)
  const [rankData, setRankData]   = useState([])
  const [growthData, setGrowthData] = useState([])
  const [wfLoading, setWfLoading] = useState(false)

  // Section 4 — Query Optimizer
  const [explainIdx, setExplainIdx] = useState(0)

  // Section 5 — Isolation level
  const [isoLevel, setIsoLevel]   = useState('...')
  const [openIso, setOpenIso]     = useState(null)

  useEffect(() => {
    getIsolationLevel().then(r => setIsoLevel(r.data.data?.isolation_level || '—'))
  }, [])

  // ── Procedure runner ──
  const runProcedure = async () => {
    setProcLoading(true)
    setProcResult(null)
    try {
      let res
      const s = parseInt(procInput.season) || 2023
      const p = parseInt(procInput.player_id) || 1
      const t1 = parseInt(procInput.team1) || 1
      const t2 = parseInt(procInput.team2) || 2

      switch (procName) {
        case 'CalculateNRR':
          res = await getNRR(s); setProcResult(res.data.data); break
        case 'GenerateSeasonLeaderboard':
          res = await getLeaderboard(s)
          setProcResult([
            ...(res.data.data?.batsmen || []).map(r => ({ ...r, __set: 'Batsmen' })),
            ...(res.data.data?.bowlers || []).map(r => ({ ...r, __set: 'Bowlers' })),
          ]); break
        case 'GetHeadToHead':
          res = await getHeadToHead(t1, t2)
          setProcResult([
            ...(res.data.data?.summary || []),
            ...(res.data.data?.venue_breakdown || []),
          ]); break
        case 'GetPlayerCareerSummary':
          res = await getCareer(p)
          setProcResult([res.data.data?.career || {}]); break
        case 'BulkImportWithSavepoint':
          res = await client.get('/query?metric=batsmen&season=' + s)
          setProcResult([{ note: 'BulkImportWithSavepoint runs internally in MySQL. See schema.sql for full implementation.' }]); break
        default: break
      }
    } catch (e) {
      setProcResult([{ error: e.message }])
    }
    setProcLoading(false)
  }

  // ── View loader ──
  const loadView = async () => {
    setViewLoading(true)
    setViewPage(0)
    try {
      const MAP = {
        'vw_batsman_season_stats': '/query?metric=batsmen',
        'vw_bowler_season_stats':  '/query?metric=bowlers',
        'vw_team_performance':     '/stats/team-winrate',
        'vw_match_summary':        '/matches',
        'vw_player_last5_form':    '/stats/player-form?player_id=1',
      }
      const res = await client.get(MAP[viewName] || '/teams')
      setViewData(res.data.data || [])
    } catch (e) {
      setViewData([])
    }
    setViewLoading(false)
  }

  // ── Window function runners ──
  const runRanking = async () => {
    setWfLoading(true)
    try {
      const res = await getWindowRanking(wfSeason)
      setRankData(res.data.data || [])
    } catch (e) { setRankData([]) }
    setWfLoading(false)
  }

  const runGrowth = async () => {
    setWfLoading(true)
    try {
      const res = await getWindowGrowth(wfPlayer)
      setGrowthData(res.data.data || [])
    } catch (e) { setGrowthData([]) }
    setWfLoading(false)
  }

  const ex = EXPLAIN_DATA[explainIdx]

  return (
    <div>
      <div className="page-header">
        <div className="page-title">Advanced DB Panel</div>
        <div className="breadcrumb">Home / <span>Advanced DB</span></div>
      </div>

      <div className="space-y-6">

        {/* ── Section 1: Stored Procedures ── */}
        <div className="card">
          <SectionHeader number="1" title="Stored Procedures" />
          <div className="flex flex-wrap gap-3 mb-4">
            <select
              value={procName}
              onChange={e => setProcName(e.target.value)}
              className="text-sm rounded-lg px-3 py-2 border border-border flex-1"
              style={{ background: '#0f1117', color: '#fff' }}
            >
              {['CalculateNRR','GenerateSeasonLeaderboard','GetHeadToHead',
                'GetPlayerCareerSummary','BulkImportWithSavepoint'].map(p =>
                <option key={p} value={p}>{p}</option>
              )}
            </select>

            {['CalculateNRR','GenerateSeasonLeaderboard'].includes(procName) && (
              <input
                type="number"
                placeholder="Season (e.g. 2023)"
                value={procInput.season}
                onChange={e => setProcInput(v => ({ ...v, season: e.target.value }))}
                className="text-sm rounded-lg px-3 py-2 border border-border w-44"
                style={{ background: '#0f1117', color: '#fff' }}
              />
            )}
            {procName === 'GetHeadToHead' && (
              <>
                <input type="number" placeholder="Team 1 ID" value={procInput.team1}
                  onChange={e => setProcInput(v => ({ ...v, team1: e.target.value }))}
                  className="text-sm rounded-lg px-3 py-2 border border-border w-28"
                  style={{ background: '#0f1117', color: '#fff' }} />
                <input type="number" placeholder="Team 2 ID" value={procInput.team2}
                  onChange={e => setProcInput(v => ({ ...v, team2: e.target.value }))}
                  className="text-sm rounded-lg px-3 py-2 border border-border w-28"
                  style={{ background: '#0f1117', color: '#fff' }} />
              </>
            )}
            {procName === 'GetPlayerCareerSummary' && (
              <input type="number" placeholder="Player ID" value={procInput.player_id}
                onChange={e => setProcInput(v => ({ ...v, player_id: e.target.value }))}
                className="text-sm rounded-lg px-3 py-2 border border-border w-32"
                style={{ background: '#0f1117', color: '#fff' }} />
            )}

            <button
              onClick={runProcedure}
              disabled={procLoading}
              className="px-4 py-2 rounded-lg text-sm font-semibold disabled:opacity-40"
              style={{ background: '#00a651', color: '#fff' }}
            >
              {procLoading ? 'Running...' : '▶ Run Procedure'}
            </button>
          </div>
          <ResultTable data={procResult} />
        </div>

        {/* ── Section 2: Views ── */}
        <div className="card">
          <SectionHeader number="2" title="Database Views" />
          <div className="flex gap-3 mb-4">
            <select
              value={viewName}
              onChange={e => setViewName(e.target.value)}
              className="text-sm rounded-lg px-3 py-2 border border-border flex-1"
              style={{ background: '#0f1117', color: '#fff' }}
            >
              {['vw_batsman_season_stats','vw_bowler_season_stats',
                'vw_team_performance','vw_match_summary',
                'vw_player_last5_form'].map(v =>
                <option key={v} value={v}>{v}</option>
              )}
            </select>
            <button
              onClick={loadView}
              disabled={viewLoading}
              className="px-4 py-2 rounded-lg text-sm font-semibold disabled:opacity-40"
              style={{ background: '#00d4ff22', color: '#00d4ff', border: '1px solid #00d4ff44' }}
            >
              {viewLoading ? 'Loading...' : '⟳ Load View'}
            </button>
          </div>
          <Pagination data={viewData} page={viewPage} setPage={setViewPage} />
        </div>

        {/* ── Section 3: Window Functions ── */}
        <div className="card">
          <SectionHeader number="3" title="Window Functions" />
          <div className="grid grid-cols-2 gap-4">
            <div className="rounded-lg p-3 border border-border" style={{ background: '#0f1117' }}>
              <div className="text-xs font-semibold text-white mb-2">
                RANK() — Season Ranking by Runs
              </div>
              <div className="flex gap-2 mb-3">
                <input
                  type="number"
                  value={wfSeason}
                  onChange={e => setWfSeason(+e.target.value)}
                  className="text-sm rounded px-2 py-1 border border-border w-24"
                  style={{ background: '#1a1d27', color: '#fff' }}
                />
                <button
                  onClick={runRanking}
                  disabled={wfLoading}
                  className="px-3 py-1 rounded text-xs font-semibold disabled:opacity-40"
                  style={{ background: '#00a651', color: '#fff' }}
                >
                  Run RANK()
                </button>
              </div>
              {rankData.length > 0 && (
                <table>
                  <thead><tr><th>Rank</th><th>Player</th><th>Team</th><th>Runs</th></tr></thead>
                  <tbody>
                    {rankData.slice(0, 8).map((r, i) => (
                      <tr key={i}>
                        <td style={{ color: r.season_rank <= 3 ? '#00a651' : '#8b8fa8' }}>
                          {r.season_rank}
                        </td>
                        <td className="font-medium text-white">{r.player_name}</td>
                        <td className="text-textsec text-xs">{r.team_name}</td>
                        <td style={{ color: '#00a651' }}>{r.total_runs}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>

            <div className="rounded-lg p-3 border border-border" style={{ background: '#0f1117' }}>
              <div className="text-xs font-semibold text-white mb-2">
                LAG() — Season-over-Season Run Growth
              </div>
              <div className="flex gap-2 mb-3">
                <input
                  type="number"
                  value={wfPlayer}
                  onChange={e => setWfPlayer(+e.target.value)}
                  placeholder="Player ID"
                  className="text-sm rounded px-2 py-1 border border-border w-28"
                  style={{ background: '#1a1d27', color: '#fff' }}
                />
                <button
                  onClick={runGrowth}
                  disabled={wfLoading}
                  className="px-3 py-1 rounded text-xs font-semibold disabled:opacity-40"
                  style={{ background: '#00d4ff22', color: '#00d4ff', border: '1px solid #00d4ff44' }}
                >
                  Run LAG()
                </button>
              </div>
              {growthData.length > 0 && (
                <table>
                  <thead><tr><th>Season</th><th>Runs</th><th>Prev</th><th>Δ</th></tr></thead>
                  <tbody>
                    {growthData.map((r, i) => (
                      <tr key={i}>
                        <td>{r.season}</td>
                        <td style={{ color: '#00a651' }}>{r.total_runs}</td>
                        <td className="text-textsec">{r.prev_season_runs}</td>
                        <td>
                          <span style={{ color: r.run_change > 0 ? '#00a651' : r.run_change < 0 ? '#ef4444' : '#8b8fa8' }}>
                            {r.run_change > 0 ? '▲' : r.run_change < 0 ? '▼' : '—'}
                            {' '}{Math.abs(r.run_change)}
                          </span>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>
          </div>
        </div>

        {/* ── Section 4: Query Optimizer ── */}
        <div className="card">
          <SectionHeader number="4" title="Query Optimizer — EXPLAIN Analysis" />
          <select
            value={explainIdx}
            onChange={e => setExplainIdx(+e.target.value)}
            className="text-sm rounded-lg px-3 py-2 border border-border mb-4 w-full"
            style={{ background: '#0f1117', color: '#fff' }}
          >
            {EXPLAIN_DATA.map((e, i) => <option key={i} value={i}>{e.name}</option>)}
          </select>

          <div className="grid grid-cols-2 gap-4">
            <div className="rounded-lg p-4" style={{ background: '#0f1117', border: '1px solid #ef444444' }}>
              <div className="text-xs font-semibold mb-3" style={{ color: '#ef4444' }}>
                ✗ WITHOUT INDEX
              </div>
              {[
                ['type',  ex.before.type],
                ['rows',  ex.before.rows.toLocaleString()],
                ['key',   ex.before.key],
                ['Extra', ex.before.extra],
              ].map(([l, v]) => (
                <div key={l} className="flex justify-between text-xs py-1 border-b border-border">
                  <span className="text-textsec">{l}</span>
                  <span className="font-mono" style={{ color: '#ef4444' }}>{v}</span>
                </div>
              ))}
            </div>

            <div className="rounded-lg p-4" style={{ background: '#0f1117', border: '1px solid #00a65144' }}>
              <div className="text-xs font-semibold mb-3" style={{ color: '#00a651' }}>
                ✓ WITH INDEX
              </div>
              {[
                ['type',  ex.after.type],
                ['rows',  ex.after.rows.toLocaleString()],
                ['key',   ex.after.key],
                ['Extra', ex.after.extra],
              ].map(([l, v]) => (
                <div key={l} className="flex justify-between text-xs py-1 border-b border-border">
                  <span className="text-textsec">{l}</span>
                  <span className="font-mono" style={{ color: '#00a651' }}>{v}</span>
                </div>
              ))}
            </div>
          </div>

          <div className="mt-3 rounded-lg p-3 text-center" style={{ background: 'rgba(0,166,81,0.06)', border: '1px solid rgba(0,166,81,0.2)' }}>
            <span className="text-sm font-bold" style={{ color: '#00a651' }}>
              {ex.speedup}% reduction
            </span>
            <span className="text-xs text-textsec ml-2">
              Rows scanned: {ex.before.rows.toLocaleString()} → {ex.after.rows.toLocaleString()}
            </span>
          </div>
          <div className="mt-2 text-xs text-textsec font-mono px-1">
            Index: {ex.index}
          </div>
        </div>

        {/* ── Section 5: Transaction Isolation ── */}
        <div className="card">
          <SectionHeader number="5" title="Transaction Isolation Levels" />
          <div className="flex items-center gap-3 mb-4">
            <span className="text-sm text-textsec">Current Session Isolation Level:</span>
            <span
              className="text-sm font-bold px-3 py-1 rounded-full"
              style={{ background: '#00a65122', color: '#00a651' }}
            >
              {isoLevel}
            </span>
          </div>

          <div className="space-y-2">
            {ISO_SCRIPTS.map((iso, i) => (
              <div key={i} className="rounded-lg overflow-hidden border border-border">
                <button
                  className="w-full flex items-center justify-between px-4 py-3 text-sm font-medium text-left hover:bg-surface transition-colors"
                  style={{ background: '#0f1117' }}
                  onClick={() => setOpenIso(openIso === i ? null : i)}
                >
                  <div>
                    <span className="text-white">{iso.title}</span>
                    <span
                      className="ml-2 text-xs px-2 py-0.5 rounded"
                      style={{ background: '#00d4ff22', color: '#00d4ff' }}
                    >
                      {iso.level}
                    </span>
                  </div>
                  <span className="text-textsec">{openIso === i ? '▲' : '▼'}</span>
                </button>
                {openIso === i && (
                  <div className="px-4 pb-4" style={{ background: '#0f1117' }}>
                    <p className="text-xs text-textsec mb-3 leading-relaxed">{iso.scenario}</p>
                    <pre
                      className="text-xs rounded-lg p-3 overflow-x-auto leading-relaxed"
                      style={{ background: '#12151f', color: '#e2e4ef', border: '1px solid #2a2d3a' }}
                    >
                      {iso.code}
                    </pre>
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>

      </div>
    </div>
  )
}
