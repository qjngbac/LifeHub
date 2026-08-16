param(
    [Parameter(Mandatory = $true)]
    [string]$Serial,
    [string]$FlutterCommand = 'flutter',
    [string]$AdbCommand = 'adb'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$flutter = (Get-Command $FlutterCommand -ErrorAction Stop).Source
$adb = (Get-Command $AdbCommand -ErrorAction Stop).Source
$package = 'com.lifehub.app.lifehub'
$deviceBackup = 'files/lifehub_stability_backup.lhbk'
$temporaryDeviceBackup = '/data/local/tmp/lifehub_stability_backup.lhbk'
$reportRoot = Join-Path $root 'build\stability'
$hostBackup = Join-Path $reportRoot 'lifehub_stability_backup.lhbk'
New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null

$qemu = (& $adb -s $Serial shell getprop ro.kernel.qemu).Trim()
if ($qemu -ne '1' -or -not $Serial.StartsWith('emulator-')) {
    throw "Refusing destructive backup drill on non-emulator target: $Serial"
}

& $flutter test integration_test\backup_drill_driver.dart -d $Serial --dart-define=DRILL_PHASE=export
if ($LASTEXITCODE -ne 0) { throw 'Backup export phase failed.' }

$quotedHost = '"' + $hostBackup + '"'
$pullCommand = '"' + $adb + '" -s ' + $Serial + ' exec-out run-as ' + $package + ' cat ' + $deviceBackup + ' > ' + $quotedHost
cmd.exe /d /c $pullCommand
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $hostBackup)) { throw 'Could not preserve the exported backup on the host.' }

& $adb -s $Serial shell pm clear $package
if ($LASTEXITCODE -ne 0) { throw 'Emulator app-data clear failed.' }

& $adb -s $Serial push $hostBackup $temporaryDeviceBackup | Out-Null
& $adb -s $Serial shell chmod 644 $temporaryDeviceBackup
& $adb -s $Serial shell run-as $package mkdir -p files
& $adb -s $Serial shell run-as $package cp $temporaryDeviceBackup $deviceBackup
if ($LASTEXITCODE -ne 0) { throw 'Could not stage the backup after clearing emulator data.' }

& $flutter test integration_test\backup_drill_driver.dart -d $Serial --dart-define=DRILL_PHASE=import
if ($LASTEXITCODE -ne 0) { throw 'Backup import phase failed.' }

& $adb -s $Serial shell am force-stop $package
& $flutter test integration_test\backup_drill_driver.dart -d $Serial --dart-define=DRILL_PHASE=import
if ($LASTEXITCODE -ne 0) { throw 'Post-restore cold-start verification failed.' }

@{
    serial = $Serial
    completedAt = (Get-Date).ToString('o')
    backupBytes = (Get-Item $hostBackup).Length
    result = 'passed'
} | ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $reportRoot 'backup-drill.json')

Write-Output "Backup restore drill passed. Evidence: $reportRoot"
