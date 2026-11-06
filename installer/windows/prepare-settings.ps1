#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $TemplatePath,
    [Parameter(Mandatory)] [string] $DestinationPath,
    [string] $ComPort
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$source = (Resolve-Path -LiteralPath $TemplatePath -ErrorAction Stop).ProviderPath
$destination = [IO.Path]::GetFullPath($DestinationPath)
if ([string]::Equals($source, $destination, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The configuration source and destination must be different files.'
}
if (-not [IO.File]::Exists($source)) { throw 'The selected template is not a file.' }

# StreamReader detects UTF-8/UTF-16 BOMs, as does the application's INI reader.
$text = [IO.File]::ReadAllText($source)
$sections = [regex]::Matches($text, '(?im)^[\t ]*\[scale\][\t ]*(?:;[^\r\n]*)?\r?$')
if ($sections.Count -ne 1) { throw 'The template must contain exactly one [scale] section.' }
$start = $sections[0].Index + $sections[0].Length
$remaining = $text.Substring($start)
$nextSection = [regex]::Match($remaining, '(?m)^[\t ]*\[')
$length = $remaining.Length
if ($nextSection.Success) { $length = $nextSection.Index }
$body = $remaining.Substring(0, $length)
$ports = [regex]::Matches($body, '(?im)^(?<prefix>[\t ]*com-port[\t ]*=[\t ]*)(?<value>[^;\r\n]*?)(?<suffix>[\t ]*(?:;[^\r\n]*)?)(?=\r?$)')
if ($ports.Count -gt 1) { throw 'The [scale] section contains more than one com-port setting.' }

if ($ComPort -match '[\x00-\x1f\x7f"]') { throw 'The COM port must not contain quotes or control characters.' }
$override = $ComPort.Trim()
if ([string]::IsNullOrEmpty($override)) {
    if ($ports.Count -ne 1 -or [string]::IsNullOrWhiteSpace($ports[0].Groups['value'].Value.Trim().Trim('"'))) {
        throw 'The template needs a non-empty [scale] com-port setting, or an explicit COM port override.'
    }
    # Do not normalize line endings or encoding when no override is requested.
    # Copy bytes, not source attributes: a read-only network template must not
    # turn the staged settings into a read-only file on a later setup attempt.
    [IO.File]::WriteAllBytes($destination, [IO.File]::ReadAllBytes($source))
} else {
    if ($ports.Count -eq 1) {
        $port = $ports[0]
        $value = $port.Groups['value']
        $body = $body.Substring(0, $value.Index) + $override + $body.Substring($value.Index + $value.Length)
    } else {
        $newline = "`n"
        if ($text.Contains("`r`n")) { $newline = "`r`n" }
        if (-not $body.EndsWith("`n")) { $body += $newline }
        $body += 'com-port=' + $override + $newline
    }
    $prepared = $text.Substring(0, $start) + $body + $remaining.Substring($length)
    [IO.File]::WriteAllText($destination, $prepared, (New-Object Text.UTF8Encoding($false)))
}
