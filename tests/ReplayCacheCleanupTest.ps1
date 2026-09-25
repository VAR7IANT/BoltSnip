param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$managerType = $assembly.GetType('BoltSnip.ReplayManager', $true)
$cleanupMethod = $managerType.GetMethod(
    'CleanupStaleReplayCacheDirectories',
    [Reflection.BindingFlags]'Static,NonPublic')
if ($null -eq $cleanupMethod) { throw 'Replay cache cleanup method was not found.' }

function Invoke-CacheCleanup {
    param(
        [string]$RootPath,
        [DateTime]$AtUtc,
        [string]$ActivePath,
        [Action[string]]$DeleteAction
    )

    $arguments = New-Object 'object[]' 4
    $arguments[0] = $RootPath.PSObject.BaseObject
    $arguments[1] = $AtUtc
    $arguments[2] = if ([string]::IsNullOrEmpty($ActivePath)) { $null } else { $ActivePath.PSObject.BaseObject }
    $arguments[3] = if ($null -eq $DeleteAction) { $null } else { $DeleteAction.PSObject.BaseObject }
    $cleanupMethod.Invoke($null, $arguments)
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('BoltSnip-ReplayCacheCleanup-' + [Guid]::NewGuid().ToString('N'))
$root = Join-Path $testRoot 'sessions'
$failureRoot = Join-Path $testRoot 'cleanup-failure'
[IO.Directory]::CreateDirectory($root) | Out-Null
[IO.Directory]::CreateDirectory($failureRoot) | Out-Null

try {
    $nowUtc = [DateTime]::UtcNow
    $staleDirectory = Join-Path $root 'stale-sibling'
    $recentDirectory = Join-Path $root 'recent-sibling'
    $activeDirectory = Join-Path $root 'current-session'
    foreach ($directory in @($staleDirectory, $recentDirectory, $activeDirectory)) {
        [IO.Directory]::CreateDirectory($directory) | Out-Null
    }
    [IO.Directory]::SetLastWriteTimeUtc($staleDirectory, $nowUtc.AddDays(-2))
    [IO.Directory]::SetLastWriteTimeUtc($recentDirectory, $nowUtc.AddHours(-1))
    [IO.Directory]::SetLastWriteTimeUtc($activeDirectory, $nowUtc.AddDays(-2))

    [void](Invoke-CacheCleanup $root $nowUtc $activeDirectory $null)
    $staleDeleted = -not [IO.Directory]::Exists($staleDirectory)
    $recentSurvived = [IO.Directory]::Exists($recentDirectory)
    $activeSurvived = [IO.Directory]::Exists($activeDirectory)

    $failingStaleDirectory = Join-Path $failureRoot 'stale-delete-failure'
    [IO.Directory]::CreateDirectory($failingStaleDirectory) | Out-Null
    [IO.Directory]::SetLastWriteTimeUtc($failingStaleDirectory, $nowUtc.AddDays(-2))
    $rejectDelete = [Action[string]]{
        param([string]$path)
        throw [UnauthorizedAccessException]::new('Injected cleanup failure for test.')
    }
    $cleanupFailureWasContained = $true
    try {
        [void](Invoke-CacheCleanup $failureRoot $nowUtc $null $rejectDelete)
    }
    catch {
        $cleanupFailureWasContained = $false
    }

    # Cache creation proceeds after best-effort cleanup reports a deletion failure.
    $newSession = Join-Path $failureRoot 'new-session'
    [IO.Directory]::CreateDirectory($newSession) | Out-Null
    $initializationContinued = [IO.Directory]::Exists($newSession)

    $passed = $staleDeleted -and $recentSurvived -and $activeSurvived -and
        $cleanupFailureWasContained -and $initializationContinued
    [pscustomobject]@{
        RecentSiblingSurvivesCleanup = $recentSurvived
        StaleSiblingIsDeleted = $staleDeleted
        CurrentSessionIsNeverDeleted = $activeSurvived
        CleanupFailureDoesNotBlockInitialization = $cleanupFailureWasContained -and $initializationContinued
        Passed = $passed
    } | Format-List
    if (-not $passed) { exit 1 }
}
finally {
    if ([IO.Directory]::Exists($testRoot)) { [IO.Directory]::Delete($testRoot, $true) }
}
