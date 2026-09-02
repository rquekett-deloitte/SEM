# SEM update priorities

## Model code

### Tasks

- Bring historical data up to the most recent period and simulate the model from that point.
- Estimate all equations to the most recent historical period by default and sense-check the outputs against previous outputs. Save a version of the current coefficients for comparison.
- Automate the process for updating data inputs, including ensuring that variables currently taken from MasterData are sourced directly in SEM.
- Add a variable-name conversion that maps SEM variables to the national Coredata naming conventions. Use `National Coredata.xlsx` as the reference and output the updated data as a Coredata file.
- Remove the residual calculation and carry-forward logic from the simulation code. Create a standalone R script that calculates the residuals and exports them to a CSV file. The simulation should use the exported residuals and retain functionality to switch residual carry-forward on or off.
- Show SS what happens when residuals are set to zero and discuss the residual carry-forward options.
- Test a historical simulation from the early 2010s and compare the results with actual values.

### High priority

- Update input data to the most recent period. This is required to run simulations that may be used in project work.
- Separate the residual calculation and carry-forward process from the simulation code. The aim is to discuss the results with Steve on Thursday, including what happens when residuals are set to zero, why residual carry-forward should be automated and why model adjustments should be a separate process.

### Medium priority

- Run a historical simulation from the early 2010s.
- Estimate equations to the current period.
- Automate data input updates.
- Add the national Coredata variable-name conversion and Coredata file output.

## Excel output file

### Task

- Redesign the Excel output file to include the full set of variables, with both historical and forecast data.

### Priority

- High priority. Ideally, complete this by Thursday as a starting point for reviewing outputs.

## Dashboard

### Tasks

- Replace the existing frontend with an R Shiny frontend.
- Ensure the dashboard can display the full set of variables for the historical and forecast periods.
- Provide AC, AB and SS with access to the dashboard.

### Priority

- Medium priority. A delivery timeframe of one to two weeks is acceptable.

## Thursday deliverables

By Thursday, aim to:

1. update the data inputs to the latest period and run the model from the most recent period of data
2. produce an Excel output file containing historical and forecast quarterly values for all variables from the updated model run in one flat file
3. use the standalone residual script and exported CSV file to test the updated model with residual carry-forward switched on and off, demonstrating what happens when residuals are set to zero.
