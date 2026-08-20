import { Link } from 'react-router-dom'

const STATUS_LABEL = { draft: 'Draft', planning: 'Planning', planned: 'Planned' }

export default function TripCard({ trip }) {
  return (
    <Link to={`/trips/${trip.id}`} className="card trip-card">
      <div className="trip-card-head">
        <h3>{trip.title}</h3>
        {trip.is_saved ? <span className="pill pill-saved">★ Saved</span> : null}
      </div>
      <p className="muted">
        {trip.origin} → {trip.destination}
      </p>
      <p className="muted">
        {trip.start_date} → {trip.end_date} · {trip.travelers} traveler(s)
      </p>
      <div className="trip-card-foot">
        <span className={`pill pill-${trip.status}`}>
          {STATUS_LABEL[trip.status] || trip.status}
        </span>
        {trip.budget_amount ? (
          <span className="muted">
            {trip.budget_currency} {trip.budget_amount}
          </span>
        ) : null}
      </div>
    </Link>
  )
}
