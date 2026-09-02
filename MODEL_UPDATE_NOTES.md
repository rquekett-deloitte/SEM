# SEM update priorities

## Model code

### Tasks

- Bring historical data up to the most recent period and simulate the model from that point.
- Estimate all equations to the most recent historical period by default and sense-check the outputs against previous outputs. Save a version of the current coefficients for comparison.
- Automate the process for updating data inputs, including ensuring that variables currently taken from MasterData are sourced directly in SEM.
- Update the model's residual carry-forward mechanics. Calculate the residual carry-forward separately and provide functionality to switch it on or off. Show SS what happens when residuals are set to zero and discuss the options.
- Test a historical simulation from the early 2010s and compare the results with actual values.

### High priority

- Update input data to the most recent period. This is required to run simulations that may be used in project work.
- Update the residual carry-forward mechanics. The aim is to discuss the results with Steve on Thursday, including what happens when residuals are set to zero, why residual carry-forward should be automated and why model adjustments should be a separate process.

### Medium priority

- Run a historical simulation from the early 2010s.
- Estimate equations to the current period.
- Automate data input updates.

## Excel output file

### Task

- Redesign the Excel output file to include the full set of variables, with both historical and forecast data.

### Priority

- High priority. Ideally, complete this by Thursday as a starting point for reviewing outputs.

## Dashboard

### Tasks

- Convert the dashboard to a Shiny dashboard.
- Ensure the dashboard can display the full set of variables for the historical and forecast periods.
- Provide AC, AB and SS with access to the dashboard.

### Priority

- Medium priority. A delivery timeframe of one to two weeks is acceptable.

## Thursday deliverables

By Thursday, aim to:

1. update the data inputs to the latest period and run the model from the most recent period of data
2. produce an Excel output file containing historical and forecast quarterly values for all variables from the updated model run in one flat file
3. test the updated model with residual carry-forward switched on and off to demonstrate what happens when residuals are set to zero.
