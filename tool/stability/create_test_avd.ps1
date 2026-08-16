param(
    [string]$AvdName = 'LifeHub_V1_9_Stability_API35',
    [string]$AndroidSdk = $env:ANDROID_SDK_ROOT,
    [string]$JavaHome = $env:JAVA_HOME,
    [string]$AvdHome = $env:ANDROID_AVD_HOME
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($AndroidSdk)) {
    throw 'Set ANDROID_SDK_ROOT or pass -AndroidSdk.'
}
if ([string]::IsNullOrWhiteSpace($JavaHome)) {
    throw 'Set JAVA_HOME or pass -JavaHome.'
}
if ([string]::IsNullOrWhiteSpace($AvdHome)) {
    $AvdHome = Join-Path $env:USERPROFILE '.android\avd'
}
$image = 'system-images;android-35;google_apis;x86_64'

$env:JAVA_HOME = $JavaHome
$env:ANDROID_SDK_ROOT = $AndroidSdk
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_AVD_HOME = $AvdHome

New-Item -ItemType Directory -Force -Path $AvdHome | Out-Null
$sdkManager = Join-Path $AndroidSdk 'cmdline-tools\latest\bin\sdkmanager.bat'
$avdManager = Join-Path $AndroidSdk 'cmdline-tools\latest\bin\avdmanager.bat'
$emulator = Join-Path $AndroidSdk 'emulator\emulator.exe'

if (-not (Test-Path (Join-Path $AndroidSdk 'emulator\emulator.exe')) -or
    -not (Test-Path (Join-Path $AndroidSdk 'system-images\android-35\google_apis\x86_64\system.img'))) {
    1..100 | ForEach-Object { 'y' } | & $sdkManager 'emulator' $image
    if ($LASTEXITCODE -ne 0) { throw 'Android emulator package installation failed.' }
}

if (-not (Test-Path (Join-Path $AvdHome "$AvdName.avd\config.ini"))) {
    'no' | & $avdManager create avd --name $AvdName --package $image --device pixel_4 --force
    if ($LASTEXITCODE -ne 0) { throw 'AVD creation failed.' }
}

& $emulator -accel-check
if ($LASTEXITCODE -ne 0) {
    throw 'Android hardware acceleration is unavailable. Enable WHPX/Android Emulator Hypervisor Driver or connect a test phone.'
}

Write-Output "AVD ready: $AvdName"
