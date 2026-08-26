@echo off
setlocal
title Scenario Economic Model Launcher
pushd "%~dp0"

where node >nul 2>nul
if errorlevel 1 (
  echo Node.js is required but was not found on PATH.
  echo Install Node.js, then run this launcher again.
  pause
  exit /b 1
)

where Rscript >nul 2>nul
if errorlevel 1 (
  echo Rscript is required but was not found on PATH.
  echo Install R or add Rscript to PATH, then run this launcher again.
  pause
  exit /b 1
)

if not exist "node_modules\" (
  echo Installing frontend dependencies...
  call npm install --no-audit --no-fund
  if errorlevel 1 (
    echo Dependency installation failed.
    pause
    exit /b 1
  )
)

echo Starting the Scenario Economic Model...
start "Scenario Economic Model" cmd /k "npm run dev"
timeout /t 5 /nobreak >nul
start "" "http://localhost:5173"

popd
endlocal
