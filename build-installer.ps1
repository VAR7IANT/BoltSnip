param(
    [string]$Version = '0.12.0',
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'dist')
)

$ErrorActionPreference = 'Stop'

$innoCompilerCandidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 7\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 7\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 7\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
)
$innoCompiler = $innoCompilerCandidates |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) } |
    Select-Object -First 1

if ([string]::IsNullOrWhiteSpace($innoCompiler)) {
    throw 'Inno Setup 7 was not found. Install it with: winget install --id JRSoftware.InnoSetup.7 -e -s winget'
}

$resolvedOutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $resolvedOutputDirectory | Out-Null

$applicationOutputDirectory = Join-Path $PSScriptRoot 'bin'
$executable = & (Join-Path $PSScriptRoot 'build.ps1') -OutputDirectory $applicationOutputDirectory
if ($LASTEXITCODE -ne 0) {
    throw "Application build failed with exit code $LASTEXITCODE"
}

$installerScript = Join-Path $PSScriptRoot 'installer\BoltSnip.iss'
$arguments = @(
    ('/DAppVersion=' + $Version),
    ('/DSourceExecutable=' + $executable),
    ('/O' + $resolvedOutputDirectory),
    $installerScript
)
& $innoCompiler $arguments
if ($LASTEXITCODE -ne 0) {
    throw "Installer compilation failed with exit code $LASTEXITCODE"
}

$installer = Join-Path $resolvedOutputDirectory ("BoltSnip-Setup-{0}-win-x64.exe" -f $Version)
if (-not (Test-Path -LiteralPath $installer)) {
    throw "Installer output was not created: $installer"
}

Write-Output $installer
