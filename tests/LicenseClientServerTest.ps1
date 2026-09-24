param(
    [string]$Executable,
    [int]$ServerPort = 8765
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($Executable)) {
    $Executable = Join-Path $root 'bin\licensed-test\BoltSnip.exe'
}
$database = Join-Path $root ('bin\license-client-server-' + [Guid]::NewGuid().ToString('N') + '.db')
$serverScript = Join-Path $root 'licensing\server.py'
$key = (& python $serverScript --db $database create).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Could not create test license.' }
$service = $null
try {
    $service = Start-Process -FilePath (Get-Command python).Source -WindowStyle Hidden -PassThru -ArgumentList @($serverScript, '--db', $database, 'serve', '--port', $ServerPort)
    $ready = $false
    for ($attempt = 0; $attempt -lt 50; $attempt++) {
        try {
            $connection = New-Object Net.Sockets.TcpClient('127.0.0.1', $ServerPort)
            $connection.Dispose()
            $ready = $true
            break
        }
        catch { Start-Sleep -Milliseconds 100 }
    }
    if (-not $ready) { throw 'Activation service did not start.' }

    $assembly = [Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($Executable))
    $type = $assembly.GetType('BoltSnip.LicenseManager', $true)
    $method = $type.GetMethod('Request', [Reflection.BindingFlags]'Static,NonPublic')
    $activated = [string]$method.Invoke($null, @('activate', $key))
    $checked = [string]$method.Invoke($null, @('check', $key))
    $invalid = [string]$method.Invoke($null, @('check', 'BS-invalid'))
    if ($activated -ne 'OK' -or $checked -ne 'OK' -or $invalid -ne 'INVALID') {
        throw "Client/server mismatch: activated=$activated checked=$checked invalid=$invalid"
    }
    Write-Output 'BoltSnip client to activation server: PASS'
}
finally {
    if ($null -ne $service) {
        $service.Refresh()
        if (-not $service.HasExited) { Stop-Process -Id $service.Id }
        $service.Dispose()
    }
    Remove-Item -LiteralPath $database -Force -ErrorAction SilentlyContinue
}
