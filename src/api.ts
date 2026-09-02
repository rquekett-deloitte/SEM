import type { Adjustment, Bootstrap, Scenario } from './types'

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, { cache: 'no-store', ...init })
  const data = await response.json().catch(() => null)
  if (!data) throw new Error('The model service returned an invalid response.')
  if (!response.ok) throw new Error(data.message || 'The request could not be completed.')
  return data
}

export const api = {
  bootstrap: () => request<Bootstrap>('/api/bootstrap'),
  scenario: (id: string) => request<Scenario>(`/api/scenarios/${id}`),
  run: (payload: { name: string; notes: string; adjustments: Adjustment[] }) =>
    request<Scenario>('/api/scenarios', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    }),
}
