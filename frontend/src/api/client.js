import axios from 'axios'

// The frontend talks ONLY to the Trip Service (Backend A).
// Empty base URL => same origin (production nginx proxies /api to the service).
const baseURL = import.meta.env.VITE_TRIP_SERVICE_URL || ''

const api = axios.create({ baseURL })

// Attach the JWT to every request.
api.interceptors.request.use((config) => {
  const token = localStorage.getItem('token')
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

// Clear a dead session on 401 so route guards can redirect to login.
api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response && error.response.status === 401) {
      localStorage.removeItem('token')
      localStorage.removeItem('user')
    }
    return Promise.reject(error)
  },
)

export const authApi = {
  register: (data) => api.post('/api/auth/register', data),
  login: (data) => api.post('/api/auth/login', data),
  me: () => api.get('/api/auth/me'),
}

export const tripsApi = {
  list: (params) => api.get('/api/trips', { params }),
  create: (data) => api.post('/api/trips', data),
  get: (id) => api.get(`/api/trips/${id}`),
  update: (id, data) => api.put(`/api/trips/${id}`, data),
  remove: (id) => api.delete(`/api/trips/${id}`),
  plan: (id) => api.post(`/api/trips/${id}/plan`),
  save: (id) => api.post(`/api/trips/${id}/save`),
  unsave: (id) => api.post(`/api/trips/${id}/unsave`),
}

export function apiError(err, fallback = 'Something went wrong. Please try again.') {
  return err?.response?.data?.message || fallback
}

export default api
