param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'bin')
)

$ErrorActionPreference = 'Stop'
$compiler = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    $compiler = 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if (-not (Test-Path -LiteralPath $compiler)) {
    throw 'The system C# compiler was not found. Install .NET Framework 4.8.'
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$sources = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'src') -Filter '*.cs' | ForEach-Object { $_.FullName }
$output = Join-Path $OutputDirectory 'BoltSnip.exe'
$manifest = Join-Path $PSScriptRoot 'app.manifest'
$iconPreview = Join-Path $OutputDirectory 'app-icon-preview.png'
$iconOutput = Join-Path $OutputDirectory 'app-icon.ico'
$iconBuilderSource = Join-Path $PSScriptRoot 'tools\IconBuilder.cs'
$iconBuilder = Join-Path $OutputDirectory 'IconBuilder.exe'

$iconBuilderArguments = @(
    '/nologo',
    '/target:exe',
    '/platform:x64',
    '/optimize+',
    '/unsafe+',
    ('/out:' + $iconBuilder),
    '/reference:System.dll',
    '/reference:System.Drawing.dll',
    $iconBuilderSource
)
& $compiler $iconBuilderArguments
if ($LASTEXITCODE -ne 0) {
    throw "Icon builder compilation failed with exit code $LASTEXITCODE"
}

& $iconBuilder $iconOutput $iconPreview
if ($LASTEXITCODE -ne 0) {
    throw "Icon generation failed with exit code $LASTEXITCODE"
}

$arguments = @(
    '/nologo',
    '/target:winexe',
    '/platform:x64',
    '/optimize+',
    '/debug-',
    ('/win32manifest:' + $manifest),
    ('/win32icon:' + $iconOutput),
    ('/out:' + $output),
    '/reference:System.dll',
    '/reference:System.Core.dll',
    '/reference:System.Drawing.dll',
    '/reference:System.Windows.Forms.dll'
) + $sources

& $compiler $arguments

if ($LASTEXITCODE -ne 0) {
    throw "Compilation failed with exit code $LASTEXITCODE"
}

Write-Output $output
