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

## Run as a Windows service

The published application can optionally be registered as a native Windows service. The same executable continues to run as a normal console application when it is started directly. Windows service mode is activated automatically only when the executable is launched by the Windows Service Control Manager.

When running as a service, `settings.ini` is loaded from the directory containing `scale.exe`. Relative paths in `[logging] file` are resolved against that directory as well. During normal console operation, both paths remain relative to the current project or working directory.

### Install

1. Publish the application and put `settings.ini` next to the generated `scale.exe`.
2. Open PowerShell 6.2 or later as Administrator.
3. Run the published installation script:

```powershell
.\dist\windows\install-windows-service.ps1
```

Without `-ExecutablePath`, the script uses the `scale.exe` located in its own directory. An explicit executable can still be selected with `-ExecutablePath C:\Path\To\scale.exe`.

The service is installed as `IndustrialScaleRestBridge`, configured for automatic startup and started immediately. It is also configured to restart after a process failure. Use `-DoNotStart` if the service should only be registered. An existing service account can be selected with `-Credential (Get-Credential)`; that account must have the **Log on as a service** right.

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
