@echo off
cd /d "%~dp0"
set "PATH=%USERPROFILE%\.rokit\bin;%PATH%"
rem Arrete un ancien serveur Rojo qui occuperait encore le port
taskkill /IM rojo.exe /F >nul 2>&1
powershell -NoProfile -Command "Get-Process rojo -ErrorAction SilentlyContinue | Stop-Process -Force" >nul 2>&1
timeout /t 2 /nobreak >nul
rem Installe la bonne version de Rojo si elle a change
rokit install --no-trust-check
echo.
echo Rojo demarre. Dans Roblox Studio : Plugins ^> Rojo ^> Connect.
echo Laisse cette fenetre ouverte. Ctrl+C pour arreter.
rojo serve
pause
