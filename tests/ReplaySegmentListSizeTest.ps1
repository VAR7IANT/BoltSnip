param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$flags = [Reflection.BindingFlags]'Instance,NonPublic'
$settingsType = $assembly.GetType('BoltSnip.ReplaySettings', $true)
$settingsConstructor = $settingsType.GetConstructor($flags, $null, [Type[]]@([TimeSpan],[int],[int]), $null)
$encoderType = $assembly.GetType('BoltSnip.ReplayEncoder', $true)
$encoder = [Activator]::CreateInstance($encoderType, $true)
$buildArguments = $encoderType.GetMethod('BuildArguments', $flags)
$sizeProperty = $settingsType.GetProperty('segment_list_size', $flags)

$cases = @(
    [pscustomobject]@{ BufferSeconds = 300; SegmentSeconds = 2; Expected = 152 }
    [pscustomobject]@{ BufferSeconds = 600; SegmentSeconds = 2; Expected = 302 }
    [pscustomobject]@{ BufferSeconds = 60; SegmentSeconds = 1; Expected = 62 }
)
$results = foreach ($case in $cases) {
    $settings = $settingsConstructor.Invoke([object[]]@(
        [TimeSpan]::FromSeconds($case.BufferSeconds), [int]60, [int]$case.SegmentSeconds))
    $size = [int]$sizeProperty.GetValue($settings, $null)
    $arguments = $buildArguments.Invoke($encoder, [object[]]@(
        'C:\cache\segments.csv', 'C:\cache\segment_%08d.mp4', '-f gdigrab ', $settings))
    $parameterMatches = [string]$arguments -match ('-segment_list_size\s+' + $case.Expected + '\s')
    [pscustomobject]@{
        BufferSeconds = $case.BufferSeconds
        SegmentSeconds = $case.SegmentSeconds
        Expected = $case.Expected
        SettingsValue = $size
        EncoderParameterCorrect = $parameterMatches
        Passed = $size -eq $case.Expected -and $parameterMatches
    }
}
$results | Format-Table -AutoSize
if (@($results | Where-Object { -not $_.Passed }).Count -gt 0) { exit 1 }
