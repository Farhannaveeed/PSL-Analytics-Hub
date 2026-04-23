import { useEffect, useState } from 'react'
import { getMatches, getTeams } from '../api/stats'
import MatchDrawer from '../components/MatchDrawer'

const SEASONS = ['', 2020, 2021, 2022, 2023, 2024, 2025]

export default function Matches() {
  const [matches, setMatches]   = useState([])
  const [teams, setTeams]       = useState([])
  const [season, setSeason]     = useState('')
  const [teamId, setTeamId]     = useState('')
  const [selected, setSelected] = useState(null)
  const [loading, setLoading]   = useState(false)

  useEffect(() => {
    getTeams().then(r => setTeams(r.data.data || []))
  }, [])

  useEffect(() => {
    setLoading(true)
    const params = {}
    if (season) params.season  = season
    if (teamId) params.team_id = teamId
    getMatches(params)
      .then(r => setMatches(r.data.data || []))
      .finally(() => setLoading(false))
  }, [season, teamId])

  const typeBadge = (t) => {
    const colors = { league: '#8b8fa8', playoff: '#f97316', final: '#00a651' }
    return (
      <span
        className="text-xs font-semibold px-2 py-0.5 rounded"
        style={{ background: (colors[t] || '#8b8fa8') + '22', color: colors[t] || '#8b8fa8' }}
      >
        {t?.toUpperCase()}
      </span>
    )
  }

  return (
    <div>
      <div className="page-header">
        <div className="page-title">Match Explorer</div>
        <div className="breadcrumb">Home / <span>Matches</span></div>
      </div>

      {/* Filters */}
      <div className="flex gap-3 mb-5">
        <select
          value={season}
          onChange={e => setSeason(e.target.value)}
          className="text-sm rounded-lg px-3 py-2 border border-border"
          style={{ background: '#1a1d27', color: '#fff' }}
        >
          {SEASONS.map(s => <option key={s} value={s}>{s || 'All Seasons'}</option>)}
        </select>
        <select
          value={teamId}
          onChange={e => setTeamId(e.target.value)}
          className="text-sm rounded-lg px-3 py-2 border border-border"
          style={{ background: '#1a1d27', color: '#fff' }}
        >
          <option value="">All Teams</option>
          {teams.map(t => <option key={t.team_id} value={t.team_id}>{t.team_name}</option>)}
        </select>
        <div className="text-sm text-textsec ml-auto self-center">
          {matches.length} matches
        </div>
      </div>

      {loading ? (
        <div className="text-center text-textsec py-12">Loading matches...</div>
      ) : (
        <div className="card overflow-x-auto">
          <table>
            <thead>
              <tr>
                <th>Date</th><th>Teams</th><th>Winner</th>
                <th>Margin</th><th>Venue</th><th>POTM</th><th>Type</th>
              </tr>
            </thead>
            <tbody>
              {matches.map(m => (
                <tr
                  key={m.match_id}
                  className="cursor-pointer"
                  onClick={() => setSelected(m)}
                >
                  <td className="text-textsec text-xs whitespace-nowrap">{m.match_date}</td>
                  <td>
                    <span className="font-medium text-white text-sm">{m.team1_name}</span>
                    <span className="text-textsec mx-1 text-xs">vs</span>
                    <span className="font-medium text-white text-sm">{m.team2_name}</span>
                  </td>
                  <td className="font-semibold" style={{ color: '#00a651' }}>
                    {m.winner_name || <span className="text-textsec">—</span>}
                  </td>
                  <td className="text-xs text-textsec">
                    {m.win_by_runs > 0 && `${m.win_by_runs}r`}
                    {m.win_by_wickets > 0 && `${m.win_by_wickets}w`}
                  </td>
                  <td className="text-xs text-textsec max-w-xs truncate">{m.venue}</td>
                  <td className="text-xs">{m.player_of_match_name || '—'}</td>
                  <td>{typeBadge(m.match_type)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <MatchDrawer match={selected} onClose={() => setSelected(null)} />
    </div>
  )
}
