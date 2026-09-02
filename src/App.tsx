import { useEffect, useState } from 'react'
import { Activity, BarChart3, BookOpen, ChevronDown, CircleHelp, Clock3, Database, Gauge, Menu, Play, Plus, RotateCcw, Settings2, X } from 'lucide-react'
import { api } from './api'
import type { Adjustment, ForecastRow, Scenario } from './types'
import { variableLabel } from './variables'

const controls = [
  { variable: 'Fpoil', label: 'Oil price', unit: '%', step: 1, factor: (v: number) => Math.log(1 + v / 100), description: 'World oil price path' },
  { variable: 'Lnom', label: 'Net overseas migration', unit: '%', step: 1, factor: (v: number) => Math.log(1 + v / 100), description: 'Quarterly NOM flow' },
  { variable: 'Cgov', label: 'Government consumption', unit: '%', step: 1, factor: (v: number) => Math.log(1 + v / 100), description: 'Real public consumption' },
  { variable: 'R90d', label: 'Short-term interest rate', unit: 'pp', step: 0.25, factor: (v: number) => v / 100, description: '90-day market rate' },
  { variable: 'Ustar', label: 'NAIRU', unit: 'pp', step: 0.1, factor: (v: number) => v, description: 'Long-run unemployment anchor' },
]

const initialVariable = 'Ygdp'
const rateVariables = new Set(['Lpar', 'Lur', 'R90d', 'R10y', 'Rmort', 'EqYield', 'R90dReal', 'R10yReal', 'RmortReal', 'RmortRealExgst', 'Fr10y', 'Fr10yReal', 'Rdif10y', 'Rbiz', 'RbizReal', 'RmortRealHpf', 'InflExp', 'Fr10yUs', 'Fr10yJp', 'Fr10yDe', 'Fr10yUk'])
type DisplayMode = 'quarterly-change' | 'annual-change' | 'level'

const quarter = (date: string) => `${date.slice(0, 4)} Q${Math.floor((Number(date.slice(5, 7)) - 1) / 3) + 1}`
const adjustmentValue = (adjustment: Adjustment) => {
  const value = adjustment.displayValue
  const formatted = new Intl.NumberFormat('en-AU', { maximumFractionDigits: 4 }).format(Math.abs(value))
  return `${value > 0 ? '+' : value < 0 ? '-' : ''}${formatted}${adjustment.unit === '%' ? '%' : ` ${adjustment.unit}`}`
}
const getValue = (row: ForecastRow, variable: string) => Number(row[variable])
const measureLabel = (variable: string, mode: DisplayMode) => {
  if (mode === 'quarterly-change') return 'Quarterly percentage change'
  if (mode === 'annual-change') return 'Annual percentage change'
  if (rateVariables.has(variable)) return 'Per cent'
  return 'Model level'
}
const metricValue = (rows: ForecastRow[], variable: string, mode: DisplayMode, index = rows.length - 1) => {
  if (!rows[index]) return null
  const publishedGrowth = Number(rows[index][`${variable}AnnualGrowth`])
  if (mode === 'annual-change') {
    if (Number.isFinite(publishedGrowth)) return publishedGrowth
    if (index < 4) return null
    const current = getValue(rows[index], variable)
    const previous = getValue(rows[index - 4], variable)
    const growth = 100 * (current / previous - 1)
    return Number.isFinite(growth) ? growth : null
  }
  if (mode === 'quarterly-change') {
    if (index < 1) return null
    const current = getValue(rows[index], variable)
    const previous = getValue(rows[index - 1], variable)
    const growth = 100 * (current / previous - 1)
    return Number.isFinite(growth) ? growth : null
  }
  const current = getValue(rows[index], variable)
  const value = rateVariables.has(variable) ? 100 * current : current
  return Number.isFinite(value) ? value : null
}

const comparisonPoints = (baseline: ForecastRow[], scenario: ForecastRow[], variable: string, mode: DisplayMode) => {
  const scenarioIndexes = new Map(scenario.map((row, index) => [row.date, index]))
  return baseline.flatMap((row, baselineIndex) => {
    const scenarioIndex = scenarioIndexes.get(row.date)
    if (scenarioIndex === undefined) return []
    const baselineValue = metricValue(baseline, variable, mode, baselineIndex)
    const scenarioValue = metricValue(scenario, variable, mode, scenarioIndex)
    if (baselineValue === null || scenarioValue === null) return []
    return [{ date: row.date, baseline: baselineValue, scenario: scenarioValue }]
  })
}

