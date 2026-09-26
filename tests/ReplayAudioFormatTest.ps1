param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$type = $assembly.GetType('BoltSnip.ReplayAudioFormat', $false)
if ($null -eq $type) { throw 'ReplayAudioFormat is not present in the build.' }
$parse = $type.GetMethod('Parse', [Reflection.BindingFlags]'Static,NonPublic')
if ($null -eq $parse) { throw 'ReplayAudioFormat.Parse is not present.' }

$pcmGuid = [Guid]'00000001-0000-0010-8000-00aa00389b71'
$floatGuid = [Guid]'00000003-0000-0010-8000-00aa00389b71'
function Parse-Format([int]$tag, [int]$bits, [int]$validBits, [int]$align, [Guid]$subFormat, [int]$extra) {
    return $parse.Invoke($null, [object[]]@($tag, 2, 48000, $bits, $align, $extra, $validBits, $subFormat))
}

$cases = @(
    @{ Name = 'float32'; Value = (Parse-Format 3 32 32 8 ([Guid]::Empty) 0); Expected = 'f32le'; Convert24 = $false },
    @{ Name = 'PCM16'; Value = (Parse-Format 1 16 16 4 ([Guid]::Empty) 0); Expected = 's16le'; Convert24 = $false },
    @{ Name = 'PCM24 packed'; Value = (Parse-Format 1 24 24 6 ([Guid]::Empty) 0); Expected = 's24le'; Convert24 = $false },
    @{ Name = 'PCM24 in 32-bit container'; Value = (Parse-Format 0xfffe 32 24 8 $pcmGuid 22); Expected = 's24le'; Convert24 = $true },
    @{ Name = 'PCM32'; Value = (Parse-Format 1 32 32 8 ([Guid]::Empty) 0); Expected = 's32le'; Convert24 = $false },
    @{ Name = 'extensible float32'; Value = (Parse-Format 0xfffe 32 32 8 $floatGuid 22); Expected = 'f32le'; Convert24 = $false }
)

$results = foreach ($case in $cases) {
    $format = $case.Value
    $actual = [string]$type.GetProperty('FfmpegSampleFormat', [Reflection.BindingFlags]'Instance,NonPublic').GetValue($format, $null)
    $convert = [bool]$type.GetProperty('RequiresPacked24Conversion', [Reflection.BindingFlags]'Instance,NonPublic').GetValue($format, $null)
    [pscustomobject]@{ Format = $case.Name; Actual = $actual; Expected = $case.Expected; ConvertPacked24 = $convert; Passed = ($actual -eq $case.Expected -and $convert -eq $case.Convert24) }
}
$results | Format-Table -AutoSize
if ($results.Where({ -not $_.Passed }).Count -gt 0) { exit 1 }

$unsupportedWasRejected = $false
try { [void](Parse-Format 1 8 8 2 ([Guid]::Empty) 0) }
catch { $unsupportedWasRejected = $true }
if (-not $unsupportedWasRejected) { throw 'Unsupported 8-bit PCM was silently accepted.' }
Write-Output 'Unsupported formats are rejected explicitly.'
