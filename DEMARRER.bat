@echo off
cd /d "%~dp0"
set "PATH=%USERPROFILE%\.rokit\bin;%PATH%"
rem Arrete un ancien serveur Rojo qui occuperait encore le port
taskkill /IM rojo.exe /F >nul 2>&1
rem Installe la bonne version de Rojo si elle a change
rokit install --no-trust-check
echo.
echo Rojo demarre. Dans Roblox Studio : Plugins ^> Rojo ^> Connect.
echo Laisse cette fenetre ouverte. Ctrl+C pour arreter.
rojo serve
pause
