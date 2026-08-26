export type ForecastRow = Record<string, number | string> & { date: string }

export type Adjustment = {
  id: string
  variable: string
  label: string
  value: number
  displayValue: number
  unit: string
  start: string
  end: string
}

export type Scenario = {
  id: string
  name: string
  notes: string
  status: 'baseline' | 'running' | 'completed' | 'failed'
  createdAt: string | null
  completedAt: string | null
  adjustments: Adjustment[]
  results?: ForecastRow[]
  error?: string
}

export type Bootstrap = { baseline: Scenario; scenarios: Scenario[] }
