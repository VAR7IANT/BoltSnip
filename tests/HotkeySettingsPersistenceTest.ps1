param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path -LiteralPath $Executable).Path)
$settingsType = $assembly.GetType('BoltSnip.AppSettings', $true)
$flags = [Reflection.BindingFlags]'Static,Instance,NonPublic'
$load = $settingsType.GetMethod('Load', $flags, $null, [Type[]]@([string], [string]), $null)
$save = $settingsType.GetMethod('Save', $flags, $null, [Type[]]@([string]), $null)
$captureProperty = $settingsType.GetProperty('CaptureHotkey', [Reflection.BindingFlags]'Instance,NonPublic')
$replayProperty = $settingsType.GetProperty('ReplaySaveHotkey', [Reflection.BindingFlags]'Instance,NonPublic')
$directoryProperty = $settingsType.GetProperty('SaveDirectory', [Reflection.BindingFlags]'Instance,NonPublic')
$gestureType = $assembly.GetType('BoltSnip.HotkeyGesture', $true)
$gestureFlags = [Reflection.BindingFlags]'Instance,NonPublic'
$modifiersProperty = $gestureType.GetProperty('Modifiers', $gestureFlags)
$keyProperty = $gestureType.GetProperty('Key', $gestureFlags)

if ($null -eq $load -or $null -eq $save -or $null -eq $captureProperty -or $null -eq $replayProperty) {
    throw 'Hotkey settings persistence test seams were not found.'
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('BoltSnip-HotkeySettings-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$oldPath = Join-Path $testRoot 'legacy-current.ini'
$legacyPath = Join-Path $testRoot 'InstantShot.ini'
$newPath = Join-Path $testRoot 'explicit.ini'

function Read-Gesture($settings, $property) {
    $gesture = $property.GetValue($settings, $null)
    return [pscustomobject]@{
        Modifiers = [uint32]$modifiersProperty.GetValue($gesture, $null)
        Key = [int]$keyProperty.GetValue($gesture, $null)
    }
}

try {
    [IO.File]::WriteAllText(
        $oldPath,
        "Modifiers=6`r`nKey=65`r`nSaveDirectory=C:\Screenshots\BoltSnip`r`n",
        [Text.UTF8Encoding]::new($false))
    $loadArguments = New-Object 'object[]' 2
    $loadArguments[0] = [string]$oldPath
    $loadArguments[1] = [string]$legacyPath
    $oldSettings = $load.Invoke($null, $loadArguments)
    $migratedCapture = Read-Gesture $oldSettings $captureProperty
    $defaultReplay = Read-Gesture $oldSettings $replayProperty
    $migratedText = [IO.File]::ReadAllText($oldPath)
    $legacyCurrentMigrated = $migratedCapture.Modifiers -eq 6 -and $migratedCapture.Key -eq 65 -and
        $defaultReplay.Modifiers -eq 5 -and $defaultReplay.Key -eq 83 -and
        $migratedText.Contains('CaptureModifiers=6') -and $migratedText.Contains('CaptureKey=65') -and
        $migratedText.Contains('ReplaySaveModifiers=5') -and $migratedText.Contains('ReplaySaveKey=83') -and
        -not $migratedText.Contains("`r`nModifiers=") -and
        $directoryProperty.GetValue($oldSettings, $null) -eq 'C:\Screenshots\BoltSnip'

    [IO.File]::WriteAllText(
        $legacyPath,
        "Modifiers=2`r`nKey=82`r`nSaveDirectory=C:\OldScreenshots`r`n",
        [Text.UTF8Encoding]::new($false))
    $legacyOutputPath = Join-Path $testRoot 'migrated.ini'
    $loadArguments = New-Object 'object[]' 2
    $loadArguments[0] = [string]$legacyOutputPath
    $loadArguments[1] = [string]$legacyPath
    $legacySettings = $load.Invoke($null, $loadArguments)
    $legacyCapture = Read-Gesture $legacySettings $captureProperty
    $legacyReplay = Read-Gesture $legacySettings $replayProperty
    $legacyPathMigrated = $legacyCapture.Modifiers -eq 2 -and $legacyCapture.Key -eq 82 -and
        $legacyReplay.Modifiers -eq 5 -and $legacyReplay.Key -eq 83 -and
        [IO.File]::ReadAllText($legacyOutputPath).Contains('CaptureKey=82')

    [IO.File]::WriteAllText(
        $newPath,
        "CaptureModifiers=2`r`nCaptureKey=82`r`nReplaySaveModifiers=1`r`nReplaySaveKey=83`r`nModifiers=4`r`nKey=66`r`n",
        [Text.UTF8Encoding]::new($false))
    $loadArguments = New-Object 'object[]' 2
    $loadArguments[0] = [string]$newPath
    $loadArguments[1] = [string]$legacyPath
    $explicitSettings = $load.Invoke($null, $loadArguments)
    $explicitCapture = Read-Gesture $explicitSettings $captureProperty
    $explicitReplay = Read-Gesture $explicitSettings $replayProperty
    $saveArguments = New-Object 'object[]' 1
    $saveArguments[0] = [string]$newPath
    [void]$save.Invoke($explicitSettings, $saveArguments)
    $explicitText = [IO.File]::ReadAllText($newPath)
    $explicitFormatRoundTrips = $explicitCapture.Modifiers -eq 2 -and $explicitCapture.Key -eq 82 -and
        $explicitReplay.Modifiers -eq 1 -and $explicitReplay.Key -eq 83 -and
        $explicitText.Contains('ReplaySaveKey=83') -and -not $explicitText.Contains("`r`nModifiers=")

    $passed = $legacyCurrentMigrated -and $legacyPathMigrated -and $explicitFormatRoundTrips
    [pscustomobject]@{
        OldFieldsMigrateToCaptureAndDefaultReplay = $legacyCurrentMigrated
        LegacyFileMigratesToCurrentPath = $legacyPathMigrated
        NewFieldsPersistAndRoundTrip = $explicitFormatRoundTrips
        Passed = $passed
    } | Format-List
    if (-not $passed) { exit 1 }
}
finally {
    if ([IO.Directory]::Exists($testRoot)) { [IO.Directory]::Delete($testRoot, $true) }
}
