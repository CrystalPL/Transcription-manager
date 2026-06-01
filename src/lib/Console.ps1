# Console.ps1 -- wspolne UI: naglowki, pytania T/N

# Szerokosc okna konsoli minus 1 (zeby kursor nie owijal)
function Get-ConsoleWidth {
    return [Math]::Max(72, [Console]::WindowWidth - 1)
}

<#
.SYNOPSIS Rysuje naglowek aplikacji z tytulem i opcjonalnym podtytulem.
#>
function Show-Header {
    param(
        [string]$Title,
        [string]$Krok = "",
        [string]$Subtitle = ""
    )
    $w = Get-ConsoleWidth
    $b = "-" * ($w - 4)
    Clear-Host
    Write-Host ""
    Write-Host (Fit "  +$b+" $w) -ForegroundColor DarkCyan
    Write-Host (Fit "  | $Title  $Krok" $w) -ForegroundColor Cyan
    Write-Host (Fit "  +$b+" $w) -ForegroundColor DarkCyan
    Write-Host ""
    if ($Subtitle) {
        Write-Host (Fit "  $Subtitle" $w) -ForegroundColor White
        Write-Host (Fit ("  " + "-" * ($w - 2)) $w) -ForegroundColor DarkGray
    }
    Write-Host ""
}

<#
.SYNOPSIS Interaktywne pytanie T/N. Enter = wybor domyslny.
#>
function Ask-TakNie {
    param(
        [string]$Question,
        [bool]$DefaultYes = $true   # zachowane dla kompatybilnosci, nie uzywane
    )
    Write-Host ""
    Write-Host "  $Question [T/N] " -ForegroundColor Yellow -NoNewline
    while ($true) {
        $k = [Console]::ReadKey($true)
        $c = [char]::ToLower($k.KeyChar)
        # Enter, spacja i inne klawisze sa ignorowane — wymagamy explicit T lub N
        if ($c -eq 't' -or $c -eq 'y') { Write-Host "Tak" -ForegroundColor Green; return $true  }
        if ($c -eq 'n')                 { Write-Host "Nie" -ForegroundColor Red;   return $false }
    }
}

<#
.SYNOPSIS Wybor sposrod listy opcji (1, 2, 3... lub Esc).
.EXAMPLE Ask-Choice "Wybor backendu" @("Claude", "Gemini", "Ollama")
#>
function Ask-Choice {
    param(
        [string]$Question,
        [string[]]$Options,
        [int]$Default = 0
    )
    Write-Host ""
    Write-Host "  $Question" -ForegroundColor Yellow
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $marker = if ($i -eq $Default) { ">" } else { " " }
        Write-Host ("   $marker $($i+1)  $($Options[$i])") -ForegroundColor White
    }
    Write-Host "  Wybor: " -NoNewline -ForegroundColor Yellow

    while ($true) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq 'Enter') {
            Write-Host ($Default + 1) -ForegroundColor Green
            return $Default
        }
        if ($k.Key -eq 'Escape') { Write-Host "anulowano" -ForegroundColor DarkGray; return -1 }
        $c = $k.KeyChar
        if ($c -match '\d') {
            $n = [int][string]$c - 1
            if ($n -ge 0 -and $n -lt $Options.Count) {
                Write-Host ($n + 1) -ForegroundColor Green
                return $n
            }
        }
    }
}

<#
.SYNOPSIS Pyta o tekst od uzytkownika. Pusta odpowiedz = $null.
#>
function Ask-Text {
    param([string]$Prompt, [string]$DefaultValue = "")
    $hint = if ($DefaultValue) { " (Enter = $DefaultValue)" } else { "" }
    Write-Host ""
    Write-Host "  $Prompt$hint" -ForegroundColor Yellow
    Write-Host "  > " -NoNewline -ForegroundColor White
    $input = Read-Host
    if (-not $input) { return $DefaultValue }
    return $input.Trim()
}
