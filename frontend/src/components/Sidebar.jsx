import { NavLink } from 'react-router-dom'

const NAV = [
  { to: '/',          label: 'Dashboard',    icon: '⊞' },
  { to: '/teams',     label: 'Teams',        icon: '🏏' },
  { to: '/players',   label: 'Players',      icon: '👤' },
  { to: '/matches',   label: 'Match Explorer', icon: '📅' },
  { to: '/analytics', label: 'Analytics',    icon: '📊' },
  { to: '/advanced',  label: 'Advanced DB',  icon: '🗄️' },
]

export default function Sidebar() {
  return (
    <aside
      className="fixed left-0 top-0 h-screen flex flex-col z-30"
      style={{ width: 240, background: '#12151f', borderRight: '1px solid #2a2d3a' }}
    >
      {/* Brand */}
      <div className="px-6 py-5 border-b border-border">
        <div className="flex items-center gap-2">
          <div
            className="w-8 h-8 rounded-lg flex items-center justify-center text-sm font-bold"
            style={{ background: '#00a651' }}
          >
            P
          </div>
          <div>
            <div className="text-sm font-bold text-white leading-none">PSL Analytics</div>
            <div className="text-xs mt-0.5" style={{ color: '#8b8fa8' }}>ADBMS Dashboard</div>
          </div>
        </div>
      </div>

      {/* Nav */}
      <nav className="flex-1 px-3 py-4 space-y-1 overflow-y-auto">
        {NAV.map(({ to, label, icon }) => (
          <NavLink
            key={to}
            to={to}
            end={to === '/'}
            className={({ isActive }) =>
              `flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-all ${
                isActive
                  ? 'text-white'
                  : 'text-textsec hover:text-white hover:bg-surface'
              }`
            }
            style={({ isActive }) =>
              isActive ? { background: 'rgba(0,166,81,0.15)', color: '#00a651' } : {}
            }
          >
            <span className="text-base w-5 text-center">{icon}</span>
            {label}
          </NavLink>
        ))}
      </nav>

      {/* Footer */}
      <div className="px-5 py-4 border-t border-border">
        <div className="text-xs" style={{ color: '#8b8fa8' }}>
          PSL Seasons 2020–2025
        </div>
        <div className="text-xs mt-0.5" style={{ color: '#2a2d3a' }}>
          MySQL 8.0 · Flask · React
        </div>
      </div>
    </aside>
  )
}
