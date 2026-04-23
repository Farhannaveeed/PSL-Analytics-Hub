export default function StatCard({ label, value, sub, accent = '#00a651' }) {
  return (
    <div className="card flex flex-col gap-1">
      <div className="text-xs font-semibold uppercase tracking-widest" style={{ color: '#8b8fa8' }}>
        {label}
      </div>
      <div className="text-3xl font-bold" style={{ color: accent }}>
        {value ?? '—'}
      </div>
      {sub && (
        <div className="text-xs" style={{ color: '#8b8fa8' }}>
          {sub}
        </div>
      )}
    </div>
  )
}
