$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$helper = Join-Path $PSScriptRoot '../../installer/windows/prepare-settings.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('scale-settings-' + [guid]::NewGuid())
[IO.Directory]::CreateDirectory($root) | Out-Null
$utf8 = New-Object Text.UTF8Encoding($false)
$passed = 0

function Assert-Equal($Expected, $Actual, [string] $Message) {
    if ($Expected -cne $Actual) { throw "$Message`nExpected: $Expected`nActual: $Actual" }
}

function Expect-Failure([scriptblock] $Action) {
    $failed = $false
    try { & $Action } catch { $failed = $true }
    if (-not $failed) { throw 'Expected configuration preparation to fail.' }
}

function Test-Case([string] $Name, [scriptblock] $Action) {
    & $Action
    $script:passed++
    Write-Host "PASS $Name"
}

try {
    $source = Join-Path $root 'Vorlage mit Umlaut ä.ini'
    $destination = Join-Path $root 'settings.ini'
    $template = "; Waage ä`r`n[service]`r`nlisten = http://127.0.0.1:5000`r`ncom-port = unrelated`r`n`r`n[scale]`r`ncom-port = COM1`r`nbaud-rate = 9600`r`ntrigger-code-byte-hex = 3C524E3E0D0A`r`n`r`n[other]`r`ncom-port = keep-me`r`n"
    [IO.File]::WriteAllText($source, $template, $utf8)

    Test-Case 'Blank override copies the source byte-for-byte' {
        & $helper -TemplatePath $source -DestinationPath $destination
        Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($source))) ([Convert]::ToBase64String([IO.File]::ReadAllBytes($destination))) 'Copy changed the source content.'
    }
    Test-Case 'Override changes only scale.com-port and preserves source, comments, CRLF and Unicode' {
        & $helper -TemplatePath $source -DestinationPath $destination -ComPort 'COM17'
        Assert-Equal ($template.Replace('com-port = COM1', 'com-port = COM17')) ([IO.File]::ReadAllText($destination)) 'Wrong port replacement.'
        Assert-Equal $template ([IO.File]::ReadAllText($source)) 'Source was modified.'
    }
    Test-Case 'Missing port can be added to the scale section' {
        [IO.File]::WriteAllText($source, "[scale]`nbaud-rate=9600`n[other]`nx=y", $utf8)
        & $helper -TemplatePath $source -DestinationPath $destination -ComPort 'COM4'
        Assert-Equal "[scale]`nbaud-rate=9600`ncom-port=COM4`n[other]`nx=y" ([IO.File]::ReadAllText($destination)) 'Port was not added to scale.'
    }
    Test-Case 'UTF-16 BOM template remains readable after override' {
        [IO.File]::WriteAllText($source, "[scale]`r`ncom-port=COM1`r`n; Grüße", [Text.Encoding]::Unicode)
        & $helper -TemplatePath $source -DestinationPath $destination -ComPort 'COM8'
        Assert-Equal "[scale]`r`ncom-port=COM8`r`n; Grüße" ([IO.File]::ReadAllText($destination)) 'UTF-16 import failed.'
    }
    Test-Case 'Quoted port without override is retained exactly' {
        [IO.File]::WriteAllText($source, "[scale]`ncom-port = `"COM3`"", $utf8)
        & $helper -TemplatePath $source -DestinationPath $destination -ComPort '  '
        Assert-Equal ([IO.File]::ReadAllText($source)) ([IO.File]::ReadAllText($destination)) 'Quoted port changed.'
    }
    Test-Case 'Inline port comment and spacing survive an override' {
        [IO.File]::WriteAllText($source, "[scale]`ncom-port = COM1  ; station A`n", $utf8)
        & $helper -TemplatePath $source -DestinationPath $destination -ComPort COM9
        Assert-Equal "[scale]`ncom-port = COM9  ; station A`n" ([IO.File]::ReadAllText($destination)) 'Inline comment changed.'
    }
    Test-Case 'Read-only template produces a writable staging copy' {
        [IO.File]::SetAttributes($source, [IO.FileAttributes]::ReadOnly)
        try {
            [IO.File]::Delete($destination)
            & $helper -TemplatePath $source -DestinationPath $destination
            Assert-Equal 0 ([int]([IO.File]::GetAttributes($destination) -band [IO.FileAttributes]::ReadOnly)) 'Staged settings inherited read-only attribute.'
            & $helper -TemplatePath $source -DestinationPath $destination -ComPort COM8
        } finally {
            [IO.File]::SetAttributes($source, [IO.FileAttributes]::Normal)
            if ([IO.File]::Exists($destination)) { [IO.File]::SetAttributes($destination, [IO.FileAttributes]::Normal) }
        }
    }
    Test-Case 'Missing, blank and ambiguous settings fail without damaging destination' {
        foreach ($invalid in @('[service]', "[scale]`ncom-port=", "[scale]`ncom-port=; no port", "[scale]`ncom-port=`"`"", "[scale]`ncom-port=COM1`ncom-port=COM2", "[scale]`ncom-port=COM1`n[scale]`ncom-port=COM2")) {
            [IO.File]::WriteAllText($source, $invalid, $utf8)
            [IO.File]::WriteAllText($destination, 'keep destination', $utf8)
            Expect-Failure { & $helper -TemplatePath $source -DestinationPath $destination }
            Assert-Equal 'keep destination' ([IO.File]::ReadAllText($destination)) 'Invalid input damaged destination.'
        }
    }
    Test-Case 'Missing source fails' {
        Expect-Failure { & $helper -TemplatePath (Join-Path $root 'missing.ini') -DestinationPath $destination }
    }
    Test-Case 'Source cannot also be destination' {
        [IO.File]::WriteAllText($source, "[scale]`ncom-port=COM1", $utf8)
        Expect-Failure { & $helper -TemplatePath $source -DestinationPath $source -ComPort COM2 }
        Assert-Equal "[scale]`ncom-port=COM1" ([IO.File]::ReadAllText($source)) 'Source was overwritten.'
    }
    Test-Case 'Newline and quote injection are rejected' {
        foreach ($port in @("COM1`n[service]", 'COM1"bad', ('COM1' + [char]1))) {
            Expect-Failure { & $helper -TemplatePath $source -DestinationPath $destination -ComPort $port }
        }
    }
    Write-Host "$passed configuration tests passed."
} finally {
    [IO.Directory]::Delete($root, $true)
}
