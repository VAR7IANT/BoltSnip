param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('init', 'issue')]
    [string]$Action,
    [string]$PrivateKeyPath = 'D:\Codex\Work\BoltSnip\owner-private.xml',
    [string]$PublicKeyPath,
    [string]$OutputPath = 'D:\Codex\Outputs\BoltSnip-owner.license'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
if ([string]::IsNullOrWhiteSpace($PublicKeyPath)) {
    $PublicKeyPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'licensing\owner-public.xml'
}
$privateFullPath = [IO.Path]::GetFullPath($PrivateKeyPath)
$projectRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent)).TrimEnd('\') + '\'
if ($privateFullPath.StartsWith($projectRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The private key must be stored outside the repository.'
}

if ($Action -eq 'init') {
    New-Item -ItemType Directory -Force -Path (Split-Path $privateFullPath -Parent) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path $PublicKeyPath -Parent) | Out-Null
    $existing = if (Test-Path -LiteralPath $privateFullPath) {
        [IO.File]::ReadAllText($privateFullPath)
    } else { $null }
    if ($null -eq $existing -and (Test-Path -LiteralPath $PublicKeyPath)) {
        throw 'Public key already exists; refusing to rotate it and invalidate issued licenses.'
    }
    if ($null -ne $existing -and -not $existing.StartsWith('<RSAKeyValue>')) {
        throw "Private key already exists; refusing to replace it: $privateFullPath"
    }
    $rsa = if ($null -ne $existing) {
        New-Object Security.Cryptography.RSACryptoServiceProvider
    } else {
        New-Object Security.Cryptography.RSACryptoServiceProvider -ArgumentList 3072
    }
    try {
        if ($null -ne $existing) { $rsa.FromXmlString($existing) }
        $privateBytes = [Text.Encoding]::UTF8.GetBytes($rsa.ToXmlString($true))
        $protected = [Security.Cryptography.ProtectedData]::Protect(
            $privateBytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        [IO.File]::WriteAllText($privateFullPath, [Convert]::ToBase64String($protected))
        [IO.File]::WriteAllText([IO.Path]::GetFullPath($PublicKeyPath), $rsa.ToXmlString($false))
    }
    finally { $rsa.Dispose() }
    Write-Output "Public key: $PublicKeyPath"
    Write-Output "Private key: $privateFullPath"
    return
}

if (-not (Test-Path -LiteralPath $privateFullPath)) {
    throw "Private key not found: $privateFullPath"
}
$rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
try {
    $protected = [Convert]::FromBase64String([IO.File]::ReadAllText($privateFullPath))
    $privateBytes = [Security.Cryptography.ProtectedData]::Unprotect(
        $protected, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    $rsa.FromXmlString([Text.Encoding]::UTF8.GetString($privateBytes))
    $payload = [Text.Encoding]::UTF8.GetBytes('BoltSnip|owner|1')
    $signature = $rsa.SignData($payload, [Security.Cryptography.HashAlgorithmName]::SHA256,
        [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $license = 'BS1.' + [Convert]::ToBase64String($payload) + '.' +
        [Convert]::ToBase64String($signature)
    New-Item -ItemType Directory -Force -Path (Split-Path $OutputPath -Parent) | Out-Null
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $license)
}
finally { $rsa.Dispose() }
Write-Output "Owner license: $OutputPath"
