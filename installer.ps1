# Installe Rokit, Rojo et le plugin Rojo pour Roblox Studio, puis lance `rojo serve`.
# Utilisation : double-clic sur INSTALLER.bat (ou lancer ce script dans PowerShell).

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$rokitBin = Join-Path $env:USERPROFILE ".rokit\bin"

Write-Host "`n=== Etape 1/3 : Rokit ===" -ForegroundColor Cyan
if (-not (Get-Command rokit -ErrorAction SilentlyContinue) -and -not (Test-Path (Join-Path $rokitBin "rokit.exe"))) {
	Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression
	Set-Location $PSScriptRoot
} else {
	Write-Host "Rokit est deja installe."
}
# Rend Rokit utilisable tout de suite dans cette fenetre
$env:PATH = "$rokitBin;$env:PATH"

Write-Host "`n=== Etape 2/3 : Rojo, Selene, StyLua ===" -ForegroundColor Cyan
rokit install --no-trust-check

Write-Host "`n=== Etape 3/3 : plugin Rojo pour Roblox Studio ===" -ForegroundColor Cyan
rojo plugin install

Write-Host "`nTout est installe !" -ForegroundColor Green
Write-Host "Ouvre (ou redemarre) Roblox Studio, ouvre ton jeu, puis : onglet Plugins > Rojo > Connect."
Write-Host "Laisse cette fenetre ouverte pendant que tu travailles. Ctrl+C pour arreter.`n"

rojo serve
