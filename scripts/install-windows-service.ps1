#Requires -Version 5.1
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

    [switch] $DoNotStart,

    [switch] $UpdateExisting
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Wait-ServiceStatus {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [System.ServiceProcess.ServiceControllerStatus] $Status,

        [int] $TimeoutSeconds = 30
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

    do {
        $currentService = Get-Service -Name $Name -ErrorAction Stop
        try {
            if ($currentService.Status -eq $Status) {
                return
            }
        }
        finally {
            $currentService.Dispose()
        }

        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "Service '$Name' did not reach status '$Status' within $TimeoutSeconds seconds."
}

if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
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

$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($null -ne $existingService) {
    $existingService.Dispose()
    if (-not $UpdateExisting) {
        throw "A service named '$ServiceName' is already installed."
    }
    if ($null -ne $Credential) {
        throw 'Updating an existing service preserves its account; do not specify Credential.'
    }
    $imagePath = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName" -Name ImagePath).ImagePath
    if ($imagePath -ine ('"{0}"' -f $resolvedExecutablePath)) {
        throw "Service '$ServiceName' points to a different executable. Refusing to modify it."
    }
    Stop-Service -Name $ServiceName
    Wait-ServiceStatus -Name $ServiceName -Status Stopped
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
    if ($null -eq $existingService) {
        New-Service @newServiceArguments | Out-Null
        $serviceCreated = $true
    }
    else {
        # Keep the existing logon account and its credentials during upgrades.
        Set-Service -Name $ServiceName -StartupType Automatic
    }

    & sc.exe failure $ServiceName "reset=" "86400" "actions=" "restart/60000/restart/60000/restart/60000" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not configure the recovery actions for service '$ServiceName'."
    }

    if (-not $DoNotStart) {
        Start-Service -Name $ServiceName
        Wait-ServiceStatus -Name $ServiceName -Status Running
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
