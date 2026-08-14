param(
    [string]$ArchivePath = "",
    [switch]$ForceDownload
)

$ErrorActionPreference = "Stop"
$version = "20260526"
$expectedSha256 = "85b18b875488585c2d21360430e0e54abb6c04aa88094b471c20208ab55ff796"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$cacheDirectory = Join-Path $repositoryRoot ".tooling-cache"
$downloadPath = if ($ArchivePath) {
    [System.IO.Path]::GetFullPath($ArchivePath)
} else {
    Join-Path $cacheDirectory "ncnn-$version-android.zip"
}
$destination = Join-Path $repositoryRoot "android/app/src/main/cpp/third_party/ncnn"
$downloadUrl = "https://github.com/Tencent/ncnn/releases/download/$version/ncnn-$version-android.zip"

New-Item -ItemType Directory -Path (Split-Path -Parent $downloadPath) -Force | Out-Null
if ($ForceDownload -and (Test-Path -LiteralPath $downloadPath)) {
    Remove-Item -LiteralPath $downloadPath -Force
}
if (-not (Test-Path -LiteralPath $downloadPath)) {
    Write-Host "Downloading ncnn $version Android SDK..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath
}

$actualSha256 = (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSha256 -ne $expectedSha256) {
    throw "ncnn archive SHA-256 mismatch. Expected $expectedSha256, got $actualSha256. Delete the archive or use -ForceDownload."
}

$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("pdr-ncnn-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
try {
    Expand-Archive -LiteralPath $downloadPath -DestinationPath $temporaryDirectory
    $packageRoot = Get-ChildItem -LiteralPath $temporaryDirectory -Directory |
        Where-Object { $_.Name -eq "ncnn-$version-android" } |
        Select-Object -First 1
    if (-not $packageRoot) {
        throw "The archive does not contain the expected ncnn-$version-android directory."
    }

    $abis = @("arm64-v8a", "armeabi-v7a", "x86", "x86_64")
    foreach ($abi in $abis) {
        $source = Join-Path $packageRoot.FullName $abi
        $cmakeConfig = Join-Path $source "lib/cmake/ncnn/ncnnConfig.cmake"
        if (-not (Test-Path -LiteralPath $cmakeConfig)) {
            throw "The ncnn package is missing $abi/lib/cmake/ncnn/ncnnConfig.cmake."
        }
    }

    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    foreach ($abi in $abis) {
        Copy-Item -LiteralPath (Join-Path $packageRoot.FullName $abi) -Destination $destination -Recurse
    }
} finally {
    if (Test-Path -LiteralPath $temporaryDirectory) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
}

Write-Host "Installed ncnn $version for Android into $destination"
