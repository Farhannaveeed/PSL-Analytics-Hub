import { useEffect, useState } from 'react'
import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell,
} from 'recharts'
import { getCareer, getPlayerForm, getPlayerRating } from '../api/stats'

const SEASONS = [2020, 2021, 2022, 2023, 2024, 2025]

function RatingBadge({ rating }) {
  const r = parseFloat(rating) || 0
  const color = r >= 70 ? '#00a651' : r >= 40 ? '#f97316' : '#ef4444'
  const label = r >= 70 ? 'Elite' : r >= 40 ? 'Good' : 'Developing'
  return (
    <span
      className="text-xs font-bold px-3 py-1 rounded-full"
      style={{ background: `${color}22`, color }}
    >
      {r.toFixed(1)} — {label}
    </span>
  )
}

export default function PlayerModal({ player, onClose }) {
  const [career, setCareer]   = useState(null)
  const [form, setForm]       = useState([])
  const [rating, setRating]   = useState(null)
  const [season, setSeason]   = useState(2023)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!player) return
    setLoading(true)
    Promise.all([
      getCareer(player.player_id),
      getPlayerForm(player.player_id),
      getPlayerRating(player.player_id, season),
    ]).then(([c, f, r]) => {
      setCareer(c.data.data)
      setForm(f.data.data || [])
      setRating(r.data.data?.rating ?? 0)
    }).finally(() => setLoading(false))
  }, [player, season])

  if (!player) return null

  const roleBadgeClass = {
    batsman: 'badge-batsman',
    bowler: 'badge-bowler',
    allrounder: 'badge-allrounder',
    wicketkeeper: 'badge-wicketkeeper',
  }[player.role] || 'badge-batsman'

  const formChartData = [...form].reverse().map((f, i) => ({
    match: `M${i + 1}`,
    runs: f.runs_scored,
    wickets: f.wickets_taken,
  }))

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4"
      style={{ background: 'rgba(0,0,0,0.75)', backdropFilter: 'blur(4px)' }}
      onClick={onClose}
    >
      <div
        className="card w-full max-w-2xl max-h-[90vh] overflow-y-auto"
        onClick={e => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-start justify-between mb-4">
          <div>
            <div className="text-xl font-bold text-white">{player.player_name}</div>
            <div className="flex items-center gap-2 mt-1">
              <span className={`badge ${roleBadgeClass}`}>{player.role}</span>
              <span className="text-xs text-textsec">{player.nationality}</span>
              <span className="text-xs text-textsec">· {player.team_name}</span>
            </div>
          </div>
          <button
            onClick={onClose}
            className="text-textsec hover:text-white transition-colors text-xl leading-none"
          >
            ✕
          </button>
        </div>

        {/* Player info */}
        <div className="grid grid-cols-2 gap-3 text-sm mb-4">
          <div className="rounded-lg p-3" style={{ background: '#0f1117' }}>
            <div className="text-textsec text-xs mb-0.5">Batting Style</div>
            <div className="font-medium">{player.batting_style}</div>
          </div>
          <div className="rounded-lg p-3" style={{ background: '#0f1117' }}>
            <div className="text-textsec text-xs mb-0.5">Bowling Style</div>
            <div className="font-medium">{player.bowling_style}</div>
          </div>
        </div>

        {/* Rating */}
        <div className="flex items-center gap-3 mb-4">
          <div className="text-sm text-textsec">Season</div>
          <select
            value={season}
            onChange={e => setSeason(+e.target.value)}
            className="text-sm rounded-lg px-2 py-1 border border-border"
            style={{ background: '#0f1117', color: '#fff' }}
          >
            {SEASONS.map(s => <option key={s} value={s}>{s}</option>)}
          </select>
          <div className="text-sm text-textsec">Rating:</div>
          <RatingBadge rating={rating} />
        </div>

        {loading ? (
          <div className="text-center text-textsec py-8">Loading stats...</div>
        ) : (
          <>
            {/* Career stats */}
            {career && (
              <div className="grid grid-cols-5 gap-2 mb-5">
                {[
                  ['Career Runs', career.career_runs],
                  ['Career Wkts', career.career_wickets],
                  ['Seasons', career.seasons_played],
                  ['Best Runs', career.best_season_runs],
                  ['Best Year', career.best_season_year],
                ].map(([l, v]) => (
                  <div key={l} className="rounded-lg p-2 text-center" style={{ background: '#0f1117' }}>
                    <div className="text-lg font-bold" style={{ color: '#00a651' }}>{v ?? '—'}</div>
                    <div className="text-xs text-textsec mt-0.5">{l}</div>
                  </div>
                ))}
              </div>
            )}

            {/* Last 5 form */}
            {formChartData.length > 0 && (
              <div>
                <div className="text-xs font-semibold uppercase tracking-widest text-textsec mb-2">
                  Last 5 Matches Form
                </div>
                <ResponsiveContainer width="100%" height={120}>
                  <BarChart data={formChartData} barGap={4}>
                    <XAxis dataKey="match" tick={{ fill: '#8b8fa8', fontSize: 11 }} axisLine={false} tickLine={false} />
                    <YAxis tick={{ fill: '#8b8fa8', fontSize: 11 }} axisLine={false} tickLine={false} />
                    <Tooltip
                      contentStyle={{ background: '#1a1d27', border: '1px solid #2a2d3a', borderRadius: 8 }}
                      labelStyle={{ color: '#8b8fa8' }}
                    />
                    <Bar dataKey="runs" name="Runs" radius={[4,4,0,0]}>
                      {formChartData.map((_, i) => (
                        <Cell key={i} fill="#00a651" fillOpacity={0.85} />
                      ))}
                    </Bar>
                    <Bar dataKey="wickets" name="Wkts" radius={[4,4,0,0]}>
                      {formChartData.map((_, i) => (
                        <Cell key={i} fill="#00d4ff" fillOpacity={0.85} />
                      ))}
                    </Bar>
                  </BarChart>
                </ResponsiveContainer>
                <div className="flex gap-4 mt-1 justify-end">
                  <span className="text-xs text-textsec flex items-center gap-1">
                    <span className="w-3 h-3 rounded-sm inline-block" style={{ background: '#00a651' }} /> Runs
                  </span>
                  <span className="text-xs text-textsec flex items-center gap-1">
                    <span className="w-3 h-3 rounded-sm inline-block" style={{ background: '#00d4ff' }} /> Wickets
                  </span>
                </div>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  )
}
