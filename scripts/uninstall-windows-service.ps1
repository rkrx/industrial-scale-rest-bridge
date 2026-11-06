#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string] $ServiceName = "IndustrialScaleRestBridge",

    [string] $ExpectedExecutablePath,

    [switch] $StopOnly
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

if (-not [string]::IsNullOrWhiteSpace($ExpectedExecutablePath)) {
    $expectedImagePath = '"{0}"' -f [IO.Path]::GetFullPath($ExpectedExecutablePath)
    $imagePath = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName" -Name ImagePath).ImagePath
    if ($imagePath -ine $expectedImagePath) {
        throw "Service '$ServiceName' points to a different executable. Refusing to modify it."
    }
}

if ($StopOnly) { Write-Host "PreviousServiceStatus=$serviceStatus" }

if ($serviceStatus -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
    Stop-Service -Name $ServiceName
    Wait-ServiceStatus -Name $ServiceName -Status Stopped
}

if ($StopOnly) {
    Write-Host "Service '$ServiceName' is stopped."
    return
}

& sc.exe delete $ServiceName | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Could not remove service '$ServiceName'."
}

# DeleteService can only mark a service for deletion while a handle is open.
# Do not let an installer remove its files until SCM confirms actual removal.
$deadline = [DateTime]::UtcNow.AddSeconds(30)
do {
    & sc.exe query $ServiceName | Out-Null
    if ($LASTEXITCODE -eq 1060) {
        Write-Host "Service '$ServiceName' was removed successfully."
        return
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Could not verify removal of service '$ServiceName' (sc.exe exit $LASTEXITCODE)."
    }
    Start-Sleep -Milliseconds 250
} while ([DateTime]::UtcNow -lt $deadline)
throw "Service '$ServiceName' is still marked for deletion. Close service management tools and retry uninstall."
