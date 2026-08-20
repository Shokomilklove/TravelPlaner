import { render } from '@testing-library/react'
import { expect, test } from 'vitest'
import ItineraryView from './ItineraryView'

const itinerary = {
  provider: 'mock',
  model_used: 'test-model',
  currency: 'USD',
  total_estimated_cost: 750,
  plan: {
    summary: '3 days in Rome',
    currency: 'USD',
    total_estimated_cost: 750,
    flights: [{ title: 'TLV-FCO', estimated_cost: 300, currency: 'USD' }],
    accommodation: [{ title: 'Hotel Roma', estimated_cost: 400, currency: 'USD' }],
    activities: [{ title: 'Colosseum', estimated_cost: 50, currency: 'USD' }],
    days: [{ day: 1, date: '2026-08-01', title: 'Arrival', items: [] }],
    budget_analysis: {
      within_budget: true,
      budget: 2000,
      delta: 1250,
      currency: 'USD',
      suggestions: ['Within budget with USD 1250.00 to spare.'],
    },
  },
}

test('renders itinerary summary and sections', () => {
  const { container } = render(<ItineraryView itinerary={itinerary} />)
  const text = container.textContent
  expect(text).toContain('3 days in Rome')
  expect(text).toContain('Flights')
  expect(text).toContain('Hotel Roma')
  expect(text).toContain('Within budget')
})

test('renders nothing when itinerary is missing', () => {
  const { container } = render(<ItineraryView itinerary={null} />)
  expect(container.textContent).toBe('')
})
