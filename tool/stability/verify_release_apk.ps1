param(
  [string]$ApkPath = "build/app/outputs/flutter-apk/app-release.apk",
  [string]$AndroidSdk = $env:ANDROID_SDK_ROOT,
  [string]$JavaHome = $env:JAVA_HOME,
  [string]$ExpectedPackage = "com.lifehub.app.lifehub",
  [string]$ExpectedVersionName = "1.9.6",
  [int]$ExpectedVersionCode = 13
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($AndroidSdk)) {
  throw "Set ANDROID_SDK_ROOT or pass -AndroidSdk."
}
if ([string]::IsNullOrWhiteSpace($JavaHome)) {
  throw "Set JAVA_HOME or pass -JavaHome."
}
$resolvedApk = (Resolve-Path -LiteralPath $ApkPath).Path
$env:JAVA_HOME = $JavaHome
$buildTools = Get-ChildItem (Join-Path $AndroidSdk "build-tools") -Directory |
  Sort-Object Name -Descending |
  Select-Object -First 1 -ExpandProperty FullName
$analyzer = Join-Path $AndroidSdk "cmdline-tools/latest/bin/apkanalyzer.bat"

$badging = & (Join-Path $buildTools "aapt.exe") dump badging $resolvedApk
if ($LASTEXITCODE -ne 0) { throw "aapt could not read the APK." }
$packageLine = $badging | Select-String -Pattern "^package:"
if ($packageLine -notmatch "name='$([regex]::Escape($ExpectedPackage))'") {
  throw "Unexpected package id: $packageLine"
}
if ($packageLine -notmatch "versionName='$([regex]::Escape($ExpectedVersionName))'") {
  throw "Unexpected version name: $packageLine"
}
if ($packageLine -notmatch "versionCode='$ExpectedVersionCode'") {
  throw "Unexpected version code: $packageLine"
}

$dexPackages = & $analyzer dex packages $resolvedApk
if ($LASTEXITCODE -ne 0) { throw "apkanalyzer could not inspect the APK." }
if (-not ($dexPackages | Select-String -SimpleMatch "io.flutter.plugins.GeneratedPluginRegistrant")) {
  throw "Release APK is missing GeneratedPluginRegistrant; Flutter plugins will not initialize."
}
if ($dexPackages | Select-String -SimpleMatch "IntegrationTestPlugin") {
  throw "Release APK unexpectedly contains the integration-test plugin."
}

& (Join-Path $buildTools "apksigner.bat") verify --verbose $resolvedApk
if ($LASTEXITCODE -ne 0) { throw "APK signature verification failed." }

Write-Output "Release APK verification passed: $resolvedApk"
