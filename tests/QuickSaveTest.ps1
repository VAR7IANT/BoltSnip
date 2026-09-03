param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$overlayType = $assembly.GetType('BoltSnip.CaptureOverlay', $true)
$settingsType = $assembly.GetType('BoltSnip.AppSettings', $true)
$flags = [Reflection.BindingFlags]'Static,NonPublic'
$buildPath = $overlayType.GetMethod('BuildUniqueSavePath', $flags)
$shouldPrompt = $overlayType.GetMethod('ShouldPromptSave', $flags)
$defaultDirectoryProperty = $settingsType.GetProperty('DefaultSaveDirectory', $flags)

$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('BoltSnip-QuickSave-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testDirectory) | Out-Null
try {
    $timestamp = [DateTime]::new(2026, 8, 13, 12, 34, 56, 789)
    $pathArguments = New-Object 'object[]' 2
    $pathArguments[0] = $testDirectory.PSObject.BaseObject
    $pathArguments[1] = $timestamp.PSObject.BaseObject
    [string]$firstPath = $buildPath.Invoke($null, $pathArguments)
    [IO.File]::WriteAllText($firstPath, 'occupied')
    [string]$secondPath = $buildPath.Invoke($null, $pathArguments)

    $shiftRight = $shouldPrompt.Invoke($null, @([Windows.Forms.MouseButtons]::Right, [Windows.Forms.Keys]::Shift))
    $plainRight = $shouldPrompt.Invoke($null, @([Windows.Forms.MouseButtons]::Right, [Windows.Forms.Keys]::None))
    $shiftLeft = $shouldPrompt.Invoke($null, @([Windows.Forms.MouseButtons]::Left, [Windows.Forms.Keys]::Shift))
    $defaultDirectory = $defaultDirectoryProperty.GetValue($null, $null)

    $firstNameMatches = [IO.Path]::GetFileName($firstPath).EndsWith('_20260813_123456_789.png')
    $secondNameMatches = [IO.Path]::GetFileName($secondPath).EndsWith('_20260813_123456_789_2.png')
    $passed = $firstNameMatches -and
        $secondNameMatches -and
        $shiftRight -and -not $plainRight -and -not $shiftLeft -and
        [IO.Path]::IsPathRooted($defaultDirectory)

    [pscustomobject]@{
        FirstFileName = [IO.Path]::GetFileName($firstPath)
        CollisionFileName = [IO.Path]::GetFileName($secondPath)
        TimestampedPngName = $firstNameMatches
        CollisionSafeSuffix = $secondNameMatches
        ShiftRightOpensSaveAs = $shiftRight
        PlainRightQuickSaves = -not $plainRight
        DefaultDirectoryIsAbsolute = [IO.Path]::IsPathRooted($defaultDirectory)
        Passed = $passed
    } | Format-List

    if (-not $passed) {
        exit 1
    }
}
finally {
    if ([IO.Directory]::Exists($testDirectory)) {
        [IO.Directory]::Delete($testDirectory, $true)
    }
}
