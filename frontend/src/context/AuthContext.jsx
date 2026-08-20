import { createContext, useContext, useState } from 'react'
import { authApi } from '../api/client'

const AuthContext = createContext(null)

export function AuthProvider({ children }) {
  const [user, setUser] = useState(() => {
    const raw = localStorage.getItem('user')
    return raw ? JSON.parse(raw) : null
  })

  function persist(token, nextUser) {
    localStorage.setItem('token', token)
    localStorage.setItem('user', JSON.stringify(nextUser))
    setUser(nextUser)
  }

  async function login(email, password) {
    const { data } = await authApi.login({ email, password })
    persist(data.access_token, data.user)
    return data.user
  }

  async function register(fullName, email, password) {
    const { data } = await authApi.register({
      full_name: fullName,
      email,
      password,
    })
    persist(data.access_token, data.user)
    return data.user
  }

  function logout() {
    localStorage.removeItem('token')
    localStorage.removeItem('user')
    setUser(null)
  }

  const value = { user, login, register, logout, isAuthenticated: !!user }
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) {
    throw new Error('useAuth must be used within an AuthProvider')
  }
  return ctx
}
