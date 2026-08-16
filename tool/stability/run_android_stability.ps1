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
$reportRoot = Join-Path $root 'build\stability'
New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null

$qemu = (& $adb -s $Serial shell getprop ro.kernel.qemu).Trim()
if ($qemu -ne '1' -or -not $Serial.StartsWith('emulator-')) {
    throw "Refusing Android stability automation on non-emulator target: $Serial"
}

$api = (& $adb -s $Serial shell getprop ro.build.version.sdk).Trim()
$model = (& $adb -s $Serial shell getprop ro.product.model).Trim()
@{
    serial = $Serial
    api = $api
    model = $model
    startedAt = (Get-Date).ToString('o')
} | ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $reportRoot 'device.json')

& $flutter test integration_test\app_lifecycle_test.dart -d $Serial
if ($LASTEXITCODE -ne 0) { throw 'Lifecycle integration test failed.' }

& $adb -s $Serial shell am force-stop com.lifehub.app.lifehub
& $adb -s $Serial shell monkey -p com.lifehub.app.lifehub 1 | Out-Null
Start-Sleep -Seconds 3

& $adb -s $Serial shell dumpsys package com.lifehub.app.lifehub |
    Set-Content -Encoding utf8 (Join-Path $reportRoot 'package.txt')
& $adb -s $Serial shell dumpsys appwidget |
    Set-Content -Encoding utf8 (Join-Path $reportRoot 'appwidget.txt')
& $adb -s $Serial shell dumpsys notification |
    Set-Content -Encoding utf8 (Join-Path $reportRoot 'notification.txt')

Write-Output "Android stability report: $reportRoot"
