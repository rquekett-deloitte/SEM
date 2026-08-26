# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

Vite, React and TypeScript for the frontend, with a local Node service that launches the R model and persists scenario inputs and results alongside the model project.

## Users

Economists and analysts using a desktop-first internal tool to define, run, inspect and compare Australian macroeconomic scenarios. The interface must remain usable on smaller screens for reviewing results and checking run status.

## Product Purpose

Turn the macro scenario model into an interactive analytical workflow. Users can control model inputs and assumptions, define scenarios, run the R model, and see results update automatically. Success means an analyst can move from an explicit set of assumptions to a traceable result without editing CSV files or invoking R manually.

## Positioning

The product joins a transparent quarterly assumption path and shock specification directly to the existing simultaneous macro model, preserving the model's variable contract and making every result traceable to a stored scenario run.

## Operating Context

Analysts work with quarterly forecasts from 2025 Q1 to 2036 Q4, compare alternative paths against a baseline, and inspect macroeconomic outcomes in charts and summary metrics. A scenario is defined, validated, run locally, assigned a unique identifier, and retained with its assumptions, status and results.

## Capabilities and Constraints

- Define named scenarios from the baseline forecast assumptions.
- Adjust high-value assumptions and behavioural or exogenous shocks over selected quarterly ranges.
- Run scenarios through the existing R model via a local API bridge.
- Store each completed run under a unique identifier and reopen prior results.
- Update the results dashboard automatically when a run completes.
- Compare a selected scenario with the baseline across major output variables.
- Preserve the executable exogenous-input and shock contracts documented in `VARIABLES.md` and implemented in `R/forecast_model.R`.
- Treat `data-raw/exogenous_forecast.csv` as the baseline source and do not modify it during scenario runs.
- Keep scenario-specific working files and output artifacts separate from the checked-in baseline inputs and outputs.

## Brand Commitments

Use Deloitte branding: a black and white foundation, Deloitte green as the primary action and status accent, and a precise, professional voice. Results charts should use the chart language of the existing ABS data site at `../ABS data site`, adapted into a coherent analytical application rather than copied as a generic card dashboard.

## Evidence on Hand

- Model runner and forecast implementation in `run_model.R` and `R/forecast_model.R`.
- Variable definitions and scenario contracts in `VARIABLES.md`.
- Baseline assumptions in `data-raw/exogenous_forecast.csv`.
- Baseline zero shocks in `data-raw/shocks.csv`.
- Baseline forecast results in `outputs/forecast.csv`.
- Existing ABS chart implementation in `../ABS data site`.
- No customer claims, benchmark claims or production deployment evidence are available and none should be fabricated.

## Product Principles

- Make assumptions explicit before making results impressive.
- Preserve a complete audit trail from scenario definition to model output.
- Keep common scenario work fast while retaining access to the full model contract.
- Compare against a stable baseline by default.
- Use economic conventions and terminology rather than consumer-app metaphors.

## Accessibility & Inclusion

Use semantic controls, keyboard-operable interactions, visible focus states, sufficient contrast, and chart alternatives that expose current values and trends in text or tables.
