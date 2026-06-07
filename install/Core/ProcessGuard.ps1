function Stop-ProcessTree {
    <#
    .SYNOPSIS Zabija proces i całe jego drzewo potomków (taskkill /T /F). Nie blokuje, nie rzuca.
    .PARAMETER Id PID procesu-korzenia drzewa do ubicia.
    .EXAMPLE Stop-ProcessTree -Id $proc.Id
    #>
    param([int]$Id)
    if (-not $Id -or $Id -le 0) { return }
    try { & taskkill.exe /PID $Id /T /F 2>$null | Out-Null } catch {}
}

function Wait-GuardedProcess {
    <#
    .SYNOPSIS Czeka na zakończenie procesu z twardym limitem czasu i opcjonalną detekcją zastoju; przy przekroczeniu ubija całe drzewo procesów i wraca.
    .DESCRIPTION Gwarantuje, że oczekiwanie nigdy nie trwa w nieskończoność. TimeoutSec to twardy sufit. Gdy podano LivenessProbe i StallSec>0, brak zmiany sygnału żywotności przez StallSec sekund również kończy oczekiwanie (martwa sieć).
    .PARAMETER Process Obiekt procesu z Start-Process -PassThru.
    .PARAMETER TimeoutSec Maksymalny czas oczekiwania w sekundach.
    .PARAMETER StallSec Brak zmiany sygnału przez tyle sekund = zastój (0 wyłącza detekcję).
    .PARAMETER LivenessProbe Scriptblock zwracający wartość, która rośnie/zmienia się gdy proces żyje (np. rozmiar pobieranego pliku).
    .PARAMETER OnTick Scriptblock wołany co iterację (np. odświeżenie UI).
    .PARAMETER PollMs Okres pętli w milisekundach.
    .EXAMPLE Wait-GuardedProcess -Process $p -TimeoutSec 1800 -StallSec 180 -LivenessProbe { (Get-Item $f -EA SilentlyContinue).Length }
    #>
    param(
        [Parameter(Mandatory = $true)] [System.Diagnostics.Process] $Process,
        [int] $TimeoutSec = 1800,
        [int] $StallSec = 0,
        [scriptblock] $LivenessProbe,
        [scriptblock] $OnTick,
        [int] $PollMs = 500
    )
    try { $null = $Process.Handle } catch {}

    $start      = Get-Date
    $lastChange = Get-Date
    $lastVal    = [string]::Empty
    $haveProbe  = ($StallSec -gt 0 -and $null -ne $LivenessProbe)

    while (-not $Process.HasExited) {
        if ($OnTick) { try { & $OnTick } catch {} }
        Start-Sleep -Milliseconds $PollMs
        $now = Get-Date

        if ($haveProbe) {
            $v = [string]::Empty
            try { $v = [string](& $LivenessProbe) } catch {}
            if ($v -ne $lastVal) { $lastVal = $v; $lastChange = $now }
            elseif ((($now - $lastChange).TotalSeconds) -ge $StallSec) {
                Stop-ProcessTree -Id $Process.Id
                return [pscustomobject]@{ Completed = $false; ExitCode = $null; Reason = 'stall' }
            }
        }

        if ((($now - $start).TotalSeconds) -ge $TimeoutSec) {
            Stop-ProcessTree -Id $Process.Id
            return [pscustomobject]@{ Completed = $false; ExitCode = $null; Reason = 'timeout' }
        }
    }

    return [pscustomobject]@{ Completed = $true; ExitCode = $Process.ExitCode; Reason = 'exited' }
}

function Start-TrackedJob {
    <#
    .SYNOPSIS Uruchamia Start-Job i wykrywa PID jego procesu-dziecka, by Stop-TrackedJob mógł go pewnie ubić bez polegania na Stop-Job.
    .PARAMETER ScriptBlock Treść zadania.
    .PARAMETER ArgumentList Argumenty przekazywane do zadania.
    .EXAMPLE $t = Start-TrackedJob -ScriptBlock $sb -ArgumentList @($a, $b)
    #>
    param(
        [Parameter(Mandatory = $true)] [scriptblock] $ScriptBlock,
        [object[]] $ArgumentList = @()
    )
    $before = @()
    try { $before = @((Get-CimInstance Win32_Process -Filter "ParentProcessId=$PID AND Name='powershell.exe'" -ErrorAction SilentlyContinue).ProcessId) } catch {}

    $job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList

    $childPid = $null
    for ($i = 0; $i -lt 20 -and -not $childPid; $i++) {
        Start-Sleep -Milliseconds 100
        $after = @()
        try { $after = @((Get-CimInstance Win32_Process -Filter "ParentProcessId=$PID AND Name='powershell.exe'" -ErrorAction SilentlyContinue).ProcessId) } catch {}
        $new = @($after | Where-Object { $before -notcontains $_ })
        if ($new.Count -gt 0) { $childPid = $new[0] }
    }

    return [pscustomobject]@{ Job = $job; ChildPid = $childPid }
}

function Stop-TrackedJob {
    <#
    .SYNOPSIS Bezpiecznie kończy zadanie z Start-TrackedJob — ubija drzewo procesu-dziecka i usuwa obiekt zadania, nigdy nie blokując.
    .PARAMETER Tracked Obiekt zwrócony przez Start-TrackedJob.
    .EXAMPLE Stop-TrackedJob -Tracked $t
    #>
    param([Parameter(Mandatory = $true)] $Tracked)
    if ($Tracked.ChildPid) { Stop-ProcessTree -Id $Tracked.ChildPid }
    try { Remove-Job -Job $Tracked.Job -Force -ErrorAction SilentlyContinue } catch {}
}
