#Requires -Version 6.2
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string] $ExecutablePath,

    [ValidateNotNullOrEmpty()]
    [string] $ServiceName = "IndustrialScaleRestBridge",

    [ValidateNotNullOrEmpty()]
    [string] $DisplayName = "Industrial Scale REST Bridge",

    [ValidateNotNullOrEmpty()]
    [string] $Description = "Exposes an industrial scale through a local REST endpoint.",

    [PSCredential] $Credential,

    [switch] $DoNotStart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $IsWindows) {
    throw "The Windows service can only be installed on Windows."
}

if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
    $ExecutablePath = Join-Path $PSScriptRoot "scale.exe"
}

if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) {
    throw "Missing published executable: $ExecutablePath"
}

$resolvedExecutablePath = (Resolve-Path -LiteralPath $ExecutablePath).Path
if ([System.IO.Path]::GetExtension($resolvedExecutablePath) -ne ".exe") {
    throw "ExecutablePath must point to the published scale.exe file."
}

$installationDirectory = Split-Path -Parent $resolvedExecutablePath
$settingsPath = Join-Path $installationDirectory "settings.ini"
if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
    throw "Missing configuration file: $settingsPath"
}

if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
    throw "A service named '$ServiceName' is already installed."
}

$newServiceArguments = @{
    Name = $ServiceName
    BinaryPathName = '"{0}"' -f $resolvedExecutablePath
    DisplayName = $DisplayName
    Description = $Description
    StartupType = "Automatic"
}

if ($null -ne $Credential) {
    $newServiceArguments["Credential"] = $Credential
}

$serviceCreated = $false

try {
    $service = New-Service @newServiceArguments
    $serviceCreated = $true

    & sc.exe failure $ServiceName "reset=" "86400" "actions=" "restart/60000/restart/60000/restart/60000" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not configure the recovery actions for service '$ServiceName'."
    }

    if (-not $DoNotStart) {
        Start-Service -Name $ServiceName
        $service.WaitForStatus(
            [System.ServiceProcess.ServiceControllerStatus]::Running,
            [TimeSpan]::FromSeconds(30)
        )
    }
}
catch {
    if ($serviceCreated) {
        try {
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
            & sc.exe delete $ServiceName | Out-Null
        }
        catch {
            Write-Warning "The incomplete service installation could not be rolled back automatically."
        }
    }

    throw
}

if ($DoNotStart) {
    Write-Host "Service '$ServiceName' was installed and is currently stopped."
}
else {
    Write-Host "Service '$ServiceName' was installed and started successfully."
}
