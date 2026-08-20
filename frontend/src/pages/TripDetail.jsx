import { useCallback, useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { apiError, tripsApi } from '../api/client'
import ErrorMessage from '../components/ErrorMessage'
import ItineraryView from '../components/ItineraryView'
import Spinner from '../components/Spinner'

export default function TripDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const [trip, setTrip] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [planning, setPlanning] = useState(false)
  const [busy, setBusy] = useState(false)

  const load = useCallback(async () => {
    try {
      const { data } = await tripsApi.get(id)
      setTrip(data.trip)
    } catch (err) {
      setError(apiError(err, 'Trip not found'))
    } finally {
      setLoading(false)
    }
  }, [id])

  useEffect(() => {
    load()
  }, [load])

  async function onPlan() {
    setError('')
    setPlanning(true)
    try {
      await tripsApi.plan(id)
      await load()
    } catch (err) {
      setError(
        apiError(err, 'AI planning failed. Verify the AI provider configuration.'),
      )
    } finally {
      setPlanning(false)
    }
  }

  async function onToggleSave() {
    setBusy(true)
    setError('')
    try {
      if (trip.is_saved) {
        await tripsApi.unsave(id)
      } else {
        await tripsApi.save(id)
      }
      await load()
    } catch (err) {
      setError(apiError(err))
    } finally {
      setBusy(false)
    }
  }

  async function onDelete() {
    if (!window.confirm('Delete this trip? This cannot be undone.')) return
    setBusy(true)
    setError('')
    try {
      await tripsApi.remove(id)
      navigate('/')
    } catch (err) {
      setError(apiError(err))
      setBusy(false)
    }
  }

  if (loading) return <Spinner />
  if (!trip) return <ErrorMessage message={error || 'Trip not found'} />

  const itinerary = trip.itinerary

  return (
    <div>
      <div className="page-head">
        <div>
          <h1>{trip.title}</h1>
          <p className="muted">
            {trip.origin} → {trip.destination} · {trip.start_date} → {trip.end_date} ·{' '}
            {trip.travelers} traveler(s)
          </p>
        </div>
        <div className="actions">
          <button className="btn btn-ghost" onClick={onToggleSave} disabled={busy}>
            {trip.is_saved ? '★ Unsave' : '☆ Save'}
          </button>
          <button className="btn btn-danger" onClick={onDelete} disabled={busy}>
            Delete
          </button>
        </div>
      </div>

      <ErrorMessage message={error} />

      <div className="card">
        <div className="detail-grid">
          <div>
            <span className="muted">Status</span>
            <div className="detail-value">{trip.status}</div>
          </div>
          <div>
            <span className="muted">Budget</span>
            <div className="detail-value">
              {trip.budget_amount
                ? `${trip.budget_currency} ${trip.budget_amount}`
                : '—'}
            </div>
          </div>
          <div>
            <span className="muted">Travelers</span>
            <div className="detail-value">{trip.travelers}</div>
          </div>
          {trip.preferences?.interests?.length ? (
            <div>
              <span className="muted">Interests</span>
              <div className="detail-value">
                {trip.preferences.interests.join(', ')}
              </div>
            </div>
          ) : null}
        </div>
      </div>

      <div className="page-head">
        <h2>Itinerary</h2>
        <button className="btn btn-primary" onClick={onPlan} disabled={planning}>
          {planning ? 'Planning…' : itinerary ? 'Re-plan with AI' : 'Plan with AI'}
        </button>
      </div>

      {planning ? <Spinner label="Generating your itinerary…" /> : null}
      {!planning && itinerary ? <ItineraryView itinerary={itinerary} /> : null}
      {!planning && !itinerary ? (
        <p className="muted">No itinerary yet. Click “Plan with AI” to generate one.</p>
      ) : null}
    </div>
  )
}
