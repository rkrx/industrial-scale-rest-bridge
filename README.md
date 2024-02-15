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
scale-response-start-index = 13

; Omitting this value means "all remaining characters from the start index".
scale-response-part-length = 7

; The scale normally responds with a string, that contains the weight than could have a thousands separator. This value 
; indicates the thousands separator, which is then removed from the string.
scale-response-thousands-separator = .

; The scale normally responds with a string, that contains the weight than could have a decimal separator other than
; a dot. This value is used to replace the decimal separator, that comes from the scale, with a dot.
scale-response-decimal-separator = ,

; Can be kilogram, gram, carat, oz, lg or lbs. Default is kilogram.
scale-response-unit = kilogram

; The character that marks the end of the scale response (eot = end of transmission).
scale-response-eot = "\n"
```

## Project setup

You have to install the .NET 8.0 SDK to build and run the server. You can download it from the [official website](https://dotnet.microsoft.com/download).

### Restore dependencies

```bash
dotnet restore
```

### Run server

```bash
dotnet run
```

### Make executable

```bash
dotnet publish -c Release -r win-x64 -o dist -p:PublishReadyToRun=true -p:PublishSingleFile=true -p:PublishTrimmed=true --self-contained true -p:IncludeNativeLibrariesForSelfExtract=true
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
