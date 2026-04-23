import { Routes, Route } from 'react-router-dom'
import Sidebar    from './components/Sidebar'
import Dashboard  from './pages/Dashboard'
import Teams      from './pages/Teams'
import Players    from './pages/Players'
import Matches    from './pages/Matches'
import Analytics  from './pages/Analytics'
import Advanced   from './pages/Advanced'

export default function App() {
  return (
    <div className="flex min-h-screen" style={{ background: '#0f1117' }}>
      <Sidebar />
      <main
        className="flex-1 overflow-y-auto"
        style={{ marginLeft: 240, padding: '2rem 2.5rem', minHeight: '100vh' }}
      >
        <Routes>
          <Route path="/"          element={<Dashboard />} />
          <Route path="/teams"     element={<Teams />} />
          <Route path="/players"   element={<Players />} />
          <Route path="/matches"   element={<Matches />} />
          <Route path="/analytics" element={<Analytics />} />
          <Route path="/advanced"  element={<Advanced />} />
        </Routes>
      </main>
    </div>
  )
}
