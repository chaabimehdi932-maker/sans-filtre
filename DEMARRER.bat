@echo off
cd /d "%~dp0"
set "PATH=%USERPROFILE%\.rokit\bin;%PATH%"
echo Rojo demarre. Dans Roblox Studio : Plugins ^> Rojo ^> Connect.
echo Laisse cette fenetre ouverte. Ctrl+C pour arreter.
rojo serve
pause
