import { useEffect, useState } from 'react'
import { getPlayers, getTeams } from '../api/stats'
import PlayerModal from '../components/PlayerModal'

const ROLES = ['', 'batsman', 'bowler', 'allrounder', 'wicketkeeper']

export default function Players() {
  const [players, setPlayers] = useState([])
  const [teams, setTeams]     = useState([])
  const [teamFilter, setTeamFilter] = useState('')
  const [roleFilter, setRoleFilter] = useState('')
  const [selected, setSelected]     = useState(null)
  const [loading, setLoading]       = useState(false)

  useEffect(() => {
    getTeams().then(r => setTeams(r.data.data || []))
  }, [])

  useEffect(() => {
    setLoading(true)
    const params = {}
    if (teamFilter) params.team_id = teamFilter
    if (roleFilter) params.role    = roleFilter
    getPlayers(params)
      .then(r => setPlayers(r.data.data || []))
      .finally(() => setLoading(false))
  }, [teamFilter, roleFilter])

  const roleBadge = (role) => {
    const classes = {
      batsman:     'badge-batsman',
      bowler:      'badge-bowler',
      allrounder:  'badge-allrounder',
      wicketkeeper:'badge-wicketkeeper',
    }
    return <span className={`badge ${classes[role] || ''}`}>{role}</span>
  }

  return (
    <div>
      <div className="page-header">
        <div className="page-title">Players</div>
        <div className="breadcrumb">Home / <span>Players</span></div>
      </div>

      {/* Filter bar */}
      <div className="flex items-center gap-3 mb-6">
        <select
          value={teamFilter}
          onChange={e => setTeamFilter(e.target.value)}
          className="text-sm rounded-lg px-3 py-2 border border-border"
          style={{ background: '#1a1d27', color: '#fff' }}
        >
          <option value="">All Teams</option>
          {teams.map(t => <option key={t.team_id} value={t.team_id}>{t.team_name}</option>)}
        </select>
        <select
          value={roleFilter}
          onChange={e => setRoleFilter(e.target.value)}
          className="text-sm rounded-lg px-3 py-2 border border-border"
          style={{ background: '#1a1d27', color: '#fff' }}
        >
          {ROLES.map(r => <option key={r} value={r}>{r || 'All Roles'}</option>)}
        </select>
        <div className="text-sm text-textsec ml-auto">
          {players.length} players
        </div>
      </div>

      {loading ? (
        <div className="text-center text-textsec py-12">Loading players...</div>
      ) : (
        <div className="grid grid-cols-4 gap-3">
          {players.map(p => (
            <div
              key={p.player_id}
              className="card cursor-pointer hover:border-green transition-colors"
              style={{ borderColor: undefined }}
              onClick={() => setSelected(p)}
            >
              <div className="flex items-start justify-between mb-2">
                <div
                  className="w-9 h-9 rounded-lg flex items-center justify-center text-white font-bold"
                  style={{ background: '#00a65122', color: '#00a651', fontSize: 14 }}
                >
                  {p.player_name[0]}
                </div>
                {roleBadge(p.role)}
              </div>
              <div className="font-semibold text-white text-sm leading-tight">{p.player_name}</div>
              <div className="text-xs text-textsec mt-1">{p.nationality}</div>
              <div className="text-xs text-textsec mt-0.5">{p.team_name}</div>
            </div>
          ))}
        </div>
      )}

      <PlayerModal player={selected} onClose={() => setSelected(null)} />
    </div>
  )
}
