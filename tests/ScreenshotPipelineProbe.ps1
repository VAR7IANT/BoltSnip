param(
    [Parameter(Mandatory=$true)][string]$ProductExe,
    [string]$OutputDirectory = 'D:\Codex\Work\BoltSnip-ScreenshotPipelineProbe',
    [string]$ExpectedCommit = '',
    [string]$SourceImage = '',
    [int]$X = 100, [int]$Y = 100, [int]$Width = 500, [int]$Height = 400,
    [switch]$RequireExactStatic,
    [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
if ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($OutputDirectory)) -ne 'D:\') { throw 'Evidence must use D drive.' }
if (-not (Test-Path -LiteralPath $ProductExe -PathType Leaf)) { throw 'ProductExe does not exist.' }
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$probe = Join-Path $OutputDirectory 'ScreenshotPipelineProbe.exe'
$compiler = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:exe /r:System.Drawing.dll /r:System.Windows.Forms.dll "/out:$probe" (Join-Path $PSScriptRoot 'ScreenshotPipelineProbe.cs')
if ($LASTEXITCODE -ne 0) { throw 'Diagnostic compile failed.' }
if ($PrepareOnly) { Write-Output "Prepared only: $probe"; return }
# Requires an interactive desktop displaying the actual STATIC user symptom scene.
# This invokes the real overlay and temporarily replaces the clipboard, then restores it.
# ExpectedCommit is an operator assertion, not inferred executable provenance.
if ([string]::IsNullOrWhiteSpace($ExpectedCommit)) { $ExpectedCommit = "unspecified" }
$runDirectory = Join-Path $OutputDirectory ([Guid]::NewGuid().ToString('N'))
& $probe ([IO.Path]::GetFullPath($ProductExe)) $runDirectory $ExpectedCommit $X $Y $Width $Height $SourceImage
if ($LASTEXITCODE -ne 0) { throw "Diagnostic incomplete: $runDirectory" }
if ($RequireExactStatic) {
    if ([string]::IsNullOrWhiteSpace($SourceImage)) { throw 'RequireExactStatic needs SourceImage.' }
    $rows = @(Import-Csv -LiteralPath (Join-Path $runDirectory 'repeated-captures.tsv') -Delimiter "`t")
    $stages = @(Import-Csv -LiteralPath (Join-Path $runDirectory 'metrics.tsv') -Delimiter "`t")
    $log = Get-Content -LiteralPath (Join-Path $runDirectory 'capture.log') -Raw
    if ($rows.Count -ne 100 -or $stages.Count -ne 6 -or
        @($rows | Where-Object { [int]$_.RGBA_mismatches -ne 0 -or [int]$_.anomalies -ne 0 }).Count -ne 0 -or
        @($stages | Where-Object { [int]$_.anomalies -ne 0 -or [int]$_.mismatchesAgainstStage0 -ne 0 }).Count -ne 0 -or
        $log -match 'verdict=FAIL|Clipboard restore FAILED' -or $log -notmatch 'GdiDelta=0') {
        throw "Static pipeline regression FAILED; preserve evidence: $runDirectory"
    }
    Write-Output 'Static pipeline regression PASS; this does not satisfy browser/multi-monitor/real-DPI acceptance.'
}
Write-Output "Evidence collected for review; no FIX READY verdict: $runDirectory"
