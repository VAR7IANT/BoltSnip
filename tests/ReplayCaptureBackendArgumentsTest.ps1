param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$flags = [Reflection.BindingFlags]'Instance,NonPublic'
$staticFlags = [Reflection.BindingFlags]'Static,NonPublic'
$backendType = $assembly.GetType('BoltSnip.ReplayCaptureBackend', $true)
$captureType = $assembly.GetType('BoltSnip.ReplayCaptureSession', $true)
$settingsType = $assembly.GetType('BoltSnip.ReplaySettings', $true)
$gdiBackend = [Enum]::Parse($backendType, 'GdiGrab')
$ddaBackend = [Enum]::Parse($backendType, 'DdaGrab')
$settings = [Activator]::CreateInstance($settingsType, $true)
$constructor = $captureType.GetConstructor($flags, $null, [Type[]]@($backendType), $null)
$buildInput = $captureType.GetMethod('BuildInputArguments', $flags)
if ($null -eq $constructor -or $null -eq $buildInput) { throw 'Capture backend argument APIs were not found.' }

$gdiSession = $constructor.Invoke(@($gdiBackend))
$ddaSession = $constructor.Invoke(@($ddaBackend))
$gdiArguments = [string]$buildInput.Invoke($gdiSession, @($settings))
$ddaArguments = [string]$buildInput.Invoke($ddaSession, @($settings))
$defaultSession = [Activator]::CreateInstance($captureType, $true)
$defaultArguments = [string]$buildInput.Invoke($defaultSession, @($settings))

$checks = [ordered]@{
    GdiUsesGdigrab = $gdiArguments.Contains('-f gdigrab') -and $gdiArguments.Contains('-i desktop')
    GdiKeepsMouseAndPhysicalSize = $gdiArguments.Contains('-draw_mouse 1') -and $gdiArguments -match '-video_size \d+x\d+'
    DdaUsesLavfiDdagrab = $ddaArguments.Contains('-f lavfi') -and $ddaArguments.Contains('ddagrab=output_idx=0:framerate=60:draw_mouse=1')
    DdaDoesNotAddCpuCopyFilters = -not $ddaArguments.Contains('hwdownload') -and -not $ddaArguments.Contains('hwupload')
    DefaultSessionRemainsGdiGrab = $defaultArguments.Contains('-f gdigrab')
}
$checks.GetEnumerator() | ForEach-Object { '{0}: {1}' -f $_.Key, $_.Value }
if ($checks.Values -contains $false) { exit 1 }
