# Telecharge la derniere version du projet depuis GitHub, remplace les fichiers de ce dossier
# puis relance Rojo (Rojo doit redemarrer pour voir les nouveaux fichiers et le nouveau projet).

$ErrorActionPreference = "Stop"

$url = "https://github.com/chaabimehdi932-maker/sans-filtre/archive/refs/heads/claude/roblox-studio-c4irid.zip"
$id = Get-Random
$zip = Join-Path $env:TEMP "sans-filtre-maj-$id.zip"
$temp = Join-Path $env:TEMP "sans-filtre-maj-$id"

Write-Host "Arret de Rojo..." -ForegroundColor Cyan
Get-Process rojo -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

Write-Host "Telechargement de la derniere version..." -ForegroundColor Cyan
Invoke-WebRequest $url -OutFile $zip -UseBasicParsing
Expand-Archive $zip -DestinationPath $temp -Force

$source = Get-ChildItem $temp -Directory | Select-Object -First 1
# Les anciens scripts supprimes du projet doivent aussi disparaitre de src/
if (Test-Path (Join-Path $PSScriptRoot "src")) { Remove-Item (Join-Path $PSScriptRoot "src") -Recurse -Force }
Copy-Item (Join-Path $source.FullName "*") -Destination $PSScriptRoot -Recurse -Force

Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $zip -Force -ErrorAction SilentlyContinue

$version = Select-String -Path (Join-Path $PSScriptRoot "src\shared\GameConfig.luau") -Pattern 'Version = "([^"]+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value }
Write-Host "Projet a jour ! Version $version" -ForegroundColor Green
Write-Host "Relance de Rojo dans une nouvelle fenetre..." -ForegroundColor Cyan
Start-Process -FilePath (Join-Path $PSScriptRoot "DEMARRER.bat") -WorkingDirectory $PSScriptRoot
Write-Host "Dans Roblox Studio : Plugins > Rojo > Disconnect puis Connect (accepte les changements)." -ForegroundColor Yellow
