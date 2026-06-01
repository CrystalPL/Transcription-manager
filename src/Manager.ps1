#Requires -Version 5.1
# Manager.ps1 -- entry point dla aplikacji Transcription Manager
# Dot-source'uje lib/, pokazuje menu glowne, uruchamia Scripts/

# Wymus UTF-8 w konsoli (zeby polskie znaki w nazwach plikow sie poprawnie wyswietlaly)
# PS 5.1 domyslnie uzywa systemowego code page (CP1250 dla PL Windows) -- nie zgadza sie z UTF-8 plikow
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
    [Console]::InputEncoding  = [System.Text.UTF8Encoding]::new()
    $OutputEncoding           = [System.Text.UTF8Encoding]::new()
} catch {}

$ScriptRoot = Split-Path $PSCommandPath -Parent
$LibDir     = Join-Path $ScriptRoot "lib"
$ScriptsDir = Join-Path $ScriptRoot "Scripts"

# ============== ZALADUJ WSZYSTKIE BIBLIOTEKI ==============
# Kolejnosc wazna: Format -> Ansi -> Console -> reszta
$libOrder = @(
    "Format.ps1",
    "Ansi.ps1",
    "Console.ps1",
    "Config.ps1",
    "Dialog.ps1",
    "ShellMetadata.ps1",
    "Picker.ps1",
    "MultiPicker.ps1",
    "Dashboard.ps1"
)
foreach ($libFile in $libOrder) {
    . (Join-Path $LibDir $libFile)
}

# ============== MENU GLOWNE ==============
function Show-MainMenu {
    $w = Get-ConsoleWidth
    $b = "-" * ($w - 4)

    Clear-Host
    Write-Host ""
    Write-Host (Fit "  +$b+" $w) -ForegroundColor DarkCyan
    Write-Host (Fit "  | Transcription Manager" $w) -ForegroundColor Cyan
    Write-Host (Fit "  +$b+" $w) -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host (Fit "  Co chcesz zrobić?" $w) -ForegroundColor White
    Write-Host (Fit ("  " + "-" * ($w - 2)) $w) -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  " -NoNewline
    Write-Host " 1 " -ForegroundColor Black -BackgroundColor Cyan -NoNewline
    Write-Host "  Tworzenie transkrypcji" -ForegroundColor White
    Write-Host "      Whisper AI — generuje .srt / .vtt / .txt z plików wideo" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  " -NoNewline
    Write-Host " 2 " -ForegroundColor Black -BackgroundColor Cyan -NoNewline
    Write-Host "  Dodawanie rozdziałów do nagrania" -ForegroundColor White
    Write-Host "      mkvmerge — wpina XML rozdziały do MKV bez ponownego kodowania" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host (Fit ("  " + "-" * ($w - 2)) $w) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host " Q " -ForegroundColor Black -BackgroundColor DarkGray -NoNewline
    Write-Host "  Wyjście" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Naciśnij 1, 2 lub Q..." -ForegroundColor DarkGray
}

function Invoke-Script {
    param([string]$ScriptName)
    $path = Join-Path $ScriptsDir $ScriptName
    if (-not (Test-Path $path)) {
        Write-Host "  BLAD: nie znaleziono $path" -ForegroundColor Red
        $null = Read-Host "`n  Nacisnij Enter..."
        return
    }
    # Dot-source -- skrypt ma dostep do funkcji z lib/
    . $path
}

# ============== PETLA MENU ==============
while ($true) {
    Show-MainMenu
    $k = [Console]::ReadKey($true)
    $c = [char]::ToLower($k.KeyChar)

    switch ($c) {
        '1' { Invoke-Script "New-Transcription.ps1" }
        '2' { Invoke-Script "Add-Chapters.ps1" }
        default {
            if ($c -eq 'q' -or $k.Key -eq 'Escape') {
                Clear-Host
                exit 0
            }
        }
    }
}
