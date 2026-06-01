# CLAUDE.md

Kontekst projektu dla przyszłych sesji Claude Code (i deweloperów). Czytaj na początku każdej sesji.

## Co to jest

PowerShell TUI do pracy z transkrypcjami nagrań:
1. **Whisper** generuje SRT/VTT z plików wideo (`New-Transcription.ps1`)
2. **LLM** (Claude / Gemini / Ollama) zamienia SRT w XML Matroska Chapters (`New-Chapters.ps1`)
3. **mkvmerge** wpina XML do MKV bez ponownego kodowania (`Add-Chapters.ps1`)

Cała aplikacja to PowerShell 5.1 + Windows Forms (do dialogów folderu) + native cmd-line tools (whisper, mkvmerge). Brak zależności od PowerShell 7.

## Struktura

```
src/
├── Manager.ps1              # entry point — dot-source'uje lib/, pokazuje menu
├── lib/                     # współdzielone helpery (KOLEJNOŚĆ ŁADOWANIA WAŻNA)
│   ├── Format.ps1           # 1. Fit, Format-Size/Time, NaturalSort, DurationToSeconds
│   ├── Ansi.ps1             # 2. ESC, Get-AnsiFg/Bg, Wrap-Ansi, Build-Row (+ VT enable)
│   ├── Console.ps1          # 3. Get-ConsoleWidth, Show-Header, Ask-TakNie, Ask-Choice
│   ├── Config.ps1           # 4. Read-Config, Save-Config, Update-Config (JSON)
│   ├── Dialog.ps1           # 5. Open-FolderDialog, Select-Folder (System.Windows.Forms)
│   ├── ShellMetadata.ps1    # 6. Get-ShellDurations, Read-FileSafe
│   ├── Picker.ps1           # 7. Show-Picker (single-select + nawigacja po katalogach)
│   ├── MultiPicker.ps1      # 8. Show-MultiPicker (multi-select, Spacja zaznacza)
│   └── Dashboard.ps1        # 9. Render-Dashboard, View-Logs, Get-WhisperProgressSec
└── Scripts/
    ├── New-Transcription.ps1   # whisper + dashboard z live progress
    ├── New-Chapters.ps1        # SRT -> XML przez API/Ollama
    └── Add-Chapters.ps1        # XML -> MKV przez mkvmerge
```

