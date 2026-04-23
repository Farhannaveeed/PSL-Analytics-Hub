import { useEffect, useState } from 'react'
import {
  getSummary, getTopBatsmen, getTopBowlers, getNRR,
} from '../api/stats'
import StatCard from '../components/StatCard'

const SEASONS = [2020, 2021, 2022, 2023, 2024, 2025]

function fmt(n) {
  if (n === undefined || n === null) return '—'
  if (n >= 1000000) return (n / 1000000).toFixed(1) + 'M'
  if (n >= 1000) return (n / 1000).toFixed(1) + 'K'
  return n
}

export default function Dashboard() {
  const [summary, setSummary]   = useState({})
  const [season, setSeason]     = useState(2023)
  const [batsmen, setBatsmen]   = useState([])
  const [bowlers, setBowlers]   = useState([])
  const [nrr, setNrr]           = useState([])
  const [loading, setLoading]   = useState(false)

  useEffect(() => {
    getSummary().then(r => setSummary(r.data.data || {}))
  }, [])

  useEffect(() => {
    setLoading(true)
    Promise.all([
      getTopBatsmen(season),
      getTopBowlers(season),
      getNRR(season),
    ]).then(([b, bw, n]) => {
      setBatsmen(b.data.data || [])
      setBowlers(bw.data.data || [])
      setNrr(n.data.data || [])
    }).finally(() => setLoading(false))
  }, [season])

  return (
    <div>
      <div className="page-header flex items-center justify-between">
        <div>
          <div className="page-title">Dashboard</div>
          <div className="breadcrumb">Home / <span>Dashboard</span></div>
        </div>
        <div className="flex items-center gap-2">
          <label className="text-sm text-textsec">Season</label>
          <select
            value={season}
            onChange={e => setSeason(+e.target.value)}
            className="text-sm rounded-lg px-3 py-1.5 border border-border"
            style={{ background: '#1a1d27', color: '#fff' }}
          >
            {SEASONS.map(s => <option key={s} value={s}>{s}</option>)}
          </select>
        </div>
      </div>

      {/* Stat cards */}
      <div className="grid grid-cols-4 gap-4 mb-6">
        <StatCard label="Total Matches"   value={fmt(summary.total_matches)}   sub="All seasons" />
        <StatCard label="Total Players"   value={fmt(summary.total_players)}   sub="All franchises" accent="#00d4ff" />
        <StatCard label="Total Runs"      value={fmt(summary.total_runs)}      sub="All innings" accent="#f97316" />
        <StatCard label="Seasons Covered" value={summary.seasons_covered}      sub="2020 – 2025" accent="#a855f7" />
      </div>

      {loading ? (
        <div className="text-center text-textsec py-12">Loading season data...</div>
      ) : (
        <div className="grid grid-cols-12 gap-4">
          {/* Top batsmen */}
          <div className="col-span-5 card">
            <div className="text-sm font-bold text-white mb-3">
              Top Batsmen — {season}
            </div>
            <table>
              <thead>
                <tr>
                  <th>#</th><th>Player</th><th>Team</th>
                  <th>Runs</th><th>SR</th><th>M</th>
                </tr>
              </thead>
              <tbody>
                {batsmen.slice(0, 5).map((b, i) => (
                  <tr key={b.player_id}>
                    <td><span style={{ color: i === 0 ? '#00a651' : '#8b8fa8' }}>{i + 1}</span></td>
                    <td className="font-medium text-white">{b.player_name}</td>
                    <td className="text-textsec text-xs">{b.team_name}</td>
                    <td className="font-bold" style={{ color: '#00a651' }}>{b.total_runs}</td>
                    <td>{b.strike_rate}</td>
                    <td className="text-textsec">{b.matches_played}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Top bowlers */}
          <div className="col-span-4 card">
            <div className="text-sm font-bold text-white mb-3">
              Top Bowlers — {season}
            </div>
            <table>
              <thead>
                <tr>
                  <th>#</th><th>Player</th>
                  <th>Wkts</th><th>Eco</th><th>M</th>
                </tr>
              </thead>
              <tbody>
                {bowlers.slice(0, 5).map((b, i) => (
                  <tr key={b.player_id}>
                    <td><span style={{ color: i === 0 ? '#00d4ff' : '#8b8fa8' }}>{i + 1}</span></td>
                    <td className="font-medium text-white">{b.player_name}</td>
                    <td className="font-bold" style={{ color: '#00d4ff' }}>{b.total_wickets}</td>
                    <td>{b.economy}</td>
                    <td className="text-textsec">{b.matches_played}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* NRR */}
          <div className="col-span-3 card">
            <div className="text-sm font-bold text-white mb-3">NRR — {season}</div>
            <table>
              <thead>
                <tr><th>Team</th><th>NRR</th></tr>
              </thead>
              <tbody>
                {nrr.map((n, i) => (
                  <tr key={n.team_id}>
                    <td className="text-xs">{n.team_name?.replace(' Kings','').replace(' Qalandars','').replace(' Gladiators','').replace(' Zalmi','').replace(' United','').replace(' Sultans','')}</td>
                    <td>
                      <span
                        className="font-bold text-sm"
                        style={{ color: parseFloat(n.nrr) >= 0 ? '#00a651' : '#ef4444' }}
                      >
                        {parseFloat(n.nrr) >= 0 ? '+' : ''}{n.nrr}
                      </span>
                    </td>
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
