#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $InstallerPath,
    [switch] $AllowServiceChanges
)

# Opt-in integration test for a disposable Windows test machine, never production.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $AllowServiceChanges) { throw 'Use -AllowServiceChanges on a disposable Windows test machine.' }
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required.' }
$installer = (Resolve-Path -LiteralPath $InstallerPath).ProviderPath
$serviceName = 'IndustrialScaleRestBridge'
if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) { throw 'Refusing to touch an existing service.' }
$root = Join-Path ([IO.Path]::GetTempPath()) ('scale-installer-test-' + [guid]::NewGuid())
$installDirectory = Join-Path $env:ProgramFiles ('Scale Installer Test ' + [guid]::NewGuid())
[IO.Directory]::CreateDirectory($root) | Out-Null
$source = Join-Path $root 'Vorlage ä.ini'
$sourceText = "[service]`r`nlisten=http://127.0.0.1:18543`r`ntest-mode=true`r`ntest-mode-response=123.45`r`n[scale]`r`ncom-port=COM1`r`ntrigger-code-byte-hex=00`r`nscale-response-start-index=0`r`nscale-response-part-length=6`r`n"
[IO.File]::WriteAllText($source, $sourceText, (New-Object Text.UTF8Encoding($true)))
$sourceHash = (Get-FileHash -LiteralPath $source).Hash

function Assert([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Run-Setup([string] $ExtraArguments) {
    $arguments = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR="{0}" /LOG="{1}" {2}' -f $installDirectory, (Join-Path $root 'setup.log'), $ExtraArguments
    $process = Start-Process -FilePath $installer -ArgumentList $arguments -Wait -PassThru
    Assert ($process.ExitCode -eq 0) "Setup failed: exit $($process.ExitCode). See $root"
}

try {
    # Invalid input must not install a service or files.
    $invalidArgs = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR="{0}" /CONFIG="{1}"' -f $installDirectory, (Join-Path $root 'missing.ini')
    $invalid = Start-Process -FilePath $installer -ArgumentList $invalidArgs -Wait -PassThru
    Assert ($invalid.ExitCode -ne 0) 'Missing configuration was accepted.'
    Assert (-not (Test-Path -LiteralPath $installDirectory)) 'Invalid setup copied program files.'
    Assert ($null -eq (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)) 'Invalid setup created a service.'

    # A readable INI can still make the application fail during service startup.
    # Setup must return failure, even though its program files have been copied.
    $badSource = Join-Path $root 'cannot-start.ini'
    [IO.File]::WriteAllText($badSource, $sourceText.Replace("trigger-code-byte-hex=00`r`n", ''), (New-Object Text.UTF8Encoding($true)))
    $badArgs = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR="{0}" /CONFIG="{1}" /LOG="{2}"' -f $installDirectory, $badSource, (Join-Path $root 'failed-service.log')
    $badSetup = Start-Process -FilePath $installer -ArgumentList $badArgs -Wait -PassThru
    Assert ($badSetup.ExitCode -ne 0) 'Service startup failure was reported as successful installation.'
    Assert ($null -eq (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)) 'Failed first installation left a service behind.'
    Assert ((Get-FileHash -LiteralPath $source).Hash -eq $sourceHash) 'Source changed during failed setup.'
    $failedUninstaller = Join-Path $installDirectory 'unins000.exe'
    if (Test-Path -LiteralPath $failedUninstaller) {
        $cleanup = Start-Process -FilePath $failedUninstaller -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -Wait -PassThru
        Assert ($cleanup.ExitCode -eq 0) 'Could not remove files from failed service installation.'
    }

    Run-Setup ('/CONFIG="{0}" /COMPORT=COM17' -f $source)
    Assert ((Get-Service -Name $serviceName).Status -eq 'Running') 'Service did not start.'
    $service = Get-CimInstance Win32_Service -Filter "Name='$serviceName'"
    Assert ($service.StartMode -eq 'Auto') 'Service startup is not automatic.'
    Assert ($service.PathName -eq ('"{0}\scale.exe"' -f $installDirectory)) 'Unexpected service executable.'
    $settings = Join-Path $installDirectory 'settings.ini'
    Assert (([IO.File]::ReadAllText($settings)) -match 'com-port=COM17') 'COM override was not written.'
    Assert ((Get-FileHash -LiteralPath $source).Hash -eq $sourceHash) 'Network/source template was changed.'
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    do {
        try { $reply = Invoke-RestMethod 'http://127.0.0.1:18543/current-weight/kg'; break } catch {
            if ([DateTime]::UtcNow -ge $deadline) { throw }
            Start-Sleep -Milliseconds 250
        }
    } while ($true)
    Assert ($reply.success -and $reply.weight -eq 123.45) 'Installed service returned the wrong test response.'

    # A second installation defaults to the installed local INI, not the network source.
    $localHash = (Get-FileHash -LiteralPath $settings).Hash
    Run-Setup ''
    Assert ((Get-FileHash -LiteralPath $settings).Hash -eq $localHash) 'Upgrade changed local configuration.'
    Assert ((Get-Service -Name $serviceName).Status -eq 'Running') 'Upgrade did not restart service.'
    Assert ((Get-CimInstance Win32_Service -Filter "Name='$serviceName'").StartName -eq $service.StartName) 'Upgrade changed the service account.'

    $failedUpgrade = Start-Process -FilePath $installer -ArgumentList $badArgs -Wait -PassThru
    Assert ($failedUpgrade.ExitCode -ne 0) 'Failed service upgrade returned success.'
    Assert ((Get-FileHash -LiteralPath $settings).Hash -eq $localHash) 'Failed upgrade did not restore local INI.'
    Assert ((Get-Service -Name $serviceName).Status -eq 'Running') 'Failed upgrade did not restore the previous running service.'
    Assert ((Get-CimInstance Win32_Service -Filter "Name='$serviceName'").StartName -eq $service.StartName) 'Failed upgrade changed the account.'

    # A mismatched executable must not be stopped or removed.
    $guarded = $false
    try { & (Join-Path $installDirectory 'uninstall-windows-service.ps1') -ExpectedExecutablePath (Join-Path $root 'wrong.exe') } catch { $guarded = $true }
    Assert $guarded 'Service identity guard accepted an unrelated path.'
    Assert ((Get-Service -Name $serviceName).Status -eq 'Running') 'Identity guard affected the running service.'

    $uninstaller = Join-Path $installDirectory 'unins000.exe'
    $uninstall = Start-Process -FilePath $uninstaller -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -Wait -PassThru
    Assert ($uninstall.ExitCode -eq 0) 'Uninstaller failed.'
    Assert ($null -eq (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)) 'Service survived uninstall.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $installDirectory 'scale.exe'))) 'Executable survived uninstall.'
    Assert (-not (Test-Path -LiteralPath $settings)) 'Local configuration survived uninstall.'
    Assert ((Get-FileHash -LiteralPath $source).Hash -eq $sourceHash) 'Source was changed during uninstall.'
    Write-Host 'PASS Windows installation, REST, upgrade, identity guard and uninstall.'
} finally {
    # On failure retain evidence and installation for inspection; never force-remove it.
    Write-Host "Test artifacts: $root"
    Write-Host "Test installation: $installDirectory"
}
