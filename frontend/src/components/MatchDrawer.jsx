import { useEffect, useState } from 'react'
import { getInnings } from '../api/stats'

export default function MatchDrawer({ match, onClose }) {
  const [innings, setInnings] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!match) return
    setLoading(true)
    getInnings(match.match_id)
      .then(r => setInnings(r.data.data || []))
      .finally(() => setLoading(false))
  }, [match])

  if (!match) return null

  const inn1 = innings[0]
  const inn2 = innings[1]
  const maxRuns = Math.max(inn1?.total_runs || 0, inn2?.total_runs || 0, 1)

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center p-4"
      style={{ background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(2px)' }}
      onClick={onClose}
    >
      <div
        className="card w-full max-w-3xl"
        onClick={e => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between mb-4">
          <div>
            <div className="font-bold text-white">
              {match.team1_name} vs {match.team2_name}
            </div>
            <div className="text-xs text-textsec mt-0.5">
              {match.match_date} · {match.venue} · {match.match_type?.toUpperCase()}
            </div>
          </div>
          <button
            onClick={onClose}
            className="text-textsec hover:text-white text-xl leading-none"
          >
            ✕
          </button>
        </div>

        {loading ? (
          <div className="text-center text-textsec py-6">Loading innings...</div>
        ) : (
          <>
            {/* Result banner */}
            <div
              className="rounded-lg px-4 py-2 mb-4 text-sm font-semibold"
              style={{ background: 'rgba(0,166,81,0.1)', color: '#00a651', border: '1px solid rgba(0,166,81,0.2)' }}
            >
              Winner: {match.winner_name || 'No Result'}
              {match.win_by_runs > 0 && ` — by ${match.win_by_runs} runs`}
              {match.win_by_wickets > 0 && ` — by ${match.win_by_wickets} wickets`}
            </div>

            {/* Innings comparison bars */}
            <div className="space-y-4">
              {[inn1, inn2].filter(Boolean).map((inn, i) => (
                <div key={i}>
                  <div className="flex items-center justify-between mb-1">
                    <div className="text-sm font-medium">{inn.batting_team_name}</div>
                    <div className="text-sm font-bold" style={{ color: i === 0 ? '#00a651' : '#00d4ff' }}>
                      {inn.total_runs}/{inn.total_wickets}
                      <span className="text-xs text-textsec ml-1">({inn.total_overs} ov)</span>
                    </div>
                  </div>
                  <div className="h-5 rounded-full overflow-hidden" style={{ background: '#0f1117' }}>
                    <div
                      className="h-full rounded-full transition-all duration-500"
                      style={{
                        width: `${(inn.total_runs / maxRuns) * 100}%`,
                        background: i === 0 ? '#00a651' : '#00d4ff',
                        opacity: 0.85,
                      }}
                    />
                  </div>
                  <div className="text-xs text-textsec mt-1">
                    Extras: {inn.extras}
                  </div>
                </div>
              ))}
            </div>

            {/* POTM */}
            {match.player_of_match_name && (
              <div className="mt-4 flex items-center gap-2 text-sm">
                <span className="text-textsec">Player of the Match:</span>
                <span className="font-semibold" style={{ color: '#00a651' }}>
                  {match.player_of_match_name}
                </span>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  )
}