function LineChart({ baseline, scenario, variable, mode }: { baseline: ForecastRow[]; scenario: ForecastRow[]; variable: string; mode: DisplayMode }) {
  const width = 820
  const height = 330
  const padding = { top: 26, right: 34, bottom: 54, left: 82 }
  const points = comparisonPoints(baseline, scenario, variable, mode)
  if (points.length < 2) return <div className="chart-empty">No comparable forecast data is available for this metric.</div>
  const values = points.flatMap((point) => [point.baseline, point.scenario])
  let min = Math.min(...values)
  let max = Math.max(...values)
  const spread = max - min || 1
  min -= spread * 0.12
  max += spread * 0.12
  const x = (index: number) => padding.left + index * ((width - padding.left - padding.right) / (points.length - 1))
  const y = (value: number) => padding.top + (max - value) * ((height - padding.top - padding.bottom) / (max - min))
  const pathFor = (key: 'baseline' | 'scenario') => points.map((point, index) => `${index ? 'L' : 'M'} ${x(index).toFixed(1)} ${y(point[key]).toFixed(1)}`).join(' ')
  const ticks = Array.from({ length: 5 }, (_, index) => min + ((max - min) * index) / 4)
  const dateTicks = Array.from(new Set(Array.from({ length: 5 }, (_, index) => Math.round(index * (points.length - 1) / 4))))
  const percentage = measureLabel(variable, mode) !== 'Model level'
  const formatTick = (value: number) => percentage
    ? `${value.toFixed(1)}%`
    : new Intl.NumberFormat('en-AU', { notation: 'compact', maximumFractionDigits: 1 }).format(value)

  return (
    <div className="chart-wrap">
      <svg viewBox={`0 0 ${width} ${height}`} role="img" aria-label={`${variableLabel(variable)} forecast comparison`}>
        {ticks.map((tick) => <g key={tick}><line className="grid-line" x1={padding.left} x2={width - padding.right} y1={y(tick)} y2={y(tick)} /><text className="axis-label" x={padding.left - 14} y={y(tick) + 7} textAnchor="end">{formatTick(tick)}</text></g>)}
        {dateTicks.map((index) => <text key={index} className="axis-label" x={x(index)} y={height - 12} textAnchor={index === 0 ? 'start' : index === points.length - 1 ? 'end' : 'middle'}>{quarter(points[index].date).replace(' Q1', '')}</text>)}
        <path className="baseline-line" d={pathFor('baseline')} />
        <path className="scenario-line" d={pathFor('scenario')} />
      </svg>
    </div>
  )
}

