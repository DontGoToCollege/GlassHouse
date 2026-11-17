# Builds GlassHouse as a portable folder: GlassHouse\GlassHouse.exe plus its themes, languages and (after first run) settings.
# Usage:  .\build.ps1         -> updates GlassHouse\ in place (your settings are kept) + Versions\Archive\GlassHouse-<version>.zip
#         .\build.ps1 -Test   -> a trial build in .test\GlassHouse; nothing archived, GlassHouse\ untouched
# Raise <GhVersion> in source\Directory.Build.props first: a version that's already archived is refused.
param([switch]$Test)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$version = ([regex]'<GhVersion>(.+?)</GhVersion>').Match((Get-Content "$root\source\Directory.Build.props" -Raw)).Groups[1].Value
$archive = "$root\Versions\Archive\GlassHouse-$version.zip"
if (-not $Test -and (Test-Path $archive)) { throw "Version $version is already archived. Raise <GhVersion> in source\Directory.Build.props, then build again." }

# The .NET 11 SDK lives inside the project (.dotnet), so building changes nothing PC-wide.
$sdk = "11.0.100"
$dotnet = "$root\.dotnet\dotnet.exe"
if (-not (Test-Path "$root\.dotnet\sdk\$sdk")) {
    Write-Host "Getting the .NET $sdk SDK (one time, about 250 MB)..."
    New-Item -ItemType Directory -Force "$root\.tools" | Out-Null
    Invoke-WebRequest https://dot.net/v1/dotnet-install.ps1 -OutFile "$root\.tools\dotnet-install.ps1" -UseBasicParsing
    & "$root\.tools\dotnet-install.ps1" -Version $sdk -InstallDir "$root\.dotnet" -NoPath
}
# AOT (the fast-starting exe) needs Microsoft's C++ Build Tools; Get-ClaudeRules installs them.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not ((Test-Path $vswhere) -and (& $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath))) {
    throw "Microsoft's C++ Build Tools are missing. Run Get-ClaudeRules.cmd (it installs them), then build again."
}
$env:DOTNET_ROOT = "$root\.dotnet"; $env:DOTNET_MULTILEVEL_LOOKUP = "0"; $env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"; $env:DOTNET_NOLOGO = "1"

# Publish into a staging folder, then add the shared payload and the portable marker, as upstream's ZIP packer does.
$stage = if ($Test) { "$root\.test" } else { "$root\.build" }
$app = "$stage\GlassHouse"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
& $dotnet publish "$root\source\ImageGlass.Win32\ImageGlass.Win32.csproj" -c Release -p:Platform=x64 -o $app
if ($LASTEXITCODE -ne 0) { throw "Publish failed." }
Get-ChildItem $app -Filter *.pdb | Remove-Item -Force
Copy-Item "$root\source\__assets\__app\*" $app -Recurse -Force
New-Item -ItemType File "$app\.igportable" -Force | Out-Null

& "$root\tools\smoke.ps1" -App $app
if ($Test) { Write-Host "Test build $version ready in .test\GlassHouse (nothing archived)." -ForegroundColor Green; return }

# Archive the zip people download from the Release (it unzips to one GlassHouse folder).
Add-Type -AssemblyName System.IO.Compression.FileSystem
New-Item -ItemType Directory -Force (Split-Path $archive) | Out-Null
[IO.Compression.ZipFile]::CreateFromDirectory($app, $archive, [IO.Compression.CompressionLevel]::Optimal, $true)
Write-Host "Built GlassHouse $version, copy kept in Versions\Archive\GlassHouse-$version.zip" -ForegroundColor Green

# Swap it into GlassHouse\ at the project root. Files are copied over, never purged, so settings and caches stay.
$live = "$root\GlassHouse"
$running = @(Get-Process GlassHouse -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$live\*" })
foreach ($p in $running) { $p.CloseMainWindow() | Out-Null }  # a normal close lets it save its settings
foreach ($p in $running) { if (-not $p.WaitForExit(10000)) { Stop-Process -Id $p.Id -Force } }
robocopy $app $live /E /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Couldn't copy the new build into GlassHouse\ (robocopy code $LASTEXITCODE)." }
Write-Host "GlassHouse\ is now $version." -ForegroundColor Green
if ($running) {
    # Started through Windows (not as this script's child) so it keeps running after the build.
    Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = "`"$live\GlassHouse.exe`""; CurrentDirectory = $live } | Out-Null
    Write-Host "Started the new GlassHouse again."
}
$global:LASTEXITCODE = 0
