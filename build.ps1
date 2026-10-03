param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'bin'),
    [switch]$EnableLicensing,
    [string]$OwnerPublicKeyPath,
    [string]$LicenseServerUrl
)

$ErrorActionPreference = 'Stop'
$identityPath = Join-Path $PSScriptRoot 'release.json'
if (-not (Test-Path -LiteralPath $identityPath)) {
    throw "Release identity was not found: $identityPath"
}
$identity = Get-Content -Raw -Encoding UTF8 $identityPath | ConvertFrom-Json
if ($EnableLicensing) {
    if ([string]::IsNullOrWhiteSpace($OwnerPublicKeyPath) -or
        -not (Test-Path -LiteralPath $OwnerPublicKeyPath) -or
        [string]::IsNullOrWhiteSpace($LicenseServerUrl)) {
        throw 'Licensed builds need -OwnerPublicKeyPath and -LicenseServerUrl.'
    }
    $uri = $null
    if (-not [Uri]::TryCreate($LicenseServerUrl, [UriKind]::Absolute, [ref]$uri) -or
        ($uri.Scheme -ne 'https' -and
         -not ($uri.Scheme -eq 'http' -and $uri.Host -in @('localhost', '127.0.0.1')))) {
        throw 'The activation URL must use HTTPS, except for localhost experiments.'
    }
    $ownerPublicKey = Get-Content -Raw -LiteralPath $OwnerPublicKeyPath
    if ($ownerPublicKey -match '<D>|<P>|<Q>|<DP>|<DQ>|<InverseQ>') {
        throw 'The owner public key file contains private key material.'
    }
    $rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
    try { $rsa.FromXmlString($ownerPublicKey) }
    finally { $rsa.Dispose() }
} else {
    $ownerPublicKey = ''
    $LicenseServerUrl = ''
}
if ([string]::IsNullOrWhiteSpace($identity.ProductName) -or
    $identity.Version -notmatch '^\d+\.\d+\.\d+$' -or
    $identity.MinimumSupportedVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw 'release.json must contain ProductName and three-part Version/MinimumSupportedVersion values.'
}
$version = [Version]$identity.Version
$assemblyVersion = '{0}.{1}.{2}.0' -f $version.Major, $version.Minor, $version.Build
$buildTimeUtc = [DateTime]::UtcNow.ToString('O', [Globalization.CultureInfo]::InvariantCulture)
$commit = $null
$git = Get-Command git.exe -ErrorAction SilentlyContinue
if ($null -ne $git) {
    $gitProcess = New-Object Diagnostics.Process
    $gitProcess.StartInfo.FileName = $git.Source
    $gitProcess.StartInfo.Arguments = '-C "' + $PSScriptRoot + '" rev-parse HEAD'
    $gitProcess.StartInfo.UseShellExecute = $false
    $gitProcess.StartInfo.CreateNoWindow = $true
    $gitProcess.StartInfo.RedirectStandardOutput = $true
    $gitProcess.StartInfo.RedirectStandardError = $true
    [void]$gitProcess.Start()
    $commit = $gitProcess.StandardOutput.ReadToEnd().Trim()
    $gitProcess.WaitForExit()
    if ($gitProcess.ExitCode -ne 0) { $commit = $null }
    $gitProcess.Dispose()
}
$buildId = if ([string]::IsNullOrWhiteSpace($commit)) {
    'local-' + [DateTime]::UtcNow.ToString('yyyyMMddHHmmssZ', [Globalization.CultureInfo]::InvariantCulture)
} else {
    $commit.Trim() + $(
        & $git.Source -C $PSScriptRoot diff --quiet HEAD -- src build.ps1
        if ($LASTEXITCODE -ne 0) { '.dirty' }
    )
}

function ConvertTo-CSharpLiteral([string]$value) {
    return $value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n')
}

$compiler = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    $compiler = 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if (-not (Test-Path -LiteralPath $compiler)) {
    throw 'The system C# compiler was not found. Install .NET Framework 4.8.'
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$intermediateDirectory = Join-Path $OutputDirectory 'intermediate'
New-Item -ItemType Directory -Force -Path $intermediateDirectory | Out-Null
$generatedIdentity = Join-Path $intermediateDirectory 'ReleaseIdentity.g.cs'
$generatedManifest = Join-Path $intermediateDirectory 'app.manifest'
$productNameLiteral = ConvertTo-CSharpLiteral ([string]$identity.ProductName)
$versionLiteral = ConvertTo-CSharpLiteral ([string]$identity.Version)
$minimumVersionLiteral = ConvertTo-CSharpLiteral ([string]$identity.MinimumSupportedVersion)
$buildTimeLiteral = ConvertTo-CSharpLiteral $buildTimeUtc
$buildIdLiteral = ConvertTo-CSharpLiteral $buildId
$ownerPublicKeyLiteral = ConvertTo-CSharpLiteral $ownerPublicKey
$licenseServerLiteral = ConvertTo-CSharpLiteral $LicenseServerUrl
$licensingEnabledLiteral = if ($EnableLicensing) { 'true' } else { 'false' }
$informationalVersionLiteral = ConvertTo-CSharpLiteral (([string]$identity.Version) + '+' + $buildId.Replace('-', '.'))
$generatedSource = @"
using System.Reflection;

[assembly: AssemblyTitle("$productNameLiteral")]
[assembly: AssemblyProduct("$productNameLiteral")]
[assembly: AssemblyVersion("$assemblyVersion")]
[assembly: AssemblyFileVersion("$assemblyVersion")]
[assembly: AssemblyInformationalVersion("$informationalVersionLiteral")]
[assembly: AssemblyMetadata("BuildTimeUtc", "$buildTimeLiteral")]
[assembly: AssemblyMetadata("BuildId", "$buildIdLiteral")]

namespace BoltSnip
{
    internal static class BuildIdentityValues
    {
        internal const string ProductName = "$productNameLiteral";
        internal const string Version = "$versionLiteral";
        internal const string MinimumSupportedVersion = "$minimumVersionLiteral";
        internal const string BuildTimeUtc = "$buildTimeLiteral";
        internal const string BuildId = "$buildIdLiteral";
    }

    internal static class LicensingValues
    {
        internal const bool Enabled = $licensingEnabledLiteral;
        internal const string OwnerPublicKeyXml = "$ownerPublicKeyLiteral";
        internal const string ServerUrl = "$licenseServerLiteral";
    }
}
"@
[IO.File]::WriteAllText($generatedIdentity, $generatedSource, [Text.UTF8Encoding]::new($true))
$manifestTemplate = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot 'app.manifest')
$manifestContents = $manifestTemplate.Replace('__ASSEMBLY_VERSION__', $assemblyVersion).Replace('__PRODUCT_NAME__', [string]$identity.ProductName)
[IO.File]::WriteAllText($generatedManifest, $manifestContents, [Text.UTF8Encoding]::new($true))
$sources = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'src') -Filter '*.cs' | ForEach-Object { $_.FullName }) + $generatedIdentity
$output = Join-Path $OutputDirectory 'BoltSnip.exe'
$manifest = $generatedManifest
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

$assemblyName = [Reflection.AssemblyName]::GetAssemblyName($output)
$versionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($output)
if ($assemblyName.Version.ToString() -ne $assemblyVersion -or
    $versionInfo.FileVersion -ne $assemblyVersion -or
    $versionInfo.ProductName -ne [string]$identity.ProductName -or
    -not $versionInfo.ProductVersion.StartsWith([string]$identity.Version, [StringComparison]::Ordinal)) {
    throw "Built executable identity does not match release.json: $output"
}

Write-Output $output
