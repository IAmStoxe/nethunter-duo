[CmdletBinding()]
param(
    [string] $AndroidSdk = "$env:LOCALAPPDATA\Android\Sdk",
    [string] $CacheRoot = "$env:LOCALAPPDATA\DuoTechnician\build-cache"
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$gradleVersion = '8.9'
$gradleSha256 = 'd725d707bfabd4dfdc958c624003b3c80accc03f7037b5122c4b1d0ef15cecab'
$archive = Join-Path $CacheRoot "gradle-$gradleVersion-bin.zip"
$gradleHome = Join-Path $CacheRoot "gradle-$gradleVersion"
$distributionUrl = "https://services.gradle.org/distributions/gradle-$gradleVersion-bin.zip"

function Assert-CacheChild {
    param([Parameter(Mandatory)][string] $Path)

    $cacheFull = [System.IO.Path]::GetFullPath($CacheRoot).TrimEnd('\', '/')
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    $prefix = $cacheFull + [System.IO.Path]::DirectorySeparatorChar
    if (-not $pathFull.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing a build-cache operation outside $cacheFull`: $pathFull"
    }
    return $pathFull
}

if (-not (Test-Path -LiteralPath (Join-Path $AndroidSdk 'platforms\android-34'))) {
    throw "Android SDK platform 34 was not found below $AndroidSdk"
}
$javaVersion = (& cmd.exe /d /c 'java -version 2>&1' | Select-Object -First 1) -join ''
if ($javaVersion -notmatch 'version "(17|18|19|2[0-9])') {
    throw "JDK 17 or newer is required; found $javaVersion"
}

New-Item -ItemType Directory -Force -Path $CacheRoot, (Join-Path $projectRoot 'dist') | Out-Null
if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
    $partial = "$archive.part"
    Invoke-WebRequest -Uri $distributionUrl -OutFile $partial
    Move-Item -LiteralPath $partial -Destination $archive -Force
}
$actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
if ($actual -ne $gradleSha256) {
    throw "Gradle archive SHA-256 mismatch: $actual"
}

$gradle = Join-Path $gradleHome 'bin\gradle.bat'
if (-not (Test-Path -LiteralPath $gradle -PathType Leaf)) {
    $extractRoot = Assert-CacheChild (Join-Path $CacheRoot ("extract-" + [guid]::NewGuid().ToString('N')))
    $verifiedGradleHome = Assert-CacheChild $gradleHome
    try {
        Expand-Archive -LiteralPath $archive -DestinationPath $extractRoot
        $extractedGradle = Assert-CacheChild (Join-Path $extractRoot "gradle-$gradleVersion")
        Move-Item -LiteralPath $extractedGradle -Destination $verifiedGradleHome
    } finally {
        if (Test-Path -LiteralPath $extractRoot) {
            Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

$env:ANDROID_SDK_ROOT = (Resolve-Path -LiteralPath $AndroidSdk).Path
& $gradle --no-daemon --project-dir $projectRoot :app:lintDebug :app:assembleDebug
if ($LASTEXITCODE -ne 0) { throw "Android build failed with exit code $LASTEXITCODE" }

$apk = Join-Path $projectRoot 'app\build\outputs\apk\debug\app-debug.apk'
$output = Join-Path $projectRoot 'dist\DuoTechnician-1.0.0-debug.apk'
Copy-Item -LiteralPath $apk -Destination $output -Force
Get-FileHash -Algorithm SHA256 -LiteralPath $output

