# One-time machine setup for the Wargaming Rules Compendium Android build.
# Run from the project root in PowerShell:  .\setup-android.ps1
$ErrorActionPreference = 'Stop'

# 1) Flutter must use a Java <=24 JDK (system Java 25 breaks Gradle 8.13).
$jbrCandidates = @(
    'D:\Coding\Android studio\jbr',
    'D:\Coding\Android Studio\jbr',
    'D:\Coding\Visual Studio\Android\jbr'
)
$jbr = $jbrCandidates | Where-Object { Test-Path (Join-Path $_ 'bin\java.exe') } | Select-Object -First 1
if (-not $jbr) {
    Write-Host "Could not auto-locate Android Studio's bundled JDK (jbr\bin\java.exe)." -ForegroundColor Yellow
    Write-Host "Looked in: $($jbrCandidates -join ', ')"
    Write-Host "Find it yourself, then run:  flutter config --jdk-dir=<path-to-jbr>"
} else {
    Write-Host "Found bundled JDK: $jbr"
    flutter config --jdk-dir=$jbr
}

# 2) Keep caches off the small C: drive.
New-Item -ItemType Directory -Force 'D:\Coding\DevCache\gradle' | Out-Null
New-Item -ItemType Directory -Force 'D:\Coding\DevCache\flutterPubCache' | Out-Null
[Environment]::SetEnvironmentVariable('GRADLE_USER_HOME','D:\Coding\DevCache\gradle','User')
[Environment]::SetEnvironmentVariable('PUB_CACHE','D:\Coding\DevCache\flutterPubCache','User')
$env:GRADLE_USER_HOME='D:\Coding\DevCache\gradle'
$env:PUB_CACHE='D:\Coding\DevCache\flutterPubCache'

# 3) Refresh dependencies.
flutter clean
flutter pub get

Write-Host "`nDone. Now run:  flutter run" -ForegroundColor Green
