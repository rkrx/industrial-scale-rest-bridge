#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string] $ServiceName = "IndustrialScaleRestBridge"
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
    throw "The Windows service can only be removed on Windows."
}

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($null -eq $service) {
    Write-Host "Service '$ServiceName' is not installed."
    return
}

$serviceStatus = $service.Status
$service.Dispose()

if ($serviceStatus -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
    Stop-Service -Name $ServiceName -Force
    Wait-ServiceStatus -Name $ServiceName -Status Stopped
}

& sc.exe delete $ServiceName | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Could not remove service '$ServiceName'."
}

Write-Host "Service '$ServiceName' was removed successfully."
