#Requires -Version 5.1
<#
.SYNOPSIS Instalator Transcription Manager - sprawdza zaleznosci, kopiuje pliki, dodaje skrot.

.DESCRIPTION
Uruchom poleceniem:
    irm https://raw.githubusercontent.com/CrystalPL/Transcryption-manager/main/install.ps1 | iex

Lub lokalnie:
    .\install.ps1
    .\install.ps1 -SkipDownload                 # uzyj plikow z biezacego folderu
    .\install.ps1 -InstallDir "D:\Transkrypcja" # zmien folder docelowy

.PARAMETER InstallDir Folder docelowy aplikacji (default: C:\Transkrypcja)
.PARAMETER SkipDownload Pomin pobieranie z GitHuba, uzyj lokalnych plikow
.PARAMETER GithubRepo URL repo na GitHubie (jesli inny niz domyslny)
#>

param(
    [string]$InstallDir = "C:\Transkrypcja",
    [string]$GithubRepo = "CrystalPL/Transcryption-manager",
    [string]$Branch     = "main",
    [switch]$SkipDownload,
    [switch]$NoShortcut,
    [switch]$NoDeps
)

$ErrorActionPreference = 'Stop'
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# ============== UTILS ==============
function Write-Step    { param($Msg) Write-Host "`n  $Msg" -ForegroundColor Cyan }
function Write-OK      { param($Msg) Write-Host "        [OK] $Msg" -ForegroundColor Green }
function Write-Skip    { param($Msg) Write-Host "        [--] $Msg" -ForegroundColor DarkYellow }
function Write-Missing { param($Msg) Write-Host "        [BRAK] $Msg" -ForegroundColor Red }
function Write-Info    { param($Msg) Write-Host "        $Msg" -ForegroundColor DarkGray }

