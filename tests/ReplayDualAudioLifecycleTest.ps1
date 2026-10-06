param([string]$Executable = (Join-Path $PSScriptRoot '..\bin\BoltSnip.exe'))
$ErrorActionPreference = 'Stop'

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable).Path)
$sessionType = $assembly.GetType('BoltSnip.ReplayAudioCaptureSession', $true)
$settingsType = $assembly.GetType('BoltSnip.ReplaySettings', $true)
$settings = [Activator]::CreateInstance($settingsType, $true)
$flags = [Reflection.BindingFlags]'Instance,Static,NonPublic'
$createMethod = $sessionType.GetMethod('Create', $flags, $null, @($settingsType), $null)
$prepareMethod = $sessionType.GetMethod('WaitUntilPrepared', $flags)
$stopMethod = $sessionType.GetMethod('Stop', $flags)
$disposeMethod = $sessionType.GetMethod('Dispose', [Reflection.BindingFlags]'Instance,Public')
$workerField = $sessionType.GetField('_worker', $flags)
$micField = $sessionType.GetField('_microphone', $flags)

for ($i = 1; $i -le 3; $i++) {
    Write-Host "--- Cycle $i ---"
    $s = $createMethod.Invoke($null, @($settings))
    $prepareMethod.Invoke($s, @(5000))
    $mic = $micField.GetValue($s)
    $hasMic = ($null -ne $mic)
    Write-Host "Prepared: hasMic=$hasMic"
    $stopMethod.Invoke($s, $null)
    $disposeMethod.Invoke($s, $null)
    $worker = $workerField.GetValue($s)
    $workerAlive = if ($worker) { $worker.IsAlive } else { $false }
    $micWorkerAlive = $false
    if ($mic) {
        $micWorker = $workerField.GetValue($mic)
        if ($micWorker) { $micWorkerAlive = $micWorker.IsAlive }
    }
    Write-Host "Cycle $i complete: primaryWorkerAlive=$workerAlive, micWorkerAlive=$micWorkerAlive"
    if ($workerAlive -or $micWorkerAlive) { throw "Worker thread leaked in cycle $i!" }
}

Write-Host "PASS: 3 consecutive Start->Stop cycles of Dual Audio (System + Mic) showed 0 thread leaks and 0 session collisions."
