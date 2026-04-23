import { useEffect, useState } from 'react'
import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer,
  LineChart, Line, CartesianGrid, Legend, Cell,
} from 'recharts'
import {
  getVenueAnalysis, getBoundaries, getSeasonTrend, getTeamWinRate,
} from '../api/stats'

const SEASONS = [2020, 2021, 2022, 2023, 2024, 2025]

const TIP = {
  contentStyle: { background: '#1a1d27', border: '1px solid #2a2d3a', borderRadius: 8 },
  labelStyle:   { color: '#8b8fa8' },
  cursor:       { fill: 'rgba(255,255,255,0.04)' },
}

export default function Analytics() {
  const [venues, setVenues]       = useState([])
  const [boundaries, setBoundaries] = useState([])
  const [trend, setTrend]         = useState([])
  const [winRate, setWinRate]     = useState([])
  const [bSeason, setBSeason]     = useState(2023)
  const [loading, setLoading]     = useState(false)

  useEffect(() => {
    setLoading(true)
    Promise.all([
      getVenueAnalysis(),
      getSeasonTrend(),
      getTeamWinRate(),
    ]).then(([v, t, w]) => {
      setVenues(v.data.data || [])
      setTrend(t.data.data || [])
      // aggregate win rate across all seasons
      const map = {}
      ;(w.data.data || []).forEach(row => {
        if (!map[row.team_name]) map[row.team_name] = { team_name: row.team_name, wins: 0, matches: 0 }
        map[row.team_name].wins    += row.wins || 0
        map[row.team_name].matches += row.matches_played || 0
      })
      const arr = Object.values(map).map(r => ({
        ...r,
        win_pct: r.matches > 0 ? Math.round((r.wins / r.matches) * 100) : 0,
      })).sort((a, b) => b.win_pct - a.win_pct)
      setWinRate(arr)
    }).finally(() => setLoading(false))
  }, [])

  useEffect(() => {
    getBoundaries(bSeason).then(r => setBoundaries(r.data.data || []))
  }, [bSeason])

  const shortName = (n) => n?.split(' ').slice(-1)[0] || n

  return (
    <div>
      <div className="page-header">
        <div className="page-title">Analytics</div>
        <div className="breadcrumb">Home / <span>Analytics</span></div>
      </div>

      {loading ? (
        <div className="text-center text-textsec py-12">Loading analytics...</div>
      ) : (
        <div className="space-y-5">
          {/* Row 1: Venue avg scores + Season run trend */}
          <div className="grid grid-cols-2 gap-4">
            <div className="card">
              <div className="text-sm font-bold text-white mb-4">Average Score by Venue</div>
              <ResponsiveContainer width="100%" height={220}>
                <BarChart layout="vertical" data={venues} margin={{ left: 10, right: 20 }}>
                  <XAxis type="number" tick={{ fill: '#8b8fa8', fontSize: 11 }} axisLine={false} tickLine={false} />
                  <YAxis dataKey="venue" type="category" tick={{ fill: '#8b8fa8', fontSize: 10 }} width={160} axisLine={false} tickLine={false}
                    tickFormatter={v => v?.replace('Stadium','').replace('Cricket','').replace('National','').trim()}
                  />
                  <Tooltip {...TIP} formatter={v => [v, 'Avg Score']} />
                  <Bar dataKey="avg_score" name="Avg Score" radius={[0,4,4,0]}>
                    {venues.map((_, i) => (
                      <Cell key={i} fill={i % 2 === 0 ? '#00a651' : '#00d4ff'} />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </div>

            <div className="card">
              <div className="text-sm font-bold text-white mb-4">Season Run Trend (2020–2025)</div>
              <ResponsiveContainer width="100%" height={220}>
                <LineChart data={trend} margin={{ left: 0, right: 20 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#2a2d3a" />
                  <XAxis dataKey="season" tick={{ fill: '#8b8fa8', fontSize: 11 }} axisLine={false} tickLine={false} />
                  <YAxis tick={{ fill: '#8b8fa8', fontSize: 11 }} axisLine={false} tickLine={false}
                    tickFormatter={v => (v / 1000).toFixed(0) + 'K'}
                  />
                  <Tooltip {...TIP} formatter={v => [v?.toLocaleString(), 'Total Runs']} />
                  <Line
                    type="monotone" dataKey="total_runs" stroke="#00a651"
                    strokeWidth={2} dot={{ fill: '#00a651', r: 4 }}
                  />
                </LineChart>
              </ResponsiveContainer>
            </div>
          </div>

          {/* Row 2: Boundaries + Win Rate */}
          <div className="grid grid-cols-2 gap-4">
            <div className="card">
              <div className="flex items-center justify-between mb-4">
                <div className="text-sm font-bold text-white">Boundary Analysis</div>
                <select
                  value={bSeason}
                  onChange={e => setBSeason(+e.target.value)}
                  className="text-xs rounded px-2 py-1 border border-border"
                  style={{ background: '#0f1117', color: '#fff' }}
                >
                  {SEASONS.map(s => <option key={s} value={s}>{s}</option>)}
                </select>
              </div>
              <ResponsiveContainer width="100%" height={220}>
                <BarChart data={boundaries} margin={{ left: 0, right: 10 }}>
                  <XAxis dataKey="team_name" tick={{ fill: '#8b8fa8', fontSize: 10 }}
                    axisLine={false} tickLine={false}
                    tickFormatter={shortName}
                  />
                  <YAxis tick={{ fill: '#8b8fa8', fontSize: 11 }} axisLine={false} tickLine={false} />
                  <Tooltip {...TIP} />
                  <Legend wrapperStyle={{ color: '#8b8fa8', fontSize: 12 }} />
                  <Bar dataKey="fours" name="4s" stackId="a" fill="#00a651" radius={[0,0,0,0]} />
                  <Bar dataKey="sixes" name="6s" stackId="a" fill="#00d4ff" radius={[4,4,0,0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>

            <div className="card">
              <div className="text-sm font-bold text-white mb-4">Team Win Rate (All Seasons)</div>
              <ResponsiveContainer width="100%" height={220}>
                <BarChart layout="vertical" data={winRate} margin={{ left: 10, right: 30 }}>
                  <XAxis type="number" domain={[0, 100]} tick={{ fill: '#8b8fa8', fontSize: 11 }}
                    axisLine={false} tickLine={false} tickFormatter={v => v + '%'}
                  />
                  <YAxis dataKey="team_name" type="category" tick={{ fill: '#8b8fa8', fontSize: 10 }}
                    width={130} axisLine={false} tickLine={false}
                    tickFormatter={shortName}
                  />
                  <Tooltip {...TIP} formatter={v => [v + '%', 'Win Rate']} />
                  <Bar dataKey="win_pct" name="Win %" radius={[0,4,4,0]}>
                    {winRate.map((_, i) => (
                      <Cell key={i} fill={i === 0 ? '#00a651' : i === 1 ? '#00d4ff' : '#8b8fa855'} />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </div>
          </div>

          {/* Venue table */}
          <div className="card">
            <div className="text-sm font-bold text-white mb-3">Venue Statistics</div>
            <table>
              <thead>
                <tr>
                  <th>Venue</th><th>City</th><th>Matches</th>
                  <th>Avg Score</th><th>Bat-First Wins</th><th>Chase Wins</th>
                </tr>
              </thead>
              <tbody>
                {venues.map(v => (
                  <tr key={v.venue}>
                    <td className="font-medium">{v.venue}</td>
                    <td className="text-textsec">{v.city}</td>
                    <td>{v.total_matches}</td>
                    <td style={{ color: '#00a651' }}>{v.avg_score}</td>
                    <td>{v.bat_first_wins}</td>
                    <td>{v.chase_wins}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  )
}
