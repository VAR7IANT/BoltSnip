param([string]$Executable)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
$assembly=[Reflection.Assembly]::LoadFile((Resolve-Path $Executable).Path)
$flags=[Reflection.BindingFlags]'NonPublic,Static'
$license=$assembly.GetType('BoltSnip.LicenseManager',$true)
$enabled=$license.GetProperty('Enabled',$flags).GetValue($null,$null)
if (-not $enabled) { throw 'FAIL: delivered executable has licensing disabled and hides authorization management' }
$generated=$assembly.GetType('BoltSnip.LicensingValues',$true)
if ($generated.GetField('ServerUrl',$flags).GetRawConstantValue() -ne 'https://bs.oioio.cyou') { throw 'Wrong activation service' }
if ([string]::IsNullOrWhiteSpace($generated.GetField('OwnerPublicKeyXml',$flags).GetRawConstantValue())) { throw 'Missing owner public key' }
$popup=$assembly.GetType('BoltSnip.TrayPopupForm',$true)
$action=$assembly.GetType('BoltSnip.TrayPopupAction',$true)
$bounds=$popup.GetMethod('GetLogicalBounds',$flags)
$licenseBounds=$bounds.Invoke($null,[object[]]@([Enum]::Parse($action,'License'),[bool]$enabled))
$replayBounds=$bounds.Invoke($null,[object[]]@([Enum]::Parse($action,'AutoStartReplay'),[bool]$enabled))
if ($licenseBounds.IsEmpty -or $licenseBounds.Top -le $replayBounds.Bottom) { throw 'Authorization row missing or overlapping' }
'PASS: licensing enabled, original service and public key present, authorization and auto-replay rows both available'