# Windows installer design

Approved basis: the conversation's Inno Setup proposal, Windows only, with
the selected network INI copied locally. Implementation authorized on 2026-11-06.

## Behavior

- An elevated German graphical wizard installs the self-contained win-x64
  application under `C:\Program Files\IndustrialScaleRestBridge` by default.
- The user selects an existing INI file using a file picker or a path, including
  UNC paths. Setup stages a local copy before stopping an existing service.
- A following page optionally overrides `[scale] com-port`, with an editable
  list populated by the existing `scale.exe --list-comports` command and a
  refresh button. Blank means retain the template value.
- Setup never writes to the source INI. It installs the prepared copy as
  `settings.ini` next to `scale.exe`.
- Setup installs and starts `IndustrialScaleRestBridge` with automatic startup
  and the existing recovery policy. First installation uses LocalSystem.
- Uninstall stops and removes that service before removing program files and
  the generated local configuration. Service failures abort file removal.

## Approaches

Inno Setup is recommended and used: native Windows wizard, scriptable dialogs,
and no additional runtime on target machines. NSIS offers similar functionality
without a benefit for this scope. Qt Installer Framework's cross-platform
capabilities are unnecessary after the Windows-only decision.

## Implementation decisions

- Reuse existing service scripts and COM discovery; no new service wrapper.
- Stage INI changes with a standalone PowerShell 5.1-compatible script so its
  file behavior can be tested on macOS without a Windows service or serial port.
- Support UTF-8 and BOM-marked UTF-16 templates, matching the application reader.
- On updates, offer the installed local INI as the default template and preserve
  existing service credentials. Reject an unrelated service with the same name.
- Keep logs outside Program Files when file logging is configured; setup does
  not invent or change the template's logging configuration.
- Build a self-contained offline installer. No automatic tool installation,
  code signing infrastructure, firewall changes, commits, or deployment.

## Module overview and cards

| Module | Responsibility / scope | Interface | Dependencies | Milestone |
| --- | --- | --- | --- | --- |
| CFG | Read-only source import, local INI staging, optional port override | `prepare-settings.ps1 -TemplatePath -DestinationPath [-ComPort]`; exit 0 or failure | PowerShell 5.1+ | CFG.M01 |
| SVC | Safe native service install/update/stop/removal | Existing scripts plus `-UpdateExisting`, `-StopOnly`, `-ExpectedExecutablePath` | Windows SCM, existing published exe | SVC.M01 |
| SET | German wizard, packaging, setup/uninstall sequencing | `build-installer.ps1 [-Version] [-IsccPath]`; setup `/CONFIG=... [/COMPORT=...]` | CFG, SVC, .NET SDK, Inno Setup 6.4+ | SET.M01 |

CFG.M01 is locally verified. SVC.M01 and SET.M01 are implemented with native
Windows acceptance outstanding. See the implementation plan for commands,
evidence and the distinction between code completion and platform acceptance.

Each milestone is a bounded approximately 2–3-hour professional work package.
Their status, acceptance and evidence are tracked in the implementation plan;
writing these documents does not count as implementation or Windows proof.
