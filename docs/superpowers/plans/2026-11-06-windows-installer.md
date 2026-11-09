# Windows Installer Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this
> approved plan inline. Do not commit or publish without user authorization.

**Goal:** Deliver a Windows graphical installer with local INI import, optional
serial-port selection and native service installation/removal.

**Architecture:** Inno Setup owns UI and ordering. A PowerShell helper stages the
INI, and the existing service scripts own SCM operations. The application stays
unchanged.

**Tech Stack:** Inno Setup 6.4+, PowerShell 5.1+, self-contained .NET 9 win-x64.

**Spec:** `docs/superpowers/specs/2026-11-06-windows-installer-design.md`

## Global Constraints

- Windows only; local copy of selected source INI; never modify network source.
- Configuration filename and service name remain `settings.ini` and
  `IndustrialScaleRestBridge`.
- Blank COM override retains the template value. Source must be readable before
  setup stops a service. Uninstall must remove the service before deleting files.
- No new target runtime dependency, infrastructure, commit, or deployment.

## Review Focus

- Unicode/space/UNC paths and comments must survive configuration import.
- Missing port, duplicate port/scale section, or newline injection must fail
  before the source or destination is damaged.
- Existing service credentials and unrelated same-name services need protection.
- Service stop/delete errors must prevent removal of executable/configuration.
- Upgrade, port discovery failure and silent setup must preserve clear behavior.

## CFG.M01 — INI staging (2–3 hours)

Files: `installer/windows/prepare-settings.ps1`,
`tests/installer/test-settings.ps1`.

Consumes an existing template path and optional override; produces a local
UTF-8 `settings.ini` or a nonzero exit without modifying the source.

- [x] Write and run failing behavioral tests for exact copy, section-scoped
  override, adding a missing port, Unicode/CRLF, unchanged source, unsafe
  same-file destination, missing/ambiguous input and newline injection.
- [x] Implement helper, run `pwsh -NoProfile -File tests/installer/test-settings.ps1`.
- [x] Record passing checks and remaining Windows acceptance.

## SVC.M01 — Native service lifecycle (2–3 hours)

Files: `scripts/install-windows-service.ps1`,
`scripts/uninstall-windows-service.ps1`, `tests/installer/test-windows-installer.ps1`.

Consumes staged application/configuration; produces a running service or failure.
Uninstall must wait for service deletion. Guard operations with the expected
executable path; update existing service without replacing its account.

- [x] Add an opt-in Windows integration test: fresh silent installation,
  source hash preservation, REST test response, upgrade retaining local INI,
  same-name path protection, uninstall and file removal.
- [x] Extend lifecycle scripts, parse all PowerShell files locally.
- [ ] Run integration on an isolated Windows machine when available; otherwise
  explicitly leave native acceptance outstanding.

## SET.M01 — Wizard and packaging (2–3 hours)

Files: `installer/windows/industrial-scale-rest-bridge.iss`,
`scripts/build-installer.ps1`, `.gitignore`, `README.md`.

Consumes CFG/SVC and published win-x64 files; produces an offline setup EXE.

- [x] Add German file selection and editable COM list with refresh; stage settings
  before file copy, check service exit codes and abort uninstall safely.
- [x] Add repeatable Windows publish/compiler entry point with explicit version.
- [x] Document graphical use, silent arguments, build and Windows smoke checks.
- [x] Run configuration tests, PowerShell parser checks, .NET build and Windows
  cross-publish; review all changes.
- [ ] Compile/run the installer on Windows and record native acceptance.

## SET.M02 — GitHub-hosted installer build (2–3 hours)

Extension requested after commit `136cf2c`; depends on CFG.M01, SVC.M01 and
SET.M01's existing scripts. This milestone automates the outstanding native
build/service checks without counting them as passed until an actual run.

Files: `.github/workflows/windows-installer.yml`, `.gitignore`, `README.md` and
the existing module overview/plan. No changes to installer or application code.

Consumes the manually selected repository ref and numeric `version` input;
produces a tested setup EXE in an Actions artifact, plus diagnostic logs.

- [x] Check official runner/action documentation and pin official action commits.
- [x] Add manual Windows job reusing `scripts/build-installer.ps1`, with Windows
  PowerShell 5.1 configuration tests and native installer integration tests.
- [x] Upload the EXE only after successful tests; upload diagnostics on failure.
- [x] Document startup/default-branch requirements, download and artifact retention.
- [x] Validate workflow syntax and embedded PowerShell; run local config checks.
- [ ] After authorized publishing, run Actions and record compiler/native results.

## Evidence / status

- Baseline: clean checkout; existing native Windows service integration and
  `--list-comports`; macOS with .NET SDK 10 and PowerShell available.
- Native Inno compiler and Windows SCM are unavailable locally.
- CFG.M01 complete: 11 behavioral tests pass on PowerShell 7.5.4/macOS, including
  inline-comment preservation and writable staging of read-only source files.
- SVC.M01 implemented: expected-path guards, account-preserving updates, stop-only
  and deletion confirmation. Native acceptance remains open.
- SET.M01 implemented: German wizard, manual/discovered ports, silent parameters,
  staged local INI, build entry point, failure UI and nonzero failure exit.
  Native compiler/GUI acceptance remains open; no setup EXE has been built here.
- Baseline .NET build and self-contained win-x64 cross-publish passed. Cross-publish
  used `PublishReadyToRun=false` on macOS; the Windows build script enables it.
  Existing `NU1701` warning for `ini-parser 2.5.2` remains unchanged.
- Real application read prepared INI and returned 123.45 kg through REST in
  synthetic test mode on macOS (.NET 10 with explicit major roll-forward).
  This does not establish .NET 9 Windows service behavior or hardware access.
- Read-only independent review identified Inno's swallowed postinstall exceptions.
  Fixed by explicit failure state, failure finish text and nonzero custom exit;
  native fresh/upgrade failure scenarios are included in the integration test.
- Initial installer implementation committed as `136cf2c` at the user's request.
  No publishing or installation on a target machine performed.
- SET.M02 workflow implemented locally; native execution remains outstanding.
- SET.M02 local checks: actionlint 1.7.12 passed, all three embedded PowerShell
  scripts parsed, and all 11 configuration tests passed. Independent review found
  a potentially mismatched diagnostic path; setting integration-step TEMP/TMP to
  `runner.temp` makes the upload path deterministic. No Actions run performed.
- 2026-11-09: User supplied the first native Actions compiler result: .NET
  publishing succeeded; Inno Setup 6.7.1 failed preprocessing at line 269 because
  the Pascal `#13#10` literal began a line and was parsed as a directive. Moved
  the unchanged literal to the preceding line. Fix is local; native compilation
  and subsequent integration acceptance still require another Actions run.
