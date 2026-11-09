# An ASP.NET server for exposing a scale via REST

![Scale](assets/scale.jpg)

## Configuration

Create a `settings.ini`-file in the root-directory.

```ini
[service]
; The IP-Adress+Port to listen to. Use `http://0.0.0.0:5000` if you want to listen non-private on all interfaces.
listen = http://127.0.0.1:5000

; Start the server in test-mode, so it always responds with 123.45 kg.
test-mode = true

; The response of the scale when test-mode is enabled.
test-mode-response = "<000001.01.0000:02   11    2.32    0.00    2.32kg     1   28244>\r\n"

[logging]
; Optional: Log all web requests and responses to the console if set to any value other than "false" or "off".
; console = true

; Optional: Log all web requests and responses to the specified file path.
; file = requests.log

[scale]
; The COM-Port of the scale. For Linux/MacOS it's something like /dev/ttyUSB0, for Windows it's like COM1.
; To find all available COM-ports of the local system, run the program with the `--list-comports` argument.
; Example: `dotnet run --list-comports`
com-port = /dev/ttyUSB0

; The BAUD-Rate.
baud-rate = 9600

; The Data-Bits.
data-bits = 8

; The Partiy mode.
parity = None

; Sets a value indicating whether the Data Terminal Ready (DTR) signal is enabled..
dtr-enable = true

; Sets a value indicating whether the Request to Send (RTS) signal is enabled.
rts-enable = true

; Sets the handshaking protocol for serial port transmission of data.
; - None (No control for the transmission is used)
; - XOnXOff (Software control for transmission is used, the XON character is sent to resume transmission and the XOFF
;    character to halt transmission)
; - RequestToSend (The serial port transmission uses the Request-to-Send (RTS) hardware control line)
; - RequestToSendXOnXOff (Both XOnXOff and RequestToSend controls are used)
handshake = XOnXOff

; The code to be send to the scale that triggers the weight response.
trigger-code-byte-hex = 3C524E3E0D0A

; The scale normally responds with a string, that contains the weight in either gram or kilogram. This index value
; marks the point, where the weight starts within the string.
scale-response-start-index = 39

; Omitting this value means "all remaining characters from the start index".
scale-response-part-length = 8

; The scale normally responds with a string, that contains the weight than could have a thousands separator. This value
; indicates the thousands separator, which is then removed from the string.
scale-response-thousands-separator = ,

; The scale normally responds with a string, that contains the weight than could have a decimal separator other than
; a dot. This value is used to replace the decimal separator, that comes from the scale, with a dot.
scale-response-decimal-separator = .

; Can be kilogram, gram, carat, oz, lg or lbs. Default is kilogram.
scale-response-unit = kilogram

