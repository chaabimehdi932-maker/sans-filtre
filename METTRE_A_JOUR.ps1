# Telecharge la derniere version du projet depuis GitHub et remplace les fichiers de ce dossier.
# Si `rojo serve` tourne, les changements arrivent tout seuls dans Roblox Studio.

$ErrorActionPreference = "Stop"

$url = "https://github.com/chaabimehdi932-maker/sans-filtre/archive/refs/heads/claude/roblox-studio-c4irid.zip"
$zip = Join-Path $env:TEMP "sans-filtre-maj.zip"
$temp = Join-Path $env:TEMP "sans-filtre-maj"

Write-Host "Telechargement de la derniere version..." -ForegroundColor Cyan
Invoke-WebRequest $url -OutFile $zip
if (Test-Path $temp) { Remove-Item $temp -Recurse -Force }
Expand-Archive $zip -DestinationPath $temp -Force

$source = Get-ChildItem $temp -Directory | Select-Object -First 1
# Les anciens scripts supprimes du projet doivent aussi disparaitre de src/
if (Test-Path (Join-Path $PSScriptRoot "src")) { Remove-Item (Join-Path $PSScriptRoot "src") -Recurse -Force }
Copy-Item (Join-Path $source.FullName "*") -Destination $PSScriptRoot -Recurse -Force

Remove-Item $temp -Recurse -Force
Remove-Item $zip -Force
Write-Host "Projet a jour !" -ForegroundColor Green
