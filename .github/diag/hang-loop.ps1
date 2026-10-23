# Run fpm-test repeatedly. When a run outlives the timeout, sample its memory
# and CPU, take gdb backtraces of the live process, then kill it.
param(
    [Parameter(Mandatory)] [string] $Label,
    [Parameter(Mandatory)] [int] $Runs,
    [Parameter(Mandatory)] [int] $TimeoutSec,
    [int] $MaxHangs = 2,
    [string[]] $TestArgs = @()
)
$ErrorActionPreference = 'Continue'
$exe = $env:EXE
$gdb = $env:GDB
$ok = 0; $failed = 0; $hangs = 0; $done = 0
$out = Join-Path $env:RUNNER_TEMP "$Label-out.txt"
$err = Join-Path $env:RUNNER_TEMP "$Label-err.txt"
$clock = [Diagnostics.Stopwatch]::StartNew()

for ($i = 1; $i -le $Runs; $i++) {
    $done = $i
    $start = @{ FilePath = $exe; NoNewWindow = $true; PassThru = $true
                RedirectStandardOutput = $out; RedirectStandardError = $err }
    if ($TestArgs.Count -gt 0) { $start.ArgumentList = $TestArgs }
    $p = Start-Process @start
    $null = $p.Handle   # keeps ExitCode available after exit

    if ($p.WaitForExit($TimeoutSec * 1000)) {
        $p.WaitForExit()
        if ($p.ExitCode -eq 0) { $ok++ } else {
            $failed++
            Write-Host "::warning::$Label run $i exited with code $($p.ExitCode)"
            Get-Content $out -Tail 15 | Write-Host
            Get-Content $err -Tail 15 | Write-Host
        }
        continue
    }

    $hangs++
    Write-Host "::error::$Label run $i still running after $TimeoutSec s (pid $($p.Id))"
    Write-Host '--- last output lines'
    Get-Content $out -Tail 5 | Write-Host
    Write-Host '--- memory and CPU, every 2 s'
    for ($s = 0; $s -lt 8; $s++) {
        $q = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
        if (-not $q) { Write-Host 'process exited'; break }
        ('{0:HH:mm:ss}  working set {1,9:N1} MB  private {2,9:N1} MB  peak working set {3,9:N1} MB  CPU {4,8:N2} s  threads {5}  handles {6}' -f `
            (Get-Date), ($q.WorkingSet64 / 1MB), ($q.PrivateMemorySize64 / 1MB), ($q.PeakWorkingSet64 / 1MB), `
            $q.TotalProcessorTime.TotalSeconds, $q.Threads.Count, $q.HandleCount) | Write-Host
        Start-Sleep -Seconds 2
    }
    foreach ($pass in 1, 2) {
        Write-Host "--- gdb backtrace, pass $pass"
        & $gdb -p $p.Id -batch -nx -ex 'set pagination off' -ex 'info threads' -ex 'thread apply all bt 40' 2>&1 | Write-Host
        Start-Sleep -Seconds 3
    }
    Write-Host '--- gdb locals, innermost frames of thread 1'
    & $gdb -p $p.Id -batch -nx -ex 'set pagination off' -ex 'thread 1' -ex 'bt full 8' 2>&1 | Write-Host
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    if ($hangs -ge $MaxHangs) { break }
}

$line = "gcc $($env:GCC), ${Label}: $done runs, $ok passed, $failed failed, $hangs hung ($([int]$clock.Elapsed.TotalSeconds) s)"
Write-Host $line
"- $line" >> $env:GITHUB_STEP_SUMMARY
