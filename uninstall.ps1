#Requires -Version 5.1
<#
.SYNOPSIS Odinstalowuje Transcription Manager.

.DESCRIPTION
Usuwa folder aplikacji i skrot Start Menu.
Nie usuwa zaleznosci zewnetrznych (Python, whisper, ffmpeg, mkvmerge) -- moga byc uzywane przez inne aplikacje.
Domyslnie pyta o usuniecie folderow z wynikami i logami.

.PARAMETER InstallDir Folder aplikacji do usuniecia (default: C:\Transkrypcja)
.PARAMETER KeepResults Zachowaj folder Wyniki/ i logi/
.PARAMETER Quiet Bez pytan (do skryptowania)
#>

param(
    [string]$InstallDir = "C:\Transkrypcja",
    [switch]$KeepResults,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

function Ask-YN {
    param([string]$Q, [bool]$Default = $false)
    if ($Quiet) { return $Default }
    $opt = if ($Default) { "[T/n]" } else { "[t/N]" }
    Write-Host "`n  $Q $opt " -NoNewline -ForegroundColor Yellow
    while ($true) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq 'Enter') {
            Write-Host (if ($Default) { "Tak" } else { "Nie" }) -ForegroundColor (if ($Default) { 'Green' } else { 'Red' })
            return $Default
        }
        $c = [char]::ToLower($k.KeyChar)
        if ($c -eq 't' -or $c -eq 'y') { Write-Host "Tak" -ForegroundColor Green; return $true }
        if ($c -eq 'n')                 { Write-Host "Nie" -ForegroundColor Red;   return $false }
    }
}

Clear-Host
Write-Host ""
Write-Host "  ======================================================" -ForegroundColor Cyan
Write-Host "    Transcription Manager -- Deinstalator" -ForegroundColor White
Write-Host "  ======================================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $InstallDir)) {
    Write-Host "  Folder $InstallDir nie istnieje -- nic do usuniecia." -ForegroundColor Yellow
    if (-not $Quiet) { Read-Host "`n  Enter aby zakonczyc" }
    exit 0
}

Write-Host "  Folder do usuniecia: " -NoNewline -ForegroundColor DarkGray
Write-Host $InstallDir -ForegroundColor White
Write-Host ""

# Sprawdz co tam jest
$hasResults = Test-Path (Join-Path $InstallDir "Wyniki")
$hasLogs    = Test-Path (Join-Path $InstallDir "logi")
$hasConfigs = (Get-ChildItem $InstallDir -Filter "*.config.json" -EA SilentlyContinue).Count -gt 0

if ($hasResults) { Write-Host "  - Wykryto folder Wyniki/" -ForegroundColor DarkGray }
if ($hasLogs)    { Write-Host "  - Wykryto folder logi/"   -ForegroundColor DarkGray }
if ($hasConfigs) { Write-Host "  - Wykryto pliki *.config.json" -ForegroundColor DarkGray }
Write-Host ""

if (-not (Ask-YN "Kontynuowac deinstalacje?" $false)) {
    Write-Host "`n  Anulowano." -ForegroundColor DarkGray
    exit 0
}

$removeResults = $false
$removeLogs    = $false

if ($hasResults -and -not $KeepResults) {
    $removeResults = Ask-YN "Usunac folder Wyniki/ z transkrypcjami?" $false
}
if ($hasLogs -and -not $KeepResults) {
    $removeLogs = Ask-YN "Usunac folder logi/?" $false
}

# Usuwaj selektywnie
Get-ChildItem $InstallDir -Force | ForEach-Object {
    $name = $_.Name
    $skip = $false
    if (-not $removeResults -and $name -eq "Wyniki") { $skip = $true }
    if (-not $removeLogs    -and $name -eq "logi")   { $skip = $true }
    if (-not $skip) {
        Remove-Item $_.FullName -Recurse -Force -EA SilentlyContinue
    }
}

# Jesli folder pusty, usun
$remaining = Get-ChildItem $InstallDir -Force -EA SilentlyContinue
if (-not $remaining) {
    Remove-Item $InstallDir -Force -EA SilentlyContinue
    Write-Host "`n  [OK] Usunieto folder $InstallDir" -ForegroundColor Green
} else {
    Write-Host "`n  [OK] Usunieto pliki aplikacji (zachowano dane uzytkownika)" -ForegroundColor Green
}

# Usun skrot Start Menu
$shortcutPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Zarzadzanie transkrypcja.lnk"
if (Test-Path $shortcutPath) {
    Remove-Item $shortcutPath -Force -EA SilentlyContinue
    Write-Host "  [OK] Usunieto skrot Start Menu" -ForegroundColor Green
}

Write-Host ""
Write-Host "  Deinstalacja zakonczona." -ForegroundColor Cyan
Write-Host ""
Write-Host "  Nie usunieto zaleznosci zewnetrznych:" -ForegroundColor DarkGray
Write-Host "    Python, openai-whisper, ffmpeg, MKVToolNix" -ForegroundColor DarkGray
Write-Host "  Mozesz je usunac recznie przez winget uninstall, jesli nie sa potrzebne." -ForegroundColor DarkGray
Write-Host ""

if (-not $Quiet) { Read-Host "  Enter aby zakonczyc" }