; The character that marks the end of the scale response (eot = end of transmission).
scale-response-eot = "\n"
```

## Project setup

You have to install the .NET 9.0 SDK to build and run the server. You can download it from the [official website](https://dotnet.microsoft.com/download).

### Restore dependencies

```bash
dotnet restore
```

### Run server

```bash
dotnet run
```

### Publish a standalone Windows executable

```bash
dotnet publish -c Release -r win-x64 -o dist/windows --self-contained true -p:PublishReadyToRun=true -p:PublishSingleFile=true -p:PublishTrimmed=false -p:IncludeNativeLibrariesForSelfExtract=true
```

Trimming is deliberately disabled because not all dependencies used by this project guarantee trimming compatibility. The publish output includes the Windows service installation scripts. Copy your `settings.ini` into `dist/windows` next to `scale.exe` before starting or installing the application.

## Graphical Windows installer

The [Inno Setup installer](installer/windows/industrial-scale-rest-bridge.iss)
packages the standalone Windows application, configuration import and native
service registration in one offline setup EXE. The wizard is in German and
requires administrator rights. Target: Windows 10 or later, x64-compatible.
The target machine does not need a separately installed .NET runtime.

### Build the installer on Windows

Install a .NET SDK capable of targeting .NET 9 and
[Inno Setup 6.4 or later](https://jrsoftware.org/isdl.php), then run in PowerShell:

```powershell
.\scripts\build-installer.ps1 -Version 1.0.0
```

The script publishes into a fresh temporary directory, compiles the installer
and removes its staging files. The result is:

```text
dist\installers\IndustrialScaleRestBridge-1.0.0-win-x64-setup.exe
```

If the compiler is in a custom location, supply
`-IsccPath 'C:\Tools\Inno Setup 6\ISCC.exe'`. No tools are downloaded or installed
by the build script. The generated setup is unsigned; signing can be added to
the release process separately. Inno Setup requests commercial users to buy
a license, but its [FAQ](https://jrsoftware.org/isorder.php#required) states
that purchase is not mandatory.

### Build with GitHub Actions

The [Build Windows installer workflow](.github/workflows/windows-installer.yml)
builds and tests the setup on a disposable GitHub-hosted `windows-2022` VM.
It uses the existing build script and Inno Setup already installed on that
runner, without a self-hosted runner or a separate installer action.

Every push to `main` starts the workflow. Its version is automatically
`1.0.<github.run_number>`, for example `1.0.42`. The same version is used for the
application, installer filename, Actions artifact and release tag `v1.0.42`.
Failed runs can leave gaps in these numbers. Re-running a job retains its number.

After a successful build and tests, open the repository's **Releases** page to
download `IndustrialScaleRestBridge-1.0.42-win-x64-setup.exe` directly from its
release. The release/tag targets the exact commit built by that run. Release
downloads do not use the Actions artifact retention period.

You can also use **Actions → Build Windows installer → Run workflow** and select
a branch/tag. Manual runs receive an automatic version too. Only runs on `main`
publish releases; other refs produce tested Actions artifacts without publishing.
The run's **Artifacts** section still offers the ZIP named
`IndustrialScaleRestBridge-1.0.42-win-x64`, containing the setup EXE.

Before publishing the installer artifact, the job runs configuration tests on
Windows PowerShell 5.1 and exercises installation, native service startup,
REST test mode, successful/failed updates and uninstall. A failing test blocks
the installer upload. Integration logs are uploaded even if a later step fails.
Installer artifacts are retained for 14 days; test logs for 7 days.

Build/tests retain read-only repository permissions. A separate release job
downloads the tested artifact from that run with `actions: read` and publishes
using `contents: write` and GitHub's automatically supplied `GITHUB_TOKEN`.
No personal access token, custom secret or additional server is needed under
standard repository policy. The publisher first creates the tag at the built
commit and fails if that tag already exists. Existing tags/releases/assets are
never overwritten. Re-running a published run, or one whose tag was created
before a publication failure, fails instead of replacing that version. Fixing a
failed build and pushing again creates a new run/version.

The EXE remains unsigned. Service tests use synthetic local configuration and
test mode, so network-share access, the graphical wizard and real scale hardware
still need manual acceptance. Adding the workflow locally does not execute it;
its first successful Actions run is the evidence for native build/release acceptance.

### Install and configure

1. Run the generated setup EXE and choose the installation directory, by default
   `C:\Program Files\IndustrialScaleRestBridge`.
2. Select an existing INI template using the file picker or enter its path.
   Network files are supported. If an elevated setup cannot see a mapped drive,
   use a UNC path such as `\\server\share\scale.ini` and ensure the setup account
   can read that share.
3. Optionally choose a detected COM port or type one manually. **Aktualisieren**
   refreshes the list using the application's existing `--list-comports` command.
   Leave the field empty to retain the template's port. Port discovery failure
   does not prevent manual entry. Listing ports does not test scale connectivity.
4. Setup copies the template locally as `settings.ini`, applies only the optional
   `[scale] com-port` override, and installs/starts `IndustrialScaleRestBridge`
   with automatic startup and restart-on-failure recovery. The source template
   is never written or deleted; the service needs no access to the share later.

Use UTF-8 or BOM-marked UTF-16 INI templates. The template must have exactly one
`[scale]` section and one non-empty `com-port`, unless a missing port is supplied
in setup. Without an override the template is copied byte-for-byte. With an
override the local copy is written as UTF-8, retaining other settings, comments
and line endings. Other configuration requirements remain those described above.

The initial service account is LocalSystem. The template controls listening
address, logging and test mode; setup does not change those values or open
firewall ports. In particular, a template with `test-mode=true` keeps test mode
enabled. For file logging prefer an absolute path under
`C:\ProgramData\IndustrialScaleRestBridge`; provision the log directory and
grant the service account write access before installation.

Running setup again supports updates in the same directory. The installed local
INI is offered as the default template, so no network access is needed for an
ordinary update. Existing service credentials are retained. A same-name service
pointing at a different executable is rejected before its process or files are
changed. Configuration staging occurs before stopping a running service.

### Silent installation

The same wizard also accepts explicit inputs for automated deployment:

```powershell
.\IndustrialScaleRestBridge-1.0.0-win-x64-setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CONFIG="\\server\share\scale.ini" /COMPORT=COM3 /LOG="C:\Temp\scale-setup.log"
```

`/CONFIG` is required for a new installation; updates can default to the installed
INI. `/COMPORT` is optional. Standard Inno Setup arguments such as `/DIR` are
also supported. A configuration or service failure must be treated as a failed
installation, not ignored by deployment automation. For scripts that must wait
for completion and inspect its exit code, use `Start-Process -Wait -PassThru`.

### Uninstall and failure handling

Remove **Industrial Scale REST Bridge** through Windows Settings → Apps.
The uninstaller first stops the matching service and waits for SCM to confirm
its deletion. Only then does it remove the installed application and local INI.
If stopping/deleting the service fails, uninstall aborts and leaves program files
in place; close service-management tools holding handles open and retry.
Unrelated files or user-created logs are not recursively deleted.

Setup checks service command exit codes. On an interrupted or failed setup it
attempts to remove a newly created service, restore a previous local INI, and
restart a previously running service. This is best-effort recovery, not a
transactional application rollback; inspect the setup log and repair/re-run setup
after a failed update. A service-start failure produces a failure screen and
nonzero setup exit code; installed files and their uninstaller remain available
for repair/removal. Setup/uninstall logging is enabled by default.

### Installer checks

Configuration import tests run on PowerShell 5.1+ without Windows service access:

```powershell
pwsh -NoProfile -File tests/installer/test-settings.ps1
```

On a **disposable Windows test machine**, open an elevated PowerShell and run:

```powershell
.\tests\installer\test-windows-installer.ps1 -InstallerPath .\dist\installers\IndustrialScaleRestBridge-1.0.0-win-x64-setup.exe -AllowServiceChanges
```

This integration check refuses to touch an existing bridge service. It exercises
invalid configuration, service-start failure with nonzero setup exit, silent installation, local COM override, unchanged source,
REST response in test mode, update with retained local INI/account, service path
protection and uninstall. Artifacts and failures are retained for inspection.
Additionally check the graphical file picker, editable port list/refresh and an
accessible network share on Windows; the automated test uses a local template.
Native installer compilation and SCM behavior cannot be verified by running the
configuration tests or cross-publishing the executable on macOS.

## Run as a Windows service

The published application can optionally be registered as a native Windows service. The same executable continues to run as a normal console application when it is started directly. Windows service mode is activated automatically only when the executable is launched by the Windows Service Control Manager.

When running as a service, `settings.ini` is loaded from the directory containing `scale.exe`. Relative paths in `[logging] file` are resolved against that directory as well. During normal console operation, both paths remain relative to the current project or working directory.

### Install

1. Publish the application and put `settings.ini` next to the generated `scale.exe`.
2. Open Windows PowerShell 5.1 or later as Administrator.
3. Run the published installation script:

```powershell
.\dist\windows\install-windows-service.ps1
```

If script execution is disabled on the system, allow the published script for the current PowerShell session only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
Unblock-File .\dist\windows\install-windows-service.ps1
.\dist\windows\install-windows-service.ps1
```

