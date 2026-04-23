import { useEffect, useState } from 'react'
import { getTeams, getTeamWinRate, getHeadToHead } from '../api/stats'

const TEAM_COLORS = {
  1: '#1a56db',  // Karachi Kings — blue
  2: '#e02424',  // Lahore Qalandars — red
  3: '#9061f9',  // Quetta Gladiators — purple
  4: '#ff9800',  // Peshawar Zalmi — orange
  5: '#0e9f6e',  // Islamabad United — green
  6: '#d97706',  // Multan Sultans — amber
}

export default function Teams() {
  const [teams, setTeams]       = useState([])
  const [winRates, setWinRates] = useState([])
  const [expanded, setExpanded] = useState(null)
  const [h2hT1, setH2hT1]      = useState('')
  const [h2hT2, setH2hT2]      = useState('')
  const [h2h, setH2h]           = useState(null)
  const [h2hLoading, setH2hLoading] = useState(false)

  useEffect(() => {
    getTeams().then(r => setTeams(r.data.data || []))
    getTeamWinRate().then(r => {
      const all = r.data.data || []
      // aggregate across all seasons
      const map = {}
      all.forEach(row => {
        if (!map[row.team_id]) map[row.team_id] = { ...row, wins: 0, matches_played: 0, total_runs_scored: 0 }
        map[row.team_id].wins           += row.wins || 0
        map[row.team_id].matches_played += row.matches_played || 0
        map[row.team_id].total_runs_scored += row.total_runs_scored || 0
      })
      setWinRates(Object.values(map))
    })
  }, [])

  const getStats = (teamId) => winRates.find(w => w.team_id === teamId) || {}

  const runH2H = () => {
    if (!h2hT1 || !h2hT2 || h2hT1 === h2hT2) return
    setH2hLoading(true)
    getHeadToHead(h2hT1, h2hT2)
      .then(r => setH2h(r.data.data))
      .finally(() => setH2hLoading(false))
  }

  return (
    <div>
      <div className="page-header">
        <div className="page-title">Teams</div>
        <div className="breadcrumb">Home / <span>Teams</span></div>
      </div>

      {/* Team cards grid */}
      <div className="grid grid-cols-3 gap-4 mb-8">
        {teams.map(t => {
          const stats = getStats(t.team_id)
          const color = TEAM_COLORS[t.team_id] || '#00a651'
          const isOpen = expanded === t.team_id
          return (
            <div key={t.team_id} className="card cursor-pointer" onClick={() => setExpanded(isOpen ? null : t.team_id)}>
              <div className="flex items-center gap-3 mb-2">
                <div
                  className="w-10 h-10 rounded-lg flex items-center justify-center text-white font-bold text-lg"
                  style={{ background: color }}
                >
                  {t.team_name[0]}
                </div>
                <div>
                  <div className="font-bold text-white">{t.team_name}</div>
                  <div className="text-xs text-textsec">{t.city}</div>
                </div>
                <div className="ml-auto text-textsec text-sm">{isOpen ? '▲' : '▼'}</div>
              </div>
              <div className="text-xs text-textsec">🏟 {t.home_ground}</div>
              <div className="text-xs text-textsec">Founded: {t.founded_year}</div>

              {isOpen && (
                <div className="mt-3 pt-3 border-t border-border grid grid-cols-2 gap-2">
                  {[
                    ['Matches', stats.matches_played],
                    ['Wins', stats.wins],
                    ['Win %', stats.matches_played ? ((stats.wins / stats.matches_played) * 100).toFixed(1) + '%' : '—'],
                    ['Runs Scored', stats.total_runs_scored?.toLocaleString() || '—'],
                  ].map(([l, v]) => (
                    <div key={l} className="rounded p-2" style={{ background: '#0f1117' }}>
                      <div className="text-xs text-textsec">{l}</div>
                      <div className="font-bold text-sm" style={{ color }}>{v ?? '—'}</div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )
        })}
      </div>

      {/* Head-to-head */}
      <div className="card">
        <div className="text-sm font-bold text-white mb-4">Head-to-Head Analysis</div>
        <div className="flex items-center gap-3 mb-4">
          <select
            value={h2hT1}
            onChange={e => setH2hT1(e.target.value)}
            className="flex-1 text-sm rounded-lg px-3 py-2 border border-border"
            style={{ background: '#0f1117', color: '#fff' }}
          >
            <option value="">Select Team 1</option>
            {teams.map(t => <option key={t.team_id} value={t.team_id}>{t.team_name}</option>)}
          </select>
          <span className="text-textsec font-bold">vs</span>
          <select
            value={h2hT2}
            onChange={e => setH2hT2(e.target.value)}
            className="flex-1 text-sm rounded-lg px-3 py-2 border border-border"
            style={{ background: '#0f1117', color: '#fff' }}
          >
            <option value="">Select Team 2</option>
            {teams.map(t => <option key={t.team_id} value={t.team_id}>{t.team_name}</option>)}
          </select>
          <button
            onClick={runH2H}
            disabled={!h2hT1 || !h2hT2 || h2hT1 === h2hT2 || h2hLoading}
            className="px-4 py-2 rounded-lg text-sm font-semibold transition-all disabled:opacity-40"
            style={{ background: '#00a651', color: '#fff' }}
          >
            {h2hLoading ? 'Loading...' : 'Fetch H2H'}
          </button>
        </div>

        {h2h && (
          <div>
            {/* Summary row */}
            {h2h.summary && h2h.summary[0] && (
              <div className="grid grid-cols-4 gap-3 mb-4">
                {[
                  ['Total Matches', h2h.summary[0].total_matches, '#8b8fa8'],
                  [teams.find(t => t.team_id == h2hT1)?.team_name + ' Wins', h2h.summary[0].team1_wins, '#00a651'],
                  [teams.find(t => t.team_id == h2hT2)?.team_name + ' Wins', h2h.summary[0].team2_wins, '#00d4ff'],
                  ['Favourite Venue', h2h.summary[0].favourite_venue, '#f97316'],
                ].map(([l, v, c]) => (
                  <div key={l} className="rounded-lg p-3 text-center" style={{ background: '#0f1117' }}>
                    <div className="font-bold text-lg" style={{ color: c }}>{v ?? '—'}</div>
                    <div className="text-xs text-textsec mt-0.5">{l}</div>
                  </div>
                ))}
              </div>
            )}

            {/* Venue breakdown */}
            {h2h.venue_breakdown && h2h.venue_breakdown.length > 0 && (
              <table>
                <thead>
                  <tr>
                    <th>Venue</th><th>Matches</th>
                    <th>{teams.find(t => t.team_id == h2hT1)?.team_name} Wins</th>
                    <th>{teams.find(t => t.team_id == h2hT2)?.team_name} Wins</th>
                  </tr>
                </thead>
                <tbody>
                  {h2h.venue_breakdown.map(v => (
                    <tr key={v.venue}>
                      <td className="font-medium">{v.venue}</td>
                      <td>{v.matches_at_venue}</td>
                      <td style={{ color: '#00a651' }}>{v.team1_venue_wins}</td>
                      <td style={{ color: '#00d4ff' }}>{v.team2_venue_wins}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        )}
      </div>
    </div>
  )
}
