import cors from 'cors'
import express from 'express'
import { createHash, randomUUID } from 'node:crypto'
import { spawn } from 'node:child_process'
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const runsRoot = path.join(root, 'scenario-runs')
const baselineExogenousPath = path.join(root, 'data-raw', 'exogenous_forecast.csv')
const baselineShocksPath = path.join(root, 'data-raw', 'shocks.csv')
const baselineForecastPath = path.join(root, 'outputs', 'forecast.csv')
const port = Number(process.env.PORT || 4174)
const app = express()

app.use(cors())
app.use(express.json({ limit: '2mb' }))

function parseCsv(text) {
  const lines = text.trim().split(/\r?\n/)
  const headers = lines[0].split(',')
  return lines.slice(1).map((line) => {
    const values = line.split(',')
    return Object.fromEntries(headers.map((header, index) => [header, header === 'date' ? values[index] : Number(values[index])]))
  })
}

function toCsv(rows) {
  const headers = Object.keys(rows[0])
  return `${headers.join(',')}\n${rows.map((row) => headers.map((header) => row[header]).join(',')).join('\n')}\n`
}

function hash(text) {
  return createHash('sha256').update(text).digest('hex')
}

function publicScenario(metadata) {
  const { paths: _paths, ...scenario } = metadata
  return scenario
}

async function readScenarios() {
  await mkdir(runsRoot, { recursive: true })
  const entries = await readdir(runsRoot, { withFileTypes: true })
  const scenarios = await Promise.all(entries.filter((entry) => entry.isDirectory()).map(async (entry) => {
    try {
      return JSON.parse(await readFile(path.join(runsRoot, entry.name, 'scenario.json'), 'utf8'))
    } catch {
      return null
    }
  }))
  return scenarios.filter(Boolean).sort((a, b) => b.createdAt.localeCompare(a.createdAt)).map(publicScenario)
}

async function baselinePayload() {
  const forecast = parseCsv(await readFile(baselineForecastPath, 'utf8'))
  return {
    id: 'baseline',
    name: 'Central forecast',
    status: 'baseline',
    createdAt: null,
    completedAt: null,
    notes: 'Current published model baseline',
    adjustments: [],
    results: forecast,
  }
}

app.get('/api/bootstrap', async (_request, response, next) => {
  try {
    response.json({ baseline: await baselinePayload(), scenarios: await readScenarios() })
  } catch (error) { next(error) }
})

app.get('/api/scenarios/:id', async (request, response, next) => {
  try {
    if (request.params.id === 'baseline') return response.json(await baselinePayload())
    const runDirectory = path.join(runsRoot, path.basename(request.params.id))
    const scenario = JSON.parse(await readFile(path.join(runDirectory, 'scenario.json'), 'utf8'))
    if (scenario.status === 'completed') scenario.results = parseCsv(await readFile(path.join(runDirectory, 'forecast.csv'), 'utf8'))
    response.json(publicScenario(scenario))
  } catch (error) { next(error) }
})

app.post('/api/scenarios', async (request, response, next) => {
  const id = `SCN-${new Date().toISOString().slice(0, 10).replaceAll('-', '')}-${randomUUID().slice(0, 6).toUpperCase()}`
  const runDirectory = path.join(runsRoot, id)
  try {
    const name = String(request.body.name || '').trim()
    const adjustments = Array.isArray(request.body.adjustments) ? request.body.adjustments : []
    if (!name) return response.status(400).json({ message: 'Enter a scenario name before running the model.' })
    if (adjustments.length > 20) return response.status(400).json({ message: 'A scenario can contain at most 20 adjustments.' })

    await mkdir(runDirectory, { recursive: true })
    const exogenousText = await readFile(baselineExogenousPath, 'utf8')
    const shocksText = await readFile(baselineShocksPath, 'utf8')
    const shocks = parseCsv(shocksText)
    const allowedVariables = new Set(Object.keys(shocks[0]).filter((key) => key !== 'date'))

    for (const adjustment of adjustments) {
      if (!allowedVariables.has(adjustment.variable)) throw new Error(`Unknown model variable: ${adjustment.variable}`)
      const start = String(adjustment.start)
      const end = String(adjustment.end)
      const value = Number(adjustment.value)
      if (!Number.isFinite(value)) throw new Error(`Invalid adjustment for ${adjustment.variable}`)
      for (const row of shocks) {
        if (row.date >= start && row.date <= end) row[adjustment.variable] = value
      }
    }

    const scenarioShocksText = toCsv(shocks)
    const exogenousPath = path.join(runDirectory, 'exogenous_forecast.csv')
    const shocksPath = path.join(runDirectory, 'shocks.csv')
    const metadata = {
      id,
      name,
      notes: String(request.body.notes || '').trim(),
      status: 'running',
      createdAt: new Date().toISOString(),
      completedAt: null,
      adjustments,
      inputHashes: { exogenous: hash(exogenousText), shocks: hash(scenarioShocksText) },
      paths: { exogenousPath, shocksPath },
    }
    await Promise.all([
      writeFile(exogenousPath, exogenousText),
      writeFile(shocksPath, scenarioShocksText),
      writeFile(path.join(runDirectory, 'scenario.json'), JSON.stringify(metadata, null, 2)),
    ])

    const child = spawn('Rscript', [path.join(root, 'R', 'run_scenario.R'), root, exogenousPath, shocksPath, runDirectory], { cwd: root, shell: false })
    let stdout = ''
    let stderr = ''
    child.stdout.on('data', (chunk) => { stdout += chunk })
    child.stderr.on('data', (chunk) => { stderr += chunk })
    child.on('error', async (error) => {
      metadata.status = 'failed'
      metadata.error = error.message
      metadata.completedAt = new Date().toISOString()
      await writeFile(path.join(runDirectory, 'scenario.json'), JSON.stringify(metadata, null, 2))
    })
    child.on('close', async (code) => {
      metadata.status = code === 0 ? 'completed' : 'failed'
      metadata.completedAt = new Date().toISOString()
      metadata.exitCode = code
      if (code !== 0) metadata.error = stderr.trim() || 'The R model did not complete.'
      await Promise.all([
        writeFile(path.join(runDirectory, 'stdout.log'), stdout),
        writeFile(path.join(runDirectory, 'stderr.log'), stderr),
        writeFile(path.join(runDirectory, 'scenario.json'), JSON.stringify(metadata, null, 2)),
      ])
    })
    response.status(202).json(publicScenario(metadata))
  } catch (error) { next(error) }
})

app.use((error, _request, response, _next) => {
  console.error(error)
  response.status(error.code === 'ENOENT' ? 404 : 500).json({ message: error.message || 'Unexpected server error.' })
})

app.listen(port, () => console.log(`Scenario API listening on http://localhost:${port}`))
