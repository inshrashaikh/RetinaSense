@echo off
REM RetinaSense one-command startup: real backend + frontend dev server.
REM Requires: global Python with backend deps (torch, matplotlib, matlab.engine)
REM and Node/npm for the frontend. Do NOT use the empty backend\myenv venv.

setlocal
cd /d "%~dp0"

set "PYTHON=python"
set "BACKEND_PORT=8000"
set "FRONTEND_PORT=5173"

echo [RetinaSense] Starting backend on http://127.0.0.1:%BACKEND_PORT% ...
start "RetinaSense-Backend" /D "%~dp0backend" /min %PYTHON% -m uvicorn app.main:app --host 0.0.0.0 --port %BACKEND_PORT% --log-level info

echo [RetinaSense] Waiting for the backend to come up...
set /a tries=0
:wait
powershell -NoProfile -Command "try { $r = Invoke-RestMethod -Uri 'http://127.0.0.1:%BACKEND_PORT%/api/health' -TimeoutSec 3; Write-Output (\"UP matlabEngine=\" + $r.matlabEngine) } catch { exit 1 }" >nul 2>&1
if not errorlevel 1 goto up
set /a tries+=1
if %tries% geq 40 (
  echo [RetinaSense] ERROR: backend did not become healthy after ~120s.
  exit /b 1
)
timeout /t 3 /nobreak >nul
goto wait

:up
echo [RetinaSense] Backend is UP ^(MATLAB engine available when matlabEngine=true^).
echo [RetinaSense] Starting frontend (Vite) on http://localhost:%FRONTEND_PORT% ...
start "RetinaSense-Frontend" /D "%~dp0frontend" /min cmd /k npm run dev

echo.
echo [RetinaSense] READY.
echo   Backend  : http://127.0.0.1:%BACKEND_PORT%  ^(OpenAPI docs at /docs^)
echo   Frontend : http://localhost:%FRONTEND_PORT%
echo.
echo   Sign in with seed account: doctor / doctor123
echo   (Role phc_operator hides review work; ophthalmologist/admin can review.)
echo.
echo   Close the two RetinaSense windows, then run:
echo     powershell -Command "Get-NetTCPConnection -LocalPort %BACKEND_PORT% -State Listen | ForEach-Object { Stop-Process -Id \$_.OwningProcess -Force }"
endlocal