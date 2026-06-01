# Transcription Manager

Zestaw narzedzi PowerShell do pracy z transkrypcjami nagran:

- **Tworzenie transkrypcji** z plikow wideo przez [OpenAI Whisper](https://github.com/openai/whisper)
- **Dodawanie rozdzialow** do plikow MKV przez [MKVToolNix](https://mkvtoolnix.download/)

Wszystko z interaktywnym TUI: dialogi wyboru folderu Windows, przegladarka plikow ze strzalkami, multi-select, live dashboard postepu.

## Instalacja

Otworz PowerShell i wklej:

```powershell
irm https://raw.githubusercontent.com/CrystalPL/Transcryption-manager/main/install.ps1 | iex
```

Instalator:

1. Pobierze ostatnia wersje aplikacji do `C:\Transkrypcja\`
2. Sprawdzi zaleznosci (Python, whisper, ffmpeg, MKVToolNix, GPU)
3. Doinstaluje brakujace przez `winget` / `pip` (po pytaniu)
4. Doda skrot **Zarzadzanie transkrypcja** do Menu Start

Po instalacji wcisnij klawisz Windows i wpisz `Zarzadzanie` zeby uruchomic.

## Wymagania

- Windows 10 / 11
- PowerShell 5.1+ (jest domyslnie)
- Python 3.8+ (instalator zainstaluje)
- Karta NVIDIA z 4GB+ VRAM (opcjonalne, do GPU acceleration whispera)

## Struktura projektu

```
src/
├── Manager.ps1              # entry point — menu glowne
├── lib/                     # wspoldzielone helpery (dot-source'owane)
│   ├── Ansi.ps1             # kody ANSI, kolory, batched output
│   ├── Console.ps1          # Show-Header, Ask-TakNie, Fit
│   ├── Format.ps1           # Format-Size, Format-Time, naturalSort, durations
│   ├── Dialog.ps1           # Open-FolderDialog, Select-Folder
│   ├── Config.ps1           # Read-Config, Save-Config
│   ├── ShellMetadata.ps1    # Get-ShellDurations
│   ├── Picker.ps1           # Show-Picker — single-select z nawigacja
│   ├── MultiPicker.ps1      # Show-MultiPicker — multi-select plikow
│   └── Dashboard.ps1        # Render-Dashboard, View-Logs, progress parser
└── Scripts/
    ├── New-Transcription.ps1   # tworzenie transkrypcji whisperem
    └── Add-Chapters.ps1        # XML rozdzialow -> MKV
```

## Reczna instalacja (jesli nie chcesz uzywac instalatora)

```powershell
git clone https://github.com/CrystalPL/Transcryption-manager.git C:\Transkrypcja
cd C:\Transkrypcja
.\install.ps1 -SkipDownload
```

## Konfiguracja

Pliki konfiguracyjne (sciezki ostatnio uzywanych folderow, klucze API) sa zapisywane obok kazdego skryptu jako `*.config.json`. Sa w `.gitignore`, wiec nie sa commitowane.

## Odinstalowanie

```powershell
C:\Transkrypcja\uninstall.ps1
```

Usuwa aplikacje, skrot Start Menu i pliki konfiguracyjne. Nie usuwa Whispera, ffmpega ani MKVToolNix (mogłyby byc uzywane przez inne aplikacje).

## Licencja

MIT
