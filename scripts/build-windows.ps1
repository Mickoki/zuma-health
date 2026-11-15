param([string]$Godot = 'godot')
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (-not (Get-Command $Godot -ErrorAction SilentlyContinue)) {
    throw 'Supply -Godot with the editor executable path.'
}
$stage = Join-Path ([IO.Path]::GetTempPath()) ('zuma-build-' + [guid]::NewGuid().ToString('N'))
$package = Join-Path $stage 'windows'
$dist = Join-Path $repo 'dist'
$output = Join-Path $dist 'windows'
$oldCgo = $env:CGO_ENABLED
try {
    New-Item -ItemType Directory -Path $package, $output -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dist '.gdignore') -Value ''
    $env:CGO_ENABLED = '0'
    Push-Location (Join-Path $repo 'server')
    try {
        & go build -trimpath -o (Join-Path $package 'zuma-server.exe') ./cmd/zuma
        if ($LASTEXITCODE -ne 0) { throw 'Go build failed.' }
    } finally { Pop-Location }
    & $Godot --headless --editor --path $repo --import 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
    & $Godot --headless --path $repo --export-release 'Windows Desktop' (Join-Path $package 'Zuma.exe') 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Godot export failed.' }
    Copy-Item -LiteralPath (Join-Path $repo 'LICENSE') -Destination $package
    Copy-Item -LiteralPath (Join-Path $repo 'third_party') -Destination $package -Recurse
    @'
Zuma for Windows

Start zuma-server.exe, then Zuma.exe. Close an older server before starting
another on the same port. The API is http://127.0.0.1:8080, not a website.
Create a profile, save the survey, then choose a game.

Run the server from this folder to keep its default database here.
See source server/README.md for ZUMA_DB and other configuration options.
Back up existing data before upgrading. Never overwrite a running server.
This ZIP contains fresh build files and no user database.

Ollama and Qwen3 8B are optional and installed separately.
R restarts a game; Esc returns; 1-4 select Speed Math answers.
Losing focus interrupts an attempt. This unsigned experimental prototype
is not a medical device. License notices are in third_party/.
'@ | Set-Content -LiteralPath (Join-Path $package 'README.txt') -Encoding utf8
    # Package fresh staging files only; existing output may contain user data.
    Compress-Archive -LiteralPath $package -DestinationPath (Join-Path $stage 'Zuma-Windows.zip')
    foreach ($file in Get-ChildItem -LiteralPath $package) {
        Copy-Item -LiteralPath $file.FullName -Destination $output -Recurse -Force
    }
    Copy-Item -LiteralPath (Join-Path $stage 'Zuma-Windows.zip') -Destination $dist -Force
    Get-Item -LiteralPath (Join-Path $output 'Zuma.exe'), (Join-Path $dist 'Zuma-Windows.zip')
} finally {
    $env:CGO_ENABLED = $oldCgo
    $fullStage = [IO.Path]::GetFullPath($stage)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ((Split-Path $fullStage -Parent) -eq $tempRoot -and (Split-Path $fullStage -Leaf) -like 'zuma-build-*') {
        if (Test-Path -LiteralPath $fullStage) { Remove-Item -LiteralPath $fullStage -Recurse -Force }
    } else { throw 'Refusing cleanup outside the temporary build directory.' }
}
