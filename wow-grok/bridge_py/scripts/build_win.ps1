$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $Root
if (Test-Path .\.venv\Scripts\Activate.ps1) { .\.venv\Scripts\Activate.ps1 }
pip install -q pillow certifi pyinstaller pystray
pyinstaller --noconfirm bridge_py\build_win.spec
Write-Host "Built: $Root\dist\WoWGrok.exe"
