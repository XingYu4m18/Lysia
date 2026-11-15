param(
  [string]$Flutter = "$env:USERPROFILE\.local\share\flutter\bin\flutter.bat",
  [switch]$PublicRelease
)
$ErrorActionPreference = 'Stop'
$sourceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
foreach ($requiredAsset in @('assets\afp\afp.js', 'assets\afp\afp.wasm.js')) {
  if ($PublicRelease) { continue }
  if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $requiredAsset))) {
    throw "Missing $requiredAsset. Read assets/afp/README.md before building."
  }
}
$stageRoot = Join-Path $env:SystemDrive 'tj-build\app'
if ($PublicRelease) { $stageRoot = Join-Path $env:SystemDrive 'lysia-public-build\app' }
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
# Flutter's Windows AOT toolchain currently mishandles non-ASCII source paths.
# Build from an ASCII-only staging copy while retaining the original sources.
$copyOptions = @('/E', '/XD', 'build', '.dart_tool', '.git', 'ephemeral', '.plugin_symlinks', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
if ($PublicRelease) { $copyOptions += @('/XF', 'afp.js', 'afp.wasm.js') }
& robocopy $sourceRoot $stageRoot @copyOptions | Out-Null
if ($LASTEXITCODE -gt 7) { throw 'Could not prepare build directory.' }
if ($PublicRelease) {
  foreach ($excludedAsset in @('assets\afp\afp.js', 'assets\afp\afp.wasm.js')) {
    if (Test-Path -LiteralPath (Join-Path $stageRoot $excludedAsset)) {
      throw 'Public build directory contains excluded AFP files. Use a clean staging directory.'
    }
  }
}
$env:Path = "$env:USERPROFILE\.local\bin;" + $env:Path
Push-Location $stageRoot
try {
  & $Flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
  & $Flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
} finally { Pop-Location }
$destination = Join-Path $sourceRoot '..\outputs\聆汐-Lysia-v0.2.0-Windows-x64'
if ($PublicRelease) { $destination = Join-Path $sourceRoot '..\outputs\Lysia-v0.2.0-Windows-x64-public' }
New-Item -ItemType Directory -Path $destination -Force | Out-Null
& robocopy (Join-Path $stageRoot 'build\windows\x64\runner\Release') $destination /E /XF tingjian.exe /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -gt 7) { throw 'Could not copy application bundle.' }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path -LiteralPath $vswhere) {
  $installation = & $vswhere -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  $redistVersion = Get-ChildItem -LiteralPath (Join-Path $installation 'VC\Redist\MSVC') -Directory |
    Where-Object { $_.Name -match '^\d' } | Sort-Object Name -Descending | Select-Object -First 1
  if ($redistVersion) {
    $runtime = Get-ChildItem -LiteralPath (Join-Path $redistVersion.FullName 'x64') -Directory |
      Where-Object { $_.Name -like 'Microsoft.VC*.CRT' } | Select-Object -First 1
    if ($runtime) { Get-ChildItem -LiteralPath $runtime.FullName -Filter '*.dll' | Copy-Item -Destination $destination -Force }
  }
}
Copy-Item -LiteralPath (Join-Path $sourceRoot 'THIRD_PARTY.md') -Destination $destination -Force
Copy-Item -LiteralPath (Join-Path $sourceRoot 'LICENSE') -Destination $destination -Force
Copy-Item -LiteralPath (Join-Path $sourceRoot 'licenses') -Destination $destination -Recurse -Force
Write-Output "Application: $destination\lysia.exe"
