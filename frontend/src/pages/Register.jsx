import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { apiError } from '../api/client'
import ErrorMessage from '../components/ErrorMessage'
import { useAuth } from '../context/AuthContext'

export default function Register() {
  const { register } = useAuth()
  const navigate = useNavigate()
  const [fullName, setFullName] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [submitting, setSubmitting] = useState(false)

  async function onSubmit(e) {
    e.preventDefault()
    setError('')
    setSubmitting(true)
    try {
      await register(fullName, email, password)
      navigate('/')
    } catch (err) {
      setError(apiError(err, 'Could not create account'))
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="auth-card">
      <h1>Create your account</h1>
      <p className="muted">Start planning smarter trips today.</p>
      <ErrorMessage message={error} />
      <form onSubmit={onSubmit}>
        <label>
          Full name
          <input
            type="text"
            value={fullName}
            onChange={(e) => setFullName(e.target.value)}
            required
          />
        </label>
        <label>
          Email
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
          />
        </label>
        <label>
          Password
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            minLength={8}
            required
          />
          <small className="muted">At least 8 characters.</small>
        </label>
        <button className="btn btn-primary" disabled={submitting}>
          {submitting ? 'Creating…' : 'Create account'}
        </button>
      </form>
      <p className="muted">
        Already have an account? <Link to="/login">Log in</Link>
      </p>
    </div>
  )
}
