import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { apiError, tripsApi } from '../api/client'
import ErrorMessage from '../components/ErrorMessage'
import Spinner from '../components/Spinner'
import TripCard from '../components/TripCard'

export default function SavedTrips() {
  const [trips, setTrips] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    tripsApi
      .list({ saved: true })
      .then(({ data }) => setTrips(data.trips))
      .catch((err) => setError(apiError(err)))
      .finally(() => setLoading(false))
  }, [])

  return (
    <div>
      <div className="page-head">
        <h1>Saved trips</h1>
      </div>
      <ErrorMessage message={error} />
      {loading ? (
        <Spinner />
      ) : trips.length === 0 ? (
        <div className="empty">
          <p>You haven’t saved any trips yet.</p>
          <Link className="btn btn-primary" to="/">
            Back to dashboard
          </Link>
        </div>
      ) : (
        <div className="grid">
          {trips.map((trip) => (
            <TripCard key={trip.id} trip={trip} />
          ))}
        </div>
      )}
    </div>
  )
}
