$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
& flutter build apk --release --target=lib/sandbox.dart --dart-define=LANGKAH_SANDBOX=true
if ($LASTEXITCODE -ne 0) { throw 'Sandbox build failed.' }
New-Item -ItemType Directory -Path 'output' -Force | Out-Null
Copy-Item -LiteralPath 'build\app\outputs\flutter-apk\app-release.apk' -Destination 'output\Langkah-Sandbox-android.apk'
Write-Output 'Sandbox APK: output\Langkah-Sandbox-android.apk. This does not replace Langkah-android.apk.'
