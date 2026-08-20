import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'

export default function Navbar() {
  const { user, isAuthenticated, logout } = useAuth()
  const navigate = useNavigate()

  function handleLogout() {
    logout()
    navigate('/login')
  }

  return (
    <nav className="navbar">
      <Link to="/" className="brand">
        <span aria-hidden="true">✈️</span> Travel Planner
      </Link>
      <div className="nav-links">
        {isAuthenticated ? (
          <>
            <Link to="/">Dashboard</Link>
            <Link to="/trips/new">New Trip</Link>
            <Link to="/saved">Saved</Link>
            <span className="nav-user">{user?.full_name}</span>
            <button className="btn btn-ghost" onClick={handleLogout}>
              Logout
            </button>
          </>
        ) : (
          <>
            <Link to="/login">Login</Link>
            <Link to="/register">Register</Link>
          </>
        )}
      </div>
    </nav>
  )
}