function App() {
  const [activeView, setActiveView] = useState<'results' | 'library' | 'guide'>('results')
  const [baseline, setBaseline] = useState<Scenario | null>(null)
  const [scenarios, setScenarios] = useState<Scenario[]>([])
  const [selected, setSelected] = useState<Scenario | null>(null)
  const [selectedVariable, setSelectedVariable] = useState(initialVariable)
  const [name, setName] = useState('')
  const [notes, setNotes] = useState('')
  const [adjustments, setAdjustments] = useState<Adjustment[]>([])
  const [running, setRunning] = useState(false)
  const [error, setError] = useState('')
  const [mobileNav, setMobileNav] = useState(false)
  const [scenarioMenuOpen, setScenarioMenuOpen] = useState(false)
  const [reloadKey, setReloadKey] = useState(0)

  useEffect(() => {
    let active = true
    const refresh = async () => {
      try {
        const data = await api.bootstrap()
        if (!active) return
        setBaseline(data.baseline)
        setScenarios(data.scenarios)
        setSelected((current) => !current || current.id === 'baseline' ? data.baseline : current)
        setError('')
      } catch (reason) {
        if (active) setError(reason instanceof Error ? reason.message : 'Could not load the model workspace.')
      }
    }
    void refresh()
    const timer = window.setInterval(refresh, 30_000)
    const refreshWhenVisible = () => { if (document.visibilityState === 'visible') void refresh() }
    document.addEventListener('visibilitychange', refreshWhenVisible)
    return () => {
      active = false
      window.clearInterval(timer)
      document.removeEventListener('visibilitychange', refreshWhenVisible)
    }
  }, [reloadKey])

  useEffect(() => {
    if (!selected || selected.status !== 'running') return
    const timer = window.setInterval(() => {
      void (async () => {
        try {
          const updated = await api.scenario(selected.id)
          setSelected(updated)
          if (updated.status !== 'running') {
            setRunning(false)
            const data = await api.bootstrap()
            setBaseline(data.baseline)
            setScenarios(data.scenarios)
          }
        } catch (reason) {
          setError(reason instanceof Error ? reason.message : 'Could not refresh the scenario status.')
        }
      })()
    }, 1800)
    return () => window.clearInterval(timer)
  }, [selected])

  const addAdjustment = (control = controls[0]) => setAdjustments((current) => [...current, {
    id: crypto.randomUUID(), variable: control.variable, label: control.label, displayValue: 0, value: 0,
    unit: control.unit, start: '2025-03-01', end: '2026-12-01',
  }])

  const updateAdjustment = (id: string, patch: Partial<Adjustment>) => setAdjustments((current) => current.map((item) => {
    if (item.id !== id) return item
    const next = { ...item, ...patch }
    const control = controls.find((entry) => entry.variable === next.variable)!
    return { ...next, label: control.label, unit: control.unit, value: control.factor(Number(next.displayValue)) }
  }))

  const run = async () => {
    setError('')
    setRunning(true)
    try {
      const scenario = await api.run({ name, notes, adjustments })
      setSelected(scenario)
      setScenarios((current) => [scenario, ...current])
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'The scenario could not be started.')
      setRunning(false)
    }
  }

  const showScenario = async (scenario: Scenario) => {
    setError('')
    try {
      const updated = await api.scenario(scenario.id)
      if (updated.id === 'baseline') setBaseline(updated)
      setSelected(updated)
      setActiveView('results')
    } catch (reason) { setError(reason instanceof Error ? reason.message : 'Could not load this scenario.') }
  }

  const navigate = (view: typeof activeView) => {
    setActiveView(view)
    setMobileNav(false)
  }

  if (!baseline || !selected) return <div className="loading-screen"><span className="brand-dot" />{error ? <><span>{error}</span><button onClick={() => setReloadKey((key) => key + 1)}>Try again</button></> : 'Loading model workspace'}</div>
  const resultRows = selected.results || baseline.results || []
  const baselineRows = baseline.results || []
  const endDate = resultRows.at(-1)?.date || '2036-12-01'
  const availableVariables = Object.keys(baselineRows[0] || {})
    .filter((variable) => variable !== 'date' && !variable.endsWith('AnnualGrowth'))
    .sort((left, right) => variableLabel(left).localeCompare(variableLabel(right)))
  const baselineVintageMismatch = selected.id !== 'baseline' && selected.baselineVersion && selected.baselineVersion !== baseline.version

  return (
    <div className="app-shell">
      <aside className={mobileNav ? 'sidebar sidebar-open' : 'sidebar'}>
        <div className="brand"><span>Deloitte</span><span className="brand-dot" /></div>
        <button className="mobile-close" onClick={() => setMobileNav(false)} aria-label="Close navigation"><X size={20} /></button>
        <nav aria-label="Primary navigation">
          <button className={`nav-item ${activeView === 'results' ? 'active' : ''}`} onClick={() => navigate('results')}><BarChart3 size={18} />Results</button>
          <button className={`nav-item ${activeView === 'library' ? 'active' : ''}`} onClick={() => navigate('library')}><Database size={18} />Scenario library</button>
          <button className={`nav-item ${activeView === 'guide' ? 'active' : ''}`} onClick={() => navigate('guide')}><BookOpen size={18} />Model guide</button>
        </nav>
        <div className="sidebar-foot"><span className="status-dot" />Model ready<span>SEM v2026.2</span></div>
      </aside>

      <main>
        <header className="topbar">
          <button className="menu-button" onClick={() => setMobileNav(true)} aria-label="Open navigation"><Menu size={21} /></button>
          <div><h1>Scenario Economic Model</h1><p>Australian economy &middot; Quarterly model</p></div>
          <div className="top-actions"><button className="text-button" onClick={() => navigate('guide')}><CircleHelp size={17} />Help</button><div className="user-mark">RQ</div></div>
        </header>

        <div className={`workspace ${activeView === 'library' || activeView === 'guide' ? 'workspace-wide' : ''}`}>
          {activeView === 'results' && <>
          <section className="results-panel">
            <div className="scenario-heading">
              <div><div className="scenario-select-label">Viewing scenario</div><div className="scenario-select" onBlur={(event) => {
                if (!event.currentTarget.contains(event.relatedTarget)) setScenarioMenuOpen(false)
              }}><button className="scenario-select-trigger" type="button" aria-haspopup="listbox" aria-expanded={scenarioMenuOpen} onClick={() => setScenarioMenuOpen((open) => !open)}><span>{selected.name}</span><ChevronDown size={17} aria-hidden="true" /></button>
                {scenarioMenuOpen && <div className="scenario-menu" role="listbox" aria-label="Select scenario">
                  {[baseline, ...scenarios].map((scenario) => <button type="button" role="option" aria-selected={scenario.id === selected.id} className={scenario.id === selected.id ? 'selected' : ''} key={scenario.id} onClick={() => { setScenarioMenuOpen(false); void showScenario(scenario) }}><span><strong>{scenario.name}</strong><small>{scenario.id === 'baseline' ? 'Published baseline' : scenario.id}</small></span><i className={`scenario-menu-status ${scenario.status}`} /></button>)}
                </div>}
              </div></div>
              <div className={`run-badge ${selected.status}`}><span />{selected.status === 'baseline' ? 'Published baseline' : selected.status}</div>
            </div>
            {baseline.isStale && <div className="data-warning" role="status"><strong>Central forecast needs regeneration.</strong> The published forecast predates updated {baseline.staleSources?.join(', ')}. Run <code>Rscript run_model.R</code> before relying on these results.</div>}
            {baselineVintageMismatch && <div className="data-warning" role="status"><strong>Baseline vintage changed.</strong> This scenario was run against an earlier central forecast, so comparisons are not like-for-like.</div>}

            <section className="applied-shocks" aria-labelledby="applied-shocks-heading">
              <div className="applied-shocks-head">
                <div><h2 id="applied-shocks-heading">Applied shocks</h2><p>{selected.id === 'baseline' ? 'The published central forecast has no scenario shocks.' : `${selected.adjustments.length} ${selected.adjustments.length === 1 ? 'shock' : 'shocks'} stored with this run.`}</p></div>
                {selected.id !== 'baseline' && <span className="mono">{selected.id}</span>}
              </div>
              {selected.notes && <p className="scenario-notes"><strong>Scenario notes</strong>{selected.notes}</p>}
              {selected.adjustments.length > 0 ? <ul className="shock-list">
                {selected.adjustments.map((adjustment) => <li key={adjustment.id}>
                  <span className="shock-name"><strong>{adjustment.label}</strong><small>{adjustment.variable}</small></span>
                  <strong className="shock-value">{adjustmentValue(adjustment)}</strong>
                  <span className="shock-period">{quarter(adjustment.start)} to {quarter(adjustment.end)}</span>
                </li>)}
              </ul> : <div className="no-shocks">No shocks applied</div>}
            </section>

            <section className="chart-workspace" aria-labelledby="results-charts-heading">
              <div className="chart-toolbar">
                <div><h2 id="results-charts-heading">{variableLabel(selectedVariable)}</h2><p>Quarterly, annual and level views for the selected variable</p></div>
                <div className="chart-controls">
                  <label className="measure-control"><span>Measure</span><select value={selectedVariable} onChange={(event) => setSelectedVariable(event.target.value)}>{availableVariables.map((variable) => <option value={variable} key={variable}>{variableLabel(variable)} ({variable})</option>)}</select></label>
                </div>
              </div>

              <div className="chart-grid">
                {(['quarterly-change', 'annual-change', 'level'] as DisplayMode[]).map((displayMode) => {
                  const points = comparisonPoints(baselineRows, resultRows, selectedVariable, displayMode)
                  const chartStartDate = points[0]?.date || resultRows[0]?.date
                  const latest = points.at(-1)
                  const percentage = measureLabel(selectedVariable, displayMode) !== 'Model level'
                  const latestValue = latest ? (percentage ? `${latest.scenario.toFixed(1)}%` : new Intl.NumberFormat('en-AU', { notation: 'compact', maximumFractionDigits: 2 }).format(latest.scenario)) : 'Not available'
                  return <article className="chart-section" key={displayMode}>
                    <div className="chart-header"><div><h3>{displayMode === 'quarterly-change' ? 'Quarterly' : displayMode === 'annual-change' ? 'Annual' : 'Level'} <span>{selectedVariable}</span></h3><p>{measureLabel(selectedVariable, displayMode)} &middot; {chartStartDate ? quarter(chartStartDate) : 'No data'} to {quarter(endDate)}</p></div><div className="chart-latest"><span>Latest</span><strong>{latestValue}</strong></div></div>
                    <div className="legend"><span><i className="legend-scenario" />{selected.name}</span><span><i className="legend-baseline" />Central forecast</span></div>
                    <LineChart baseline={baselineRows} scenario={resultRows} variable={selectedVariable} mode={displayMode} />
                  </article>
                })}
              </div>
              <p className="chart-source">Source: Deloitte Access Economics macro scenario model. Central forecast generated {baseline.createdAt ? new Date(baseline.createdAt).toLocaleString('en-AU', { dateStyle: 'medium', timeStyle: 'short' }) : 'date unavailable'} &middot; Version <span className="mono">{baseline.version || 'unknown'}</span>.</p>
            </section>

            <section className="library">
              <div className="section-header"><div><h2>Recent scenarios</h2><p>Stored runs and their latest status</p></div><button className="text-button" onClick={() => document.getElementById('scenario-name')?.focus()}>New scenario <Plus size={16} /></button></div>
              <div className="scenario-table" role="table" aria-label="Recent scenarios">
                <div className="table-row table-head" role="row"><span>Name</span><span>Run ID</span><span>Created</span><span>Status</span></div>
                {[baseline, ...scenarios].slice(0, 5).map((scenario) => <button className="table-row" role="row" key={scenario.id} onClick={() => showScenario(scenario)}>
                  <span><strong>{scenario.name}</strong><small>{scenario.adjustments.length} assumption changes</small></span><span className="mono">{scenario.id}</span><span>{scenario.createdAt ? new Date(scenario.createdAt).toLocaleDateString('en-AU') : 'Current'}</span><span className={`table-status ${scenario.status}`}><i />{scenario.status === 'baseline' ? 'Ready' : scenario.status}</span>
                </button>)}
              </div>
            </section>
          </section>

          <aside className="scenario-builder">
            <div className="builder-head"><div><h2>Build a scenario</h2><p>Changes are applied to the central forecast.</p></div><Settings2 size={20} /></div>
            <label className="field"><span>Scenario name</span><input id="scenario-name" value={name} onChange={(event) => setName(event.target.value)} placeholder="e.g. Higher oil prices" /></label>
            <label className="field"><span>Notes <em>optional</em></span><textarea value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="Purpose or key assumptions" rows={2} /></label>
            <div className="assumption-head"><div><strong>Adjustments</strong><span>{adjustments.length} applied</span></div><button onClick={() => addAdjustment()}><Plus size={15} />Add</button></div>
            <div className="adjustments">
              {adjustments.length === 0 && <div className="empty-adjustments"><Gauge size={22} /><strong>No changes yet</strong><p>Add an assumption to create a scenario, or run an unchanged baseline copy.</p></div>}
              {adjustments.map((item) => <div className="adjustment" key={item.id}>
                <div className="adjustment-top"><select value={item.variable} onChange={(event) => updateAdjustment(item.id, { variable: event.target.value })}>{controls.map((control) => <option key={control.variable} value={control.variable}>{control.label}</option>)}</select><button onClick={() => setAdjustments((current) => current.filter((entry) => entry.id !== item.id))} aria-label={`Remove ${item.label}`}><X size={16} /></button></div>
                <p>{controls.find((control) => control.variable === item.variable)?.description}</p>
                <div className="value-input"><button onClick={() => updateAdjustment(item.id, { displayValue: item.displayValue - (controls.find((c) => c.variable === item.variable)?.step || 1) })}>&minus;</button><input type="number" step={controls.find((c) => c.variable === item.variable)?.step} value={item.displayValue} onChange={(event) => updateAdjustment(item.id, { displayValue: Number(event.target.value) })} aria-label={`${item.label} change`} /><span>{item.unit}</span><button onClick={() => updateAdjustment(item.id, { displayValue: item.displayValue + (controls.find((c) => c.variable === item.variable)?.step || 1) })}>+</button></div>
                <div className="date-range"><label><span>From</span><select value={item.start} onChange={(event) => updateAdjustment(item.id, { start: event.target.value })}>{baselineRows.map((row) => <option value={row.date} key={row.date}>{quarter(row.date)}</option>)}</select></label><label><span>To</span><select value={item.end} onChange={(event) => updateAdjustment(item.id, { end: event.target.value })}>{baselineRows.map((row) => <option value={row.date} key={row.date}>{quarter(row.date)}</option>)}</select></label></div>
              </div>)}
            </div>
            {error && <div className="error-message" role="alert">{error}</div>}
            {selected.status === 'failed' && selected.error && <div className="error-message" role="alert">{selected.error}</div>}
            <div className="builder-summary"><span><Clock3 size={15} />Typical run: 1-3 min</span><button className="reset-button" onClick={() => { setAdjustments([]); setName(''); setNotes('') }}><RotateCcw size={14} />Reset</button></div>
            <button className="run-button" onClick={run} disabled={running || !name.trim()}>{running ? <><Activity className="spin" size={18} />Running model...</> : <><Play size={18} fill="currentColor" />Run scenario</>}</button>
            <p className="run-copy">A unique run ID and complete input snapshot will be stored automatically.</p>
          </aside>
          </>}

          {activeView === 'library' && <section className="wide-panel">
            <div className="page-heading"><div><h2>Scenario library</h2><p>Open a stored run to review its results and compare it with the central forecast.</p></div><button className="primary-small" onClick={() => navigate('results')}><Plus size={16} />New scenario</button></div>
            <div className="library-summary"><span><strong>{scenarios.length}</strong> stored scenarios</span><span><strong>{scenarios.filter((item) => item.status === 'completed').length}</strong> completed runs</span><span><strong>2025 Q1</strong> forecast origin</span><span><strong>2036 Q4</strong> forecast horizon</span></div>
            <div className="scenario-table full-table" role="table" aria-label="Scenario library">
              <div className="table-row table-head" role="row"><span>Name</span><span>Run ID</span><span>Created</span><span>Status</span></div>
              {[baseline, ...scenarios].map((scenario) => <button className="table-row" role="row" key={scenario.id} onClick={() => showScenario(scenario)}>
                <span><strong>{scenario.name}</strong><small>{scenario.notes || `${scenario.adjustments.length} assumption changes`}</small></span><span className="mono">{scenario.id}</span><span>{scenario.createdAt ? new Date(scenario.createdAt).toLocaleString('en-AU', { dateStyle: 'medium', timeStyle: 'short' }) : 'Current baseline'}</span><span className={`table-status ${scenario.status}`}><i />{scenario.status === 'baseline' ? 'Ready' : scenario.status}</span>
              </button>)}
            </div>
          </section>}

          {activeView === 'guide' && <section className="wide-panel guide-page">
            <div className="page-heading"><div><h2>Model guide</h2><p>How to define, run and interpret a Scenario Economic Model forecast.</p></div><span>SEM v2026.2</span></div>
            <div className="guide-grid">
              <article><span>1</span><div><h3>Define the change</h3><p>Start from the central forecast and add one or more assumptions. Set the magnitude and the exact quarters over which each change applies.</p></div></article>
              <article><span>2</span><div><h3>Run the model</h3><p>The application creates immutable copies of the baseline inputs, assigns a unique run ID and executes the simultaneous quarterly R model.</p></div></article>
              <article><span>3</span><div><h3>Compare outcomes</h3><p>Results update when the run completes. Every chart retains the central forecast as a dashed comparator so scenario impacts remain visible.</p></div></article>
            </div>
            <div className="guide-columns">
              <div><h3>Shock conventions</h3><dl><dt>Percentage changes</dt><dd>Oil, migration and government consumption are converted to log innovations.</dd><dt>Percentage points</dt><dd>Interest-rate changes use decimal rate units; NAIRU changes use percentage units.</dd><dt>Timing</dt><dd>Every adjustment uses inclusive start and end quarters between 2025 Q1 and 2036 Q4.</dd></dl></div>
              <div><h3>Run records</h3><dl><dt>Unique ID</dt><dd>Each run receives a server-generated identifier beginning with <span className="mono">SCN</span>.</dd><dt>Stored evidence</dt><dd>Input snapshots, hashes, model logs, metadata and the complete forecast remain together.</dd><dt>Isolation</dt><dd>Scenario runs never overwrite the checked-in baseline assumptions or forecast.</dd></dl></div>
            </div>
          </section>}
        </div>
      </main>
    </div>
  )
}

export default App
