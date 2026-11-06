#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+(\.\d+)?$')]
    [string] $Version = '1.0.0',
    [string] $IsccPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Build the Windows installer on Windows with .NET SDK and Inno Setup 6.4 or later.'
}
foreach ($part in $Version.Split('.')) {
    if ([int]$part -gt 65535) { throw 'Version components must be between 0 and 65535.' }
}
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw 'The .NET SDK is required.' }
if ([string]::IsNullOrWhiteSpace($IsccPath)) {
    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) { $IsccPath = $command.Source }
    else {
        foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, $env:LOCALAPPDATA)) {
            if ([string]::IsNullOrWhiteSpace($base)) { continue }
            foreach ($relative in @('Inno Setup 7\ISCC.exe', 'Inno Setup 6\ISCC.exe', 'Programs\Inno Setup 7\ISCC.exe', 'Programs\Inno Setup 6\ISCC.exe')) {
                $candidate = Join-Path $base $relative
                if (Test-Path -LiteralPath $candidate -PathType Leaf) { $IsccPath = $candidate; break }
            }
            if (-not [string]::IsNullOrWhiteSpace($IsccPath)) { break }
        }
    }
}
if ([string]::IsNullOrWhiteSpace($IsccPath) -or -not (Test-Path -LiteralPath $IsccPath -PathType Leaf)) {
    throw 'Inno Setup compiler not found. Install Inno Setup 6.4+ or supply -IsccPath.'
}
$IsccPath = (Resolve-Path -LiteralPath $IsccPath).ProviderPath
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output = Join-Path $repository 'dist/installers'
$staging = Join-Path $repository ('dist/installer-publish-' + [guid]::NewGuid())
[IO.Directory]::CreateDirectory($staging) | Out-Null
try {
    # A fresh staging directory prevents obsolete files from earlier builds shipping.
    & dotnet publish (Join-Path $repository 'scale.csproj') -c Release -r win-x64 -o $staging --self-contained true '-p:PublishSingleFile=true' '-p:PublishReadyToRun=true' '-p:PublishTrimmed=false' '-p:IncludeNativeLibrariesForSelfExtract=true' "-p:Version=$Version"
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed (exit $LASTEXITCODE)." }
    & $IsccPath "/DAppVersion=$Version" "/DPublishDir=$staging" "/DInstallerOutputDir=$output" (Join-Path $repository 'installer/windows/industrial-scale-rest-bridge.iss')
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed (exit $LASTEXITCODE)." }
    Write-Host "Installer: $(Join-Path $output "IndustrialScaleRestBridge-$Version-win-x64-setup.exe")"
} finally {
    Remove-Item -LiteralPath $staging -Recurse -Force
}