Without `-ExecutablePath`, the script uses the `scale.exe` located in its own directory. An explicit executable can still be selected with `-ExecutablePath C:\Path\To\scale.exe`.

The service is installed as `IndustrialScaleRestBridge`, configured for automatic startup and started immediately. It is also configured to restart after a process failure. Use `-DoNotStart` if the service should only be registered. An existing service account can be selected with `-Credential (Get-Credential)`; that account must have the **Log on as a service** right.

For an update in the same directory, `-UpdateExisting` retains the existing
service account and restarts the service using the replaced executable. It
rejects a same-name service registered for another executable. Stop the service
before replacing its files; the graphical installer performs this sequencing.

The service account needs read and execute permission for the published directory, read access to `settings.ini`, access to the configured COM port, and write permission for the configured log directory. For a dedicated service account, an absolute log path below `C:\ProgramData\IndustrialScaleRestBridge` is recommended:

```ini
[logging]
file = C:\ProgramData\IndustrialScaleRestBridge\requests.log
```

### Operate and verify

```powershell
Get-Service -Name IndustrialScaleRestBridge
Invoke-RestMethod http://127.0.0.1:5000/current-weight/kg
Restart-Service -Name IndustrialScaleRestBridge
```

Host-level warnings and errors can be inspected in the Windows Application event log. If the service listens on a non-loopback address, configure the Windows Firewall for the selected port separately.

### Uninstall

Open PowerShell as Administrator and run:

```powershell
.\dist\windows\uninstall-windows-service.ps1
```

This standalone script removes only the service, not application files. It also
supports `-StopOnly` and an optional `-ExpectedExecutablePath` guard, used by the
graphical installer. Removal waits until SCM confirms the service no longer
exists, rather than treating a service marked for deletion as already removed.

## Usage

Open a browser and navigate to `http://localhost:5000/current-weight/kg`. The server will respond with the weight in the configured unit.

A HTTP 200 response normally looks like this:

```json
{
    "success": true,
    "weight": 2.32,
    "unit": "kilogram"
}
```

An error response will have the status code HTTP 500 and look like this:

```json
{
    "success": false,
    "message": "Operation timed out"
}
```
