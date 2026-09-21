param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$definition = Get-Content -Raw -Encoding UTF8 (Join-Path (Split-Path $PSScriptRoot -Parent) 'release.json') | ConvertFrom-Json
$logPath = Join-Path $env:TEMP ('BoltSnip-startup-' + [Guid]::NewGuid().ToString('N') + '.log')
$env:BOLTSNIP_DIAGNOSTIC_LOG = '1'
$env:BOLTSNIP_DIAGNOSTIC_LOG_PATH = $logPath
$process = $null

try {
    $process = Start-Process -FilePath $Executable -WindowStyle Hidden -PassThru
    for ($attempt = 0; $attempt -lt 100 -and -not (Test-Path -LiteralPath $logPath); $attempt++) {
        Start-Sleep -Milliseconds 10
    }
    if (Test-Path -LiteralPath $logPath) {
        for ($attempt = 0; $attempt -lt 100; $attempt++) {
            $contents = Get-Content -Raw -LiteralPath $logPath
            if ($contents -match '\| Startup \|') { break }
            Start-Sleep -Milliseconds 10
        }
    }

    $process.Refresh()
    $contents = if (Test-Path -LiteralPath $logPath) { Get-Content -Raw -LiteralPath $logPath } else { '' }
    $startupRecorded = $contents -match '\| Startup \|'
    $versionRecorded = $contents -match ('Version=' + [Regex]::Escape([string]$definition.Version))
    $pathRecorded = $contents.Contains('Path=' + [IO.Path]::GetFullPath($Executable))
    $pidRecorded = $contents.Contains('PID=' + $process.Id)
    $timeRecorded = $contents -match 'StartedAtUtc=[^;]+'
    $processRunning = -not $process.HasExited
    $passed = $startupRecorded -and $versionRecorded -and $pathRecorded -and
        $pidRecorded -and $timeRecorded -and $processRunning

    [pscustomobject]@{
        StartupRecorded = $startupRecorded
        VersionRecorded = $versionRecorded
        ExecutablePathRecorded = $pathRecorded
        ProcessIdRecorded = $pidRecorded
        StartupTimeRecorded = $timeRecorded
        ProcessRunning = $processRunning
        Passed = $passed
    } | Format-List

    if (-not $passed) { exit 1 }
}
finally {
    if ($null -ne $process) {
        $process.Refresh()
        if (-not $process.HasExited) { Stop-Process -Id $process.Id }
    }
    Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
    Remove-Item Env:BOLTSNIP_DIAGNOSTIC_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:BOLTSNIP_DIAGNOSTIC_LOG_PATH -ErrorAction SilentlyContinue
}