Każdy `Scripts/*.ps1` zakłada że wszystkie `lib/*` są już załadowane (dot-source'owane przez Manager.ps1). Nigdy nie uruchamiaj `New-Transcription.ps1` bezpośrednio — tylko przez Managera.

## Krytyczne ograniczenia PowerShell 5.1

To NIE działa (PS7-only syntax):
- Ternary `$x ? 'a' : 'b'` → użyj `if ($x) { 'a' } else { 'b' }`
- Null-coalescing `$x ?? 'default'` → użyj `if ($null -eq $x) { 'default' } else { $x }`
- `ConvertFrom-Json -AsHashtable` → konwertuj PSCustomObject ręcznie pętlą po PSObject.Properties
- Pipeline chain `||` `&&` → użyj `; if ($?) { ... }` lub osobnych linii
- `?.` null-conditional → ręczny `if ($x) { $x.Foo }`

UTF-16 LE BOM przy `Out-File` / `Set-Content` bez `-Encoding UTF8` to klasyczny bug — zawsze ustaw encoding.

## Rendering UI — wzorce krytyczne dla braku migania

### 1. Cały frame jako jeden Write

`Write-Host` w PS 5.1 idzie przez pipeline (format → output → host) = ~5ms per call. Przy 30 liniach to 150ms na klatkę = miganie i lag.

Wzorzec używany w `Render-FullMulti`, `Render-Dashboard`, `View-Logs`:

```powershell
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("$script:ESC[H")                          # kursor home
[void]$sb.Append((Wrap-Ansi (Fit "..." $w) 'Cyan') + "`n") # każda linia z kolorem ANSI
# ... więcej Append
[void]$sb.Append("$script:ESC[J")                          # clear to end of screen
[Console]::Write($sb.ToString())                           # JEDEN syscall
```

### 2. NIGDY Clear-Host w pętli renderu

`Clear-Host` (lub ANSI `[2J`) powoduje czarny błysk. Zamiast tego:
- `Clear-Host` RAZ przed pętlą (czysty start)
- W pętli: `[H]` (cursor home) + każda linia `Fit`-owana do `$w` znaków (nadpisuje stare znaki) + `[J]` na końcu (czyści resztę)

Wyjątek: **detekcja resize wymaga `Clear-Host`** — bo nowe (szersze) linie nie nadpiszą starych (węższych) znaków po prawej. Każda funkcja UI musi mieć:

```powershell
$lastW = [Console]::WindowWidth; $lastH = [Console]::WindowHeight
while ($true) {
    $w = [Console]::WindowWidth; $h = [Console]::WindowHeight
    if ($w -ne $lastW -or $h -ne $lastH) {
        $lastW = $w; $lastH = $h
        Clear-Host  # JEDYNE miejsce gdzie wolno
    }
    # render
}
```

### 3. Partial updates (np. ruch kursora w pickerze)

Gdy zmienia się tylko jedna/dwie linie, NIE renderuj całego frame'a. Pozycjonuj kursor ANSI:

```powershell
$frame = "$script:ESC[$($oldRow + 1);1H" + (Build-ItemAnsi $items[$old] $false $w) +
         "$script:ESC[$($newRow + 1);1H" + (Build-ItemAnsi $items[$new] $true  $w)
[Console]::Write($frame)
```

ANSI rows są 1-indexed, dlatego `+1`.

### 4. Coalesce powtórzeń klawiszy

Trzymanie strzałki = 30 keystroke/s. Każdy osobno = render za render. Wzorzec:

```powershell
$k = [Console]::ReadKey($true)
$repeat = 1
if ($k.Key -eq 'UpArrow' -or $k.Key -eq 'DownArrow') {
    while ([Console]::KeyAvailable) {
        $next = [Console]::ReadKey($true)
        if ($next.Key -eq $k.Key) { $repeat++ } else { break }
    }
}
# potem: $cursor += $repeat (z wrap-around)
```

Bez tego: 5 sekund przytrzymania = 5 sekund renderowania PO puszczeniu klawisza.

### 5. Polling pattern (key + resize)

```powershell
while (-not [Console]::KeyAvailable) {
    Start-Sleep -Milliseconds 30
    $nw = [Console]::WindowWidth
    if ($nw -ne $lastW) { ... resize handling ... }
    if ($needFull) { Render-Whatever; $needFull = $false }
}
$k = [Console]::ReadKey($true)
```

30ms = responsywne, nie zżera CPU. `[Console]::WindowWidth` to tani property read — nie ma sensu ograniczać.

## Procesy zewnętrzne — pułapki

### `Register-ObjectEvent` NIE DZIAŁA w pętlach

Eventy `OutputDataReceived` kolejkują się ale **wykonują dopiero gdy PowerShell yielduje**. `Start-Sleep` tego nie robi. Loop z pollingiem = eventy nigdy nie wystrzelą = puste logi.

Działa: `Start-Process -RedirectStandardOutput $file -RedirectStandardError $errFile`. Plik jest pisany przez child process bezpośrednio, nasz PS tylko czyta.

### cmd.exe + polskie znaki = trouble

Pierwsza próba używała `.cmd` wrapper z `Set-Content -Encoding ASCII` — polskie znaki w ścieżce (`Zajęcia`) były zamieniane na `?`, cmd nie znajdował pliku. Lekcja: jeśli musisz cmd, zapisz bat jako `[System.Text.Encoding]::Default` (system ANSI code page) albo użyj UTF-8 + `chcp 65001` na początku. Lepiej: pomiń cmd wrapper całkowicie, używaj `Start-Process`.

### PYTHONUNBUFFERED dla whispera

Python domyślnie buforuje stdout gdy stdout nie jest TTY. Whisper przez subprocess = buforowanie = log pusty do końca procesu = brak live progress.

Ustaw przed odpaleniem whispera:
```powershell
$env:PYTHONUNBUFFERED = "1"
$env:PYTHONIOENCODING = "utf-8"
```

Child process dziedziczy env vars rodzica.

### `Start-Process` nie pozwala stdout i stderr do tego samego pliku

File lock conflict. Rozwiązanie: dwa pliki (`*.log` i `*.log.err`), wszystkie funkcje czytające log (Get-WhisperProgressSec, View-Logs) muszą czytać oba i sklejać. Po zakończeniu procesu Finalize-WhisperJob dokleja `.err` do `.log` i usuwa `.err`.

### File locking podczas live read

`[System.IO.File]::ReadAllText()` rzuca exception jeśli plik jest otwarty na zapis przez inny proces. W `Read-FileSafe`:

```powershell
$fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
$sr = New-Object System.IO.StreamReader($fs)
$content = $sr.ReadToEnd()
$sr.Close(); $fs.Close()
```

`FileShare.ReadWrite` = "ja chcę tylko czytać, inni mogą sobie pisać do woli".

## Konwencje kodu

### Naming
- **Verb-Noun** zgodnie z PS approved verbs (Get-Verb żeby sprawdzić): `New-Transcription`, `Add-Chapters`, `Show-Picker`, nie `getConfig`/`doWhisper`/`makeAnsi`.
- **Polskie nazwy plików** dozwolone w nazwach skryptów (`Tworzenie transkrypcji.config.json`) — wpisują się w UI po polsku. Ale **nazwy funkcji i zmiennych — angielskie** (`$selectedFiles`, nie `$wybraneFile`).
- **Skrypty PowerShellowe — `.ps1`**, biblioteki też `.ps1` (nie `.psm1`, bo dot-source'ujemy zamiast importowania jako moduły).

### Polskie znaki TAK — ale TYLKO z UTF-8 BOM

Pliki `.ps1` **MUSZĄ być zapisane z UTF-8 BOM** (bajty `EF BB BF` na początku). Bez BOM PS 5.1 czyta plik jako CP1250 (systemowy code page polskiego Windowsa), wszystkie znaki spoza ASCII stają się krzakami (`â€"`, `Ã¦`).

**Sprawdzenie czy BOM jest:**
```powershell
$bytes = [System.IO.File]::ReadAllBytes("plik.ps1")[0..2]
($bytes | ForEach-Object { $_.ToString('X2') }) -join ' '
# Powinno: "EF BB BF"
```

**Dodanie BOM:**
```powershell
$content = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($true))
```

**UWAGA — Edit/Write tool sandboxa zapisuje bez BOM!** Jeśli edytujesz pliki przez te narzędzia, po każdej edycji **musisz ponownie dodać BOM** powyższym kodem PowerShell. To krytyczne.

**Konsola też potrzebuje UTF-8** — Manager.ps1 ustawia na początku:
```powershell
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::InputEncoding  = [System.Text.UTF8Encoding]::new()
$OutputEncoding           = [System.Text.UTF8Encoding]::new()
```

To naprawia rendering polskich znaków w nazwach plików (np. `Zajęcia kontaktowe`) przy listowaniu w pickerze.

### Em-dashe i inne unicode-y też OK

Skoro mamy BOM, możemy używać em-dash `—`, strzałki `→`, multiplikacji `×` itp. Wszystkie znaki Unicode działają. Emoji też (np. w prompcie do AI: 📢, ⚙️) — pod warunkiem że terminal je renderuje (Windows Terminal i IntelliJ Terminal — tak; stary conhost — tylko monochromatyczne).

### Comment-based help

Każda publiczna funkcja:

```powershell
<#
.SYNOPSIS Jednolinijkowe co robi.
.PARAMETER X Opis parametru
.EXAMPLE Show-Picker -StartPath C:\
#>
function Show-Picker { param(...) ... }
```

Działa potem `Get-Help Show-Picker -Full`.

### Brak komentarzy "co robi linia"

Komentuj **WHY** (powód decyzji, hidden gotcha), nie **WHAT** (to widać z kodu). Jak coś jest nieoczywiste — krótki komentarz. Jeśli kod się tłumaczy sam — bez komentarza.

OK: `# PYTHONUNBUFFERED — bez tego logi sa puste az do zakonczenia procesu`
NIE: `# Iteruj po plikach` przed `foreach ($f in $files)`.

### Ścieżki — używaj `$PSCommandPath` nie `$PSScriptRoot`

`$PSScriptRoot` bywa pusty zależnie od sposobu wywołania. `$PSCommandPath` zawsze ma pełną ścieżkę aktualnego pliku:

```powershell
$ScriptDir = Split-Path $PSCommandPath -Parent
$ProjectRoot = Split-Path $PSCommandPath -Parent | Split-Path -Parent
```

## Workspace dev environment vs produkcja

Skrypty mają DWA tryby przechowywania configów/wyników:

| Tryb | Kiedy | Lokalizacja |
|---|---|---|
| **Produkcyjny** | Po instalacji przez `install.ps1`, uruchomienie ze skrótu Start Menu | Folder instalacji (default `C:\Transkrypcja\`, ale `install.ps1 -InstallDir D:\X` da `D:\X\`) |
| **Dev (workspace)** | Uruchomienie z IntelliJ przez Run config | `$PROJECT_DIR$\.workspace\` |

Mechanizm: env vars czytane przez skrypty, w innym wypadku relatywnie do **lokalizacji skryptu** (`$PSCommandPath`):

```powershell
$ProjectRoot = Split-Path $PSCommandPath -Parent | Split-Path -Parent
# Scripts/New-Transcription.ps1 -> .. -> Scripts/ -> .. -> root instalacji

$ConfigDir  = if ($env:TRANSCRIPTION_CONFIG_DIR) { $env:TRANSCRIPTION_CONFIG_DIR } else { $ProjectRoot }
$LogsRoot   = if ($env:TRANSCRIPTION_LOGS_DIR)   { $env:TRANSCRIPTION_LOGS_DIR }   else { Join-Path $ProjectRoot "logi" }
$DefaultOut = if ($env:TRANSCRIPTION_OUTPUT_DIR) { $env:TRANSCRIPTION_OUTPUT_DIR } else { Join-Path $ProjectRoot "Wyniki" }
```

**NIE hardkoduj `C:\Transkrypcja` jako fallback** — install.ps1 ma flagę `-InstallDir`, user może mieć aplikację gdziekolwiek.

IntelliJ run config (`.idea/runConfigurations/Manager.xml`) ustawia te env vars:

```xml
<envs>
    <env name="TRANSCRIPTION_CONFIG_DIR" value="$PROJECT_DIR$\workspace" />
    <env name="TRANSCRIPTION_LOGS_DIR" value="$PROJECT_DIR$\.workspace\logi" />
    <env name="TRANSCRIPTION_OUTPUT_DIR" value="$PROJECT_DIR$\.workspace\Wyniki" />
</envs>
```

`.workspace/` jest w gitignore (poza `.gitkeep`) — configs, logi, wyniki nie są commitowane.

**Dodawanie kolejnych env vars** — dla nowego ustawienia konfiguracyjnego:
1. Skrypt: `$X = if ($env:TRANSCRIPTION_X) { $env:TRANSCRIPTION_X } else { default }`
2. IntelliJ run config: dodaj `<env name="TRANSCRIPTION_X" value="..." />`
3. CLAUDE.md: dodaj do tabeli wyżej

## Konfiguracja per-skrypt

Każdy Script ma swój config obok pliku w `src/`:
- `New-Transcription.config.json` (lastSourceDir, lastOutputDir, fp16)
- `New-Chapters.config.json` (lastSrtDir, backend, ollamaModel)
- `Add-Chapters.config.json` (lastVideoDir, lastXmlDir)

API keys (`ANTHROPIC_API_KEY`, `GEMINI_API_KEY`) jako User Environment Variables, NIE w configu (config jest w gitignore ale i tak — sekrety osobno).

Funkcje z `Config.ps1`:
- `Read-Config -Path $cfg -Default @{...}` — zwraca PSCustomObject, fallback default
- `Save-Config -Path $cfg -Data @{...}` — pełny overwrite
- `Update-Config -Path $cfg -Key 'x' -Value $v` — tylko jeden klucz, reszta zachowana

## Dashboard whispera — jak działa progress

1. Whisper z `--verbose True` wypisuje segmenty: `[00:05:42.500 --> 00:05:47.000]  tekst...`
2. Regex `'-->\s+(\d+(?::\d+)+\.\d+)\]'` wyciąga **końcowe** timestampy
3. Ostatni timestamp → sekundy przez `Convert-DurationToSeconds`
4. `% = sec_done / total_duration * 100` (total z Shell.Application Get-Details)
5. ETA = `elapsed * (100 - pct) / pct`

Cap progress na 99% w czasie pracy, 100% dopiero gdy `Process.HasExited` i `ExitCode -eq 0`.

Whisper na początku ~5s ładuje model — w tym czasie log pusty, progress = 0%. Normalne.

## Dodawanie nowej opcji menu

1. W `src/Scripts/` stwórz `New-CośTam.ps1` — może używać wszystkich funkcji z `lib/`
2. W `Manager.ps1` w `Show-MainMenu` dodaj wpis menu
3. W `switch ($c)` dodaj case wywołujący `Invoke-Script "New-CośTam.ps1"`

Wzorzec dla skryptu:

```powershell
# 1. Sprawdź zewnętrzne narzędzia
function Test-Tool { try { tool --help 2>&1 | Out-Null; return $LASTEXITCODE -eq 0 } catch { return $false } }
if (-not (Test-Tool)) { Show-Header...; Read-Host; return }

# 2. Wczytaj config
$ConfigPath = Join-Path (Split-Path $PSCommandPath -Parent | Split-Path -Parent) "Nazwa.config.json"
$cfg = Read-Config -Path $ConfigPath -Default @{ ... }

# 3. Etapy w pętli "z opcją cofnięcia" jeśli więcej niż 1 step:
while ($true) {
    # KROK 1: Show-Header + Select-Folder / Show-Picker / ...
    # KROK 2: ...
    # Podsumowanie + T/W/Q (start/wróć/anuluj)
    if ($decision -eq 'start') { break }
    if ($decision -eq 'cancel') { return }
}

# 4. Logika
# 5. Read-Host na końcu żeby user widział wyniki przed powrotem do menu
```

## Dodawanie nowego backendu AI (do New-Chapters)

W `New-Chapters.ps1` w `Ask-Choice` dodaj nową opcję, w `switch ($backend)` dodaj case. Wzorzec:

```powershell
'mojbackend' {
    $key = Get-ApiKey "MOJBACKEND_API_KEY" "Moj Backend"
    if (-not $key) { return }

    $body = @{ ... } | ConvertTo-Json -Depth 5
    try {
        $resp = Invoke-RestMethod -Method Post -Uri "..." -Headers @{...} -Body $body
        $response = $resp.text   # struktura zależna od API
    } catch {
        Write-Host "BLAD: $_" -ForegroundColor Red
        return
    }
}
```

Response zawsze jako string w `$response`. Reszta skryptu (wyciągnięcie XML z markdownu, zapis pliku) jest wspólna.

## Testowanie

Nie ma test framework'u (Pester nie był setupowany). Testy manualne:

1. **Picker** — `Show-Picker -StartPath C:\` w shellu z załadowanym lib/
2. **Multi-picker** — to samo z `Show-MultiPicker`
3. **Dashboard** — uruchom `New-Transcription.ps1` na 2-3 krótkich plikach (30s każdy), zobacz czy progress się aktualizuje
4. **Install** — `.\install.ps1 -SkipDownload` na czystej VM (Windows Sandbox świetny do tego)

Częste regresje:
- Miganie po zmianie renderera (czy `[2J` się przypadkiem nie wkradł)
- Lag przy holdowaniu strzałki (czy coalesce nadal działa)
- Encoding polskich znaków w configu (czy `-Encoding UTF8` jest wszędzie)
- File locking gdy whisper aktywny (czy `Read-FileSafe` używane wszędzie)

## Debugowanie

Trace co PowerShell wykonuje:
```powershell
Set-PSDebug -Trace 1
# ... uruchom skrypt
Set-PSDebug -Off
```

Verbose process output (gdy whisper się wykrzacza):
```powershell
$env:PYTHONUNBUFFERED = "1"
& whisper "plik.mp4" --verbose True 2>&1 | Tee-Object -FilePath debug.log
```

Sprawdź czy ANSI VT mode włączony:
```powershell
. .\src\lib\Ansi.ps1
[Console]::Write("$([char]27)[31mtest$([char]27)[0m`n")
# Jeśli widzisz literalny "ESC[31mtest" zamiast czerwonego "test" — VT nie działa
```

## TODO / pomysły na rozwój

- Pester testy dla `Format.ps1` (najłatwiejsze do testowania — czyste funkcje)
- Auto-update przez `update.ps1` (git pull lub re-download ZIP, zachowując configi)
- Wsparcie dla Whisper.cpp (szybsze, mniejsze VRAM) jako alternatywny backend
- Eksport rozdziałów do innych formatów (FCPXML dla Final Cut, YouTube chapter syntax)
- Streamowanie odpowiedzi z LLM-ów (Claude/Gemini wspierają SSE) zamiast czekać na pełną odpowiedź
- Drag-and-drop plików na Manager.ps1 (PowerShell może odbierać argumenty)
- GUI fallback (Windows Forms) dla nie-terminalowych userów

## Read-Host pollution — KRYTYCZNE

PowerShell funkcja **zwraca cały pipeline output**, nie tylko `return`. `Read-Host` w funkcji bez przypisania zwraca string do pipeline'a — pollutuje return value funkcji.

```powershell
function Foo {
    Read-Host "naciśnij Enter"      # ZŁE — zwracana wartość trafia do output
    return $null
}
$result = Foo
# $result = @("", $null) zamiast $null
```

**Fix**: zawsze prefiksuj `$null = ` lub `[void]`:

```powershell
function Foo {
    $null = Read-Host "naciśnij Enter"   # ✓
    return $null
}
```

To samo dotyczy każdego cmdlet z return value (np. `New-Item`, `Add-Member`) — albo użyj `| Out-Null`, albo `$null = `, albo `[void](...)`.

**Caller też powinien filtrować defensywnie**:
```powershell
$result = Foo
$result = @($result | Where-Object { $_ -and $_ -is [string] })
if ($result.Count -eq 0) { ... }
```

Nie polegaj tylko na `if (-not $result)` — `@("", $null)` jest truthy.

## Ważne — czego NIE robić

- **NIE używać Register-ObjectEvent** do capture stdout w pętlach pollujących
- **NIE używać cmd.exe wrappers** z polskimi znakami w ścieżkach
- **NIE używać `Clear-Host` w pętli renderu** (tylko raz przed lub przy resize)
- **NIE używać `Write-Host` w hot path** renderu (każdy `Write-Host` = pipeline overhead)
- **NIE importować lib/ jako `.psm1` moduł** — komplikacje z scope'em, dot-source jest prostszy
- **NIE zapisywać plików .ps1 bez UTF-8 BOM** — PS 5.1 przeczyta je w CP1250 i wszystkie polskie/unicode znaki staną się krzakami
- **NIE używać PS 7 syntax** (ternary, `??`, `?.`) — projekt musi działać na czystym Win10/11
- **NIE commitować `*.config.json`** — są w gitignore, mają lokalne ścieżki użytkownika

## Linki dokumentacja

- PowerShell 5.1: https://learn.microsoft.com/en-us/powershell/scripting/overview?view=powershell-5.1
- Approved Verbs: https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands
- Whisper CLI: https://github.com/openai/whisper#command-line-usage
- mkvmerge --chapters: https://mkvtoolnix.download/doc/mkvmerge.html#mkvmerge.description.chapters
- Matroska Chapters XML: https://mkvtoolnix.download/doc/mkvmerge.html#mkvmerge.chapter_files
- Anthropic API: https://docs.anthropic.com/en/api/messages
- Gemini API: https://ai.google.dev/api/rest
- Ollama API: https://github.com/ollama/ollama/blob/main/docs/api.md
- winget docs: https://learn.microsoft.com/en-us/windows/package-manager/winget/
