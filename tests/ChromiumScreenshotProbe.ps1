param(
    [Parameter(Mandatory=$true)][string]$ProductExe,
    [string]$SourceImage = 'C:\Users\VAR7IANT\Downloads\微信图片_20261002211430_14028_160.png',
    [string]$OutputDirectory = 'D:\Codex\Work\BoltSnip-ChromiumScreenshotProbe',
    [string]$EdgeExe = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    [int]$Iterations = 100,
    [int]$SampleSpacing = 1,
    [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
if ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($OutputDirectory)) -ne 'D:\') { throw 'Evidence and browser profile must use D drive.' }
foreach ($file in @($ProductExe,$SourceImage,$EdgeExe)) { if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "File not found: $file" } }
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$probe = Join-Path $OutputDirectory 'ChromiumScreenshotProbe.exe'
& 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe' /nologo /target:exe /r:System.Drawing.dll /r:System.Windows.Forms.dll "/out:$probe" (Join-Path $PSScriptRoot 'ChromiumScreenshotProbe.cs')
if ($LASTEXITCODE -ne 0) { throw 'Chromium diagnostic compile failed.' }
if ($PrepareOnly) { Write-Output "Compiled only: $probe"; return }
if ($Iterations -lt 1) { throw 'Iterations must be positive.' }
if ($SampleSpacing -lt 1) { throw 'SampleSpacing must be positive; 1 checks every ROI pixel.' }
$token = 'BoltSnipProbe-' + [Guid]::NewGuid().ToString('N')
$run = Join-Path $OutputDirectory $token
[IO.Directory]::CreateDirectory($run) | Out-Null
$sourceUri = ([Uri]([IO.Path]::GetFullPath($SourceImage))).AbsoluteUri
$html = @"
<!doctype html><html><head><meta charset='utf-8'><title>$token</title>
<meta http-equiv='Content-Security-Policy' content="default-src 'none'; img-src file:; style-src 'unsafe-inline'; script-src 'none'; connect-src 'none'">
<style>
*{box-sizing:border-box}html,body{margin:0;background:#0d0b0c;color:#ddd;font:18px Segoe UI,sans-serif}
main{width:1200px;min-height:1000px;padding:32px;background:linear-gradient(120deg,#0d0b0c,#131927 60%,#0d0b0c)}
h1{font-size:25px;margin:0 0 16px}.grid{display:grid;grid-template-columns:360px 720px;gap:24px}
.card{border-radius:22px;padding:22px;box-shadow:0 12px 32px #0009;background:linear-gradient(140deg,#15191eaa,#26283fcc);border:1px solid #ffffff12}
.palette{height:140px;background:linear-gradient(90deg,#0d0b0c,#111314,#242024,#010203);border-radius:15px;box-shadow:inset 0 0 12px #0008}
p{line-height:1.6}.source{width:720px;height:850px;background:#0d0b0c;overflow:hidden;border-radius:16px}.source img{display:block;width:720px;height:auto;transform:translateZ(0)}
.swatches{display:flex;gap:4px;margin-top:24px}.swatches span{width:32px;height:32px;border-radius:6px;background:#0d0b0c}
</style></head><body><main><h1>Chromium static screenshot diagnostic</h1><div class='grid'>
<section class='card'><div class='palette'></div><p>Dark text and gradients<br>透明阴影 · 圆角卡片<br>0123456789 ABC abc</p><div class='swatches'><span></span><span style='background:#11100f'></span><span style='background:#191718'></span><span style='background:#d3d3d3'></span></div></section>
<section class='source'><img src='$sourceUri'></section></div></main></body></html>
"@
$fixture = Join-Path $run 'fixture.html'
[IO.File]::WriteAllText($fixture,$html,[Text.UTF8Encoding]::new($false))
# Owns one isolated Edge browser process/profile. No GPU-disabling flags.
& $probe ([IO.Path]::GetFullPath($ProductExe)) $run ([IO.Path]::GetFullPath($EdgeExe)) ([Uri]$fixture).AbsoluteUri $token $Iterations $SampleSpacing
if ($LASTEXITCODE -ne 0) { throw "Chromium diagnostic FAIL or incomplete: $run" }
Write-Output "Static Chromium and layered evidence collected: $run. Dynamic scenarios and GPU acceleration verification remain separate."
