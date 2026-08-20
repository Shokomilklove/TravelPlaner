import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { apiError, tripsApi } from '../api/client'
import ErrorMessage from '../components/ErrorMessage'

const CURRENCIES = ['USD', 'EUR', 'GBP', 'ILS', 'JPY']

export default function NewTrip() {
  const navigate = useNavigate()
  const [form, setForm] = useState({
    title: '',
    origin: '',
    destination: '',
    start_date: '',
    end_date: '',
    budget_amount: '',
    budget_currency: 'USD',
    travelers: 1,
    interests: '',
  })
  const [error, setError] = useState('')
  const [submitting, setSubmitting] = useState(false)

  function update(key, value) {
    setForm((f) => ({ ...f, [key]: value }))
  }

  async function onSubmit(e) {
    e.preventDefault()
    setError('')
    setSubmitting(true)
    try {
      const payload = {
        origin: form.origin,
        destination: form.destination,
        start_date: form.start_date,
        end_date: form.end_date,
        travelers: Number(form.travelers) || 1,
        budget_currency: form.budget_currency,
      }
      if (form.title.trim()) payload.title = form.title.trim()
      if (form.budget_amount !== '') payload.budget_amount = Number(form.budget_amount)
      const interests = form.interests
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean)
      if (interests.length) payload.preferences = { interests }

      const { data } = await tripsApi.create(payload)
      navigate(`/trips/${data.trip.id}`)
    } catch (err) {
      setError(apiError(err, 'Could not create trip'))
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div>
      <div className="page-head">
        <h1>New trip</h1>
      </div>
      <ErrorMessage message={error} />
      <form className="card form-grid" onSubmit={onSubmit}>
        <label className="span-2">
          Trip title <span className="muted">(optional)</span>
          <input
            type="text"
            value={form.title}
            placeholder="e.g. Summer in Rome"
            onChange={(e) => update('title', e.target.value)}
          />
        </label>
        <label>
          Origin
          <input
            type="text"
            value={form.origin}
            placeholder="e.g. Tel Aviv"
            onChange={(e) => update('origin', e.target.value)}
            required
          />
        </label>
        <label>
          Destination
          <input
            type="text"
            value={form.destination}
            placeholder="e.g. Rome"
            onChange={(e) => update('destination', e.target.value)}
            required
          />
        </label>
        <label>
          Start date
          <input
            type="date"
            value={form.start_date}
            onChange={(e) => update('start_date', e.target.value)}
            required
          />
        </label>
        <label>
          End date
          <input
            type="date"
            value={form.end_date}
            onChange={(e) => update('end_date', e.target.value)}
            required
          />
        </label>
        <label>
          Budget <span className="muted">(optional)</span>
          <input
            type="number"
            min="0"
            step="1"
            value={form.budget_amount}
            placeholder="e.g. 2000"
            onChange={(e) => update('budget_amount', e.target.value)}
          />
        </label>
        <label>
          Currency
          <select
            value={form.budget_currency}
            onChange={(e) => update('budget_currency', e.target.value)}
          >
            {CURRENCIES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </label>
        <label>
          Travelers
          <input
            type="number"
            min="1"
            max="50"
            value={form.travelers}
            onChange={(e) => update('travelers', e.target.value)}
          />
        </label>
        <label className="span-2">
          Interests <span className="muted">(comma separated)</span>
          <input
            type="text"
            value={form.interests}
            placeholder="e.g. food, history, museums, nightlife"
            onChange={(e) => update('interests', e.target.value)}
          />
        </label>
        <div className="span-2 form-actions">
          <button className="btn btn-primary" disabled={submitting}>
            {submitting ? 'Creating…' : 'Create trip'}
          </button>
        </div>
      </form>
    </div>
  )
}