function Test-Command {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Ask-YN {
    param([string]$Q, [bool]$Default = $true)
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

# ============== HEADER ==============
Clear-Host
$bar = "=" * 70
Write-Host ""
Write-Host "  $bar" -ForegroundColor Cyan
Write-Host "    Transcription Manager -- Instalator" -ForegroundColor White
Write-Host "  $bar" -ForegroundColor Cyan

# ============== KROK 1: SYSTEM CHECK ==============
Write-Step "[1/5] Sprawdzanie systemu..."

$winVer = [System.Environment]::OSVersion.Version
if ($winVer.Major -lt 10) {
    Write-Missing "Wymagany Windows 10 lub nowszy (masz: $winVer)"
    exit 1
}
Write-OK "Windows $($winVer.Major).$($winVer.Minor) build $($winVer.Build)"
Write-OK "PowerShell $($PSVersionTable.PSVersion)"

$hasWinget = Test-Command "winget"
if ($hasWinget) {
    Write-OK "winget (Microsoft Package Manager)"
} else {
    Write-Skip "winget nieobecny -- niektore zaleznosci trzeba zainstalowac recznie"
    Write-Info "Pobierz App Installer z Microsoft Store, lub: https://aka.ms/getwinget"
}

# ============== KROK 2: POBRANIE APLIKACJI ==============
Write-Step "[2/5] Pobieranie aplikacji..."

if ($SkipDownload) {
    Write-Skip "SkipDownload -- pomijam pobieranie"
    $srcDir = Join-Path $PSScriptRoot "src"
    if (-not (Test-Path $srcDir)) {
        Write-Missing "Brak folderu 'src' w biezacym katalogu"
        exit 1
    }
} else {
    $tmpZip = Join-Path $env:TEMP "tm-install.zip"
    $tmpDir = Join-Path $env:TEMP "tm-install-extract"
    $url    = "https://github.com/$GithubRepo/archive/refs/heads/$Branch.zip"

    Write-Info "URL: $url"
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmpZip -UseBasicParsing
        Write-OK "Pobrano archiwum ($([Math]::Round((Get-Item $tmpZip).Length / 1KB)) KB)"
    } catch {
        Write-Missing "Nie udalo sie pobrac: $_"
        exit 1
    }

    if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
    Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
    $repoFolder = Get-ChildItem $tmpDir -Directory | Select-Object -First 1
    $srcDir     = Join-Path $repoFolder.FullName "src"

    if (-not (Test-Path $srcDir)) {
        Write-Missing "Brak folderu 'src' w pobranym archiwum"
        exit 1
    }
    Write-OK "Rozpakowano"
}

# Kopiowanie do InstallDir
if (Test-Path $InstallDir) {
    Write-Info "Folder $InstallDir juz istnieje"
    if (-not (Ask-YN "Nadpisac pliki aplikacji (zachowamy config'i i Wyniki/)?" $true)) {
        Write-Host "  Anulowano." -ForegroundColor DarkGray
        exit 0
    }
    # Zachowaj uzytkownika
    $preserve = @("*.config.json", "Wyniki", "logi")
    Get-ChildItem $InstallDir -Force | Where-Object {
        $name = $_.Name
        $keep = $false
        foreach ($p in $preserve) {
            if ($name -like $p -or $name -eq $p) { $keep = $true; break }
        }
        -not $keep
    } | Remove-Item -Recurse -Force -EA SilentlyContinue
} else {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

Copy-Item -Path (Join-Path $srcDir "*") -Destination $InstallDir -Recurse -Force
Write-OK "Skopiowano do $InstallDir"

# ============== KROK 3: SPRAWDZANIE ZALEZNOSCI ==============
Write-Step "[3/5] Sprawdzanie zaleznosci..."

$deps = [ordered]@{
    'Python'      = @{ Cmd = 'python';   Required = $true;  WinGet = 'Python.Python.3.11' }
    'pip'         = @{ Cmd = 'pip';      Required = $true;  WinGet = $null }   # idzie z pythonem
    'ffmpeg'      = @{ Cmd = 'ffmpeg';   Required = $true;  WinGet = 'Gyan.FFmpeg' }
    'mkvmerge'    = @{ Cmd = 'mkvmerge'; Required = $true;  WinGet = 'MoritzBunkus.MKVToolNix' }
    'whisper'     = @{ Cmd = 'whisper';  Required = $true;  WinGet = $null }   # idzie z pip
}

$missingDeps = @()
foreach ($name in $deps.Keys) {
    if (Test-Command $deps[$name].Cmd) {
        Write-OK $name
    } else {
        Write-Missing $name
        $missingDeps += $name
    }
}

# Sprawdz GPU NVIDIA + CUDA
$hasNvidia = Test-Command "nvidia-smi"
if ($hasNvidia) {
    try {
        $gpuName = (& nvidia-smi --query-gpu=name --format=csv,noheader | Select-Object -First 1).Trim()
        Write-OK "GPU NVIDIA: $gpuName"
    } catch {
        Write-OK "GPU NVIDIA wykryta"
    }
} else {
    Write-Skip "Brak GPU NVIDIA -- whisper bedzie dzialal na CPU (znacznie wolniej)"
}

# ============== KROK 4: INSTALACJA BRAKUJACYCH ==============
if ($missingDeps.Count -gt 0 -and -not $NoDeps) {
    Write-Step "[4/5] Instalacja brakujacych zaleznosci..."

    if (-not (Ask-YN "Zainstalowac brakujace zaleznosci automatycznie?" $true)) {
        Write-Skip "Pominieto instalacje zaleznosci -- aplikacja moze nie dzialac"
    } else {
        foreach ($name in $missingDeps) {
            $dep = $deps[$name]
            Write-Host "`n  Instaluje: $name" -ForegroundColor Yellow

            if ($name -eq 'whisper') {
                if (-not (Test-Command 'pip')) {
                    Write-Skip "Pomijam whisper -- najpierw zainstaluj Pythona, potem uruchom: pip install openai-whisper"
                    continue
                }
                & pip install openai-whisper
                if ($LASTEXITCODE -eq 0) { Write-OK "whisper zainstalowany" }
                else { Write-Missing "Instalacja whisper nieudana" }
            }
            elseif ($name -eq 'pip') {
                Write-Skip "pip powinien byc z Pythonem -- zainstaluj python (jest w liscie)"
            }
            elseif ($dep.WinGet) {
                if (-not $hasWinget) {
                    Write-Missing "Brak winget -- zainstaluj recznie: $($dep.WinGet)"
                    continue
                }
                & winget install --id $dep.WinGet --accept-source-agreements --accept-package-agreements --silent
                if ($LASTEXITCODE -eq 0) { Write-OK "$name zainstalowany" }
                else { Write-Missing "Instalacja $name nieudana ($LASTEXITCODE)" }
            }
        }

        # Po instalacji pythona warto zaproponowac whisper + cuda
        if (($missingDeps -contains 'Python') -and $hasNvidia) {
            if (Ask-YN "Zainstalowac PyTorch z CUDA support (dla GPU acceleration whispera)?" $true) {
                & pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
            }
        }

        Write-Host "`n  UWAGA: nowo zainstalowane narzedzia moga wymagac restartu PowerShella" -ForegroundColor Yellow
        Write-Host "         zeby pojawily sie w PATH." -ForegroundColor Yellow
    }
} elseif ($NoDeps) {
    Write-Step "[4/5] Sprawdzanie zaleznosci pominiete (NoDeps)"
} else {
    Write-Step "[4/5] Wszystkie zaleznosci sa zainstalowane"
}

# ============== KROK 5: SKROT START MENU ==============
Write-Step "[5/5] Tworzenie skrotow..."

if ($NoShortcut) {
    Write-Skip "NoShortcut -- pominieto"
} else {
    try {
        $shortcutPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Zarzadzanie transkrypcja.lnk"
        $managerPath  = Join-Path $InstallDir "Manager.ps1"

        $wsh = New-Object -ComObject WScript.Shell
        $sc  = $wsh.CreateShortcut($shortcutPath)
        $sc.TargetPath       = "powershell.exe"
        $sc.Arguments        = "-ExecutionPolicy Bypass -File `"$managerPath`""
        $sc.WorkingDirectory = $InstallDir
        $sc.Description      = "Transcription Manager"
        $sc.WindowStyle      = 1
        $sc.Save()
        Write-OK "Skrot Start Menu: 'Zarzadzanie transkrypcja'"
    } catch {
        Write-Missing "Nie udalo sie utworzyc skrotu: $_"
    }
}

# ============== PODSUMOWANIE ==============
Write-Host ""
Write-Host "  $bar" -ForegroundColor Green
Write-Host "    Instalacja zakonczona!" -ForegroundColor White
Write-Host "  $bar" -ForegroundColor Green
Write-Host ""
Write-Host "  Aplikacja zainstalowana w: " -NoNewline -ForegroundColor DarkGray
Write-Host $InstallDir -ForegroundColor White
Write-Host ""
Write-Host "  Uruchom przez:" -ForegroundColor White
Write-Host "    - Klawisz Windows -> 'Zarzadzanie transkrypcja'" -ForegroundColor Cyan
Write-Host "    - Lub bezposrednio: $(Join-Path $InstallDir 'Manager.ps1')" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Odinstaluj: $(Join-Path $InstallDir 'uninstall.ps1')" -ForegroundColor DarkGray
Write-Host ""

if ($missingDeps.Count -gt 0 -and $NoDeps) {
    Write-Host "  UWAGA: niektore zaleznosci nie sa zainstalowane:" -ForegroundColor Yellow
    foreach ($d in $missingDeps) { Write-Host "    - $d" -ForegroundColor Yellow }
    Write-Host "  Aplikacja moze dzialac nieprawidlowo." -ForegroundColor Yellow
    Write-Host ""
}

# Skopiuj uninstaller do InstallDir
$uninstallSrc = Join-Path $PSScriptRoot "uninstall.ps1"
if (Test-Path $uninstallSrc) {
    Copy-Item $uninstallSrc -Destination $InstallDir -Force
}

Read-Host "  Nacisnij Enter aby zakonczyc"
