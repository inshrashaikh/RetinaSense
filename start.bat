@echo off
REM RetinaSense — full-stack launcher (backend + frontend).
REM MATLAB R2026a is required for the real pipeline.
REM Uses global Python (not backend\myenv) and npm for the frontend.

setlocal
cd /d "%~dp0"

set "PYTHON=python"
set "BACKEND_PORT=8000"
set "FRONTEND_PORT=5173"
set "MATLAB_BIN=C:\Program Files\MATLAB\R2026a\bin\win64"

REM Pre-pend MATLAB bin\win64 to PATH so DLLs resolve before Python loads.
set "PATH=%MATLAB_BIN%;%PATH%"

echo [RetinaSense] MATLAB bin added to PATH: %MATLAB_BIN%
echo [RetinaSense] Starting backend on http://127.0.0.1:%BACKEND_PORT% ...
echo [RetinaSense]   Config: backend\.env  (SIMULATION=off, MATLAB R2026a)
start "RetinaSense-Backend" /D "%~dp0backend" /min ^
  cmd /c "set PATH=%MATLAB_BIN%;%PATH% && %PYTHON% -m uvicorn app.main:app --host 0.0.0.0 --port %BACKEND_PORT% --log-level info --env-file .env"

echo [RetinaSense] Waiting for backend to be healthy (MATLAB engine start takes ~30s)...
set /a tries=0
:wait
powershell -NoProfile -Command ^
  "try { $r = Invoke-RestMethod -Uri 'http://127.0.0.1:%BACKEND_PORT%/api/health' -TimeoutSec 5; exit 0 } catch { exit 1 }" >nul 2>&1
if not errorlevel 1 goto up
set /a tries+=1
if %tries% geq 60 (
  echo [RetinaSense] ERROR: backend did not become healthy after ~5 min.
  echo [RetinaSense] Check the RetinaSense-Backend window for errors.
  exit /b 1
)
timeout /t 5 /nobreak >nul
goto wait

:up
REM Print what health says about MATLAB engine
for /f "delims=" %%i in ('powershell -NoProfile -Command ^
  "try { $r = Invoke-RestMethod -Uri 'http://127.0.0.1:%BACKEND_PORT%/api/health' -TimeoutSec 5; \"matlabEngine=\" + $r.matlabEngine } catch { 'health-check-failed' }"') do set HEALTH=%%i
echo [RetinaSense] Backend UP  (%HEALTH%)

echo [RetinaSense] Starting frontend (Vite) on http://localhost:%FRONTEND_PORT% ...
start "RetinaSense-Frontend" /D "%~dp0frontend" /min cmd /k npm run dev

echo.
echo ================================================================
echo  RetinaSense is READY
echo ================================================================
echo   Backend  : http://127.0.0.1:%BACKEND_PORT%
echo   API docs : http://127.0.0.1:%BACKEND_PORT%/docs
echo   Frontend : http://localhost:%FRONTEND_PORT%
echo.
echo   Login:  doctor / doctor123   (ophthalmologist — can review)
echo           operator / operator123  (PHC operator — upload only)
echo           admin / admin123
echo.
echo   MATLAB pipeline: RETINASENSE_SIMULATION=off  (real runPipeline)
echo   Simulink model : simulink\DRTelemedicine.slx  (open in MATLAB)
echo.
echo   To stop: close the two console windows above, then run:
echo     powershell -Command "Get-NetTCPConnection -LocalPort %BACKEND_PORT%,%FRONTEND_PORT% -State Listen | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }"
echo ================================================================
endlocal
