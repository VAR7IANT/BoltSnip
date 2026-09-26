param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
if (-not [IO.File]::Exists($Executable)) { throw "Required file was not found: $Executable" }

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$managerType = $assembly.GetType('BoltSnip.ReplayManager', $true)
$method = $managerType.GetMethod('RunEncoderShutdownFailSafe', [Reflection.BindingFlags]'Static,NonPublic')
if ($null -eq $method) { throw 'The testable encoder shutdown fail-safe helper was not found.' }

$script:stopCalls = 0
$script:logCalls = 0
$script:joinCalls = 0
$script:logMessage = $null
$script:callOrder = [Collections.Generic.List[string]]::new()
$stopEncoder = [Action] { $script:stopCalls++; $script:callOrder.Add('stop') }
$logShutdown = [Action] {
    $script:logCalls++
    $script:logMessage = 'Forced encoder shutdown after recording worker timeout'
    $script:callOrder.Add('log')
}
$shortJoin = [Action] { $script:joinCalls++; $script:callOrder.Add('join') }

[void]$method.Invoke($null, [object[]]@($false, $stopEncoder, $logShutdown, $shortJoin))
$normalShutdownDidNotForceEncoder = $script:stopCalls -eq 0 -and $script:logCalls -eq 0 -and $script:joinCalls -eq 0
[void]$method.Invoke($null, [object[]]@($true, $stopEncoder, $logShutdown, $shortJoin))
$forcedShutdownWasLogged = $script:stopCalls -eq 1 -and $script:logCalls -eq 1 -and
    $script:joinCalls -eq 1 -and $script:logMessage -ceq 'Forced encoder shutdown after recording worker timeout' -and
    [string]::Join(',', $script:callOrder) -ceq 'stop,join,log'

[pscustomobject]@{
    NormalShutdownPreservesWorkerOrdering = $normalShutdownDidNotForceEncoder
    TimedOutWorkerForcesEncoderStop = $script:stopCalls -eq 1
    ForcedShutdownLogIsExact = $forcedShutdownWasLogged
    CallOrder = [string]::Join(' -> ', $script:callOrder)
    ShortJoinFollowsEncoderStop = [string]::Join(',', $script:callOrder) -ceq 'stop,join,log'
    Passed = $normalShutdownDidNotForceEncoder -and $forcedShutdownWasLogged
} | Format-List

if (-not ($normalShutdownDidNotForceEncoder -and $forcedShutdownWasLogged)) { exit 1 }
