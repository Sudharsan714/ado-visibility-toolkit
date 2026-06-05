# Contributing to ado-visibility-toolkit

Thank you for taking the time to contribute! All contributions are welcome — bug fixes, new scripts, documentation improvements, and feature ideas.

---

## Getting Started

1. **Fork** the repository and clone it locally
2. Create a **feature branch** from `main`:
   ```powershell
   git checkout -b feature/your-feature-name
   ```
3. Make your changes
4. Test your script manually against a real Azure DevOps organization
5. Submit a **Pull Request** with a clear description of what changed and why

---

## Coding Standards

All scripts in this project follow these conventions — please match them in any contribution:

**Structure**
- `#Requires -Version 5.1` at the top of every script
- `[CmdletBinding()]` on all scripts
- `Set-StrictMode -Version Latest` and `$ErrorActionPreference = "Stop"`
- All inputs via `param()` blocks with `[Parameter(Mandatory)]` and `[ValidateNotNullOrEmpty()]`

**Naming**
- Follow PowerShell `Verb-Noun` naming: `Get-ADO*`
- Use approved PowerShell verbs (`Get-Verb` to check)

**Documentation**
- Every script must have comment-based help: `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`, `.NOTES`
- `.NOTES` must include required PAT scopes and API version used

**Error handling**
- Wrap all API calls in `try/catch`
- Handle 401, 403, and 404 specifically with actionable error messages
- Use `-Verbose` for diagnostic output — never hardcode `Write-Output` debug lines

**Output**
- Always use `@()` when assigning API response values to avoid single-item unwrapping under `Set-StrictMode`
- Default CSV export goes to the `output/` folder relative to `$PSScriptRoot`
- Display a summary (total count, output path) at the end of each script

**Security**
- Never hardcode credentials, organization names, or resource IDs
- Only request the minimum PAT scopes needed (prefer read-only)

---

## Suggesting a New Script

If you have an idea for a new script, open an **Issue** first with:

- The Azure DevOps UI limitation it addresses
- What data it surfaces
- The REST API endpoint it would use
- Required PAT scopes

This keeps effort aligned before code is written.

---

## Reporting Bugs

Please open an **Issue** with:

- PowerShell version (`$PSVersionTable.PSVersion`)
- The script name and command you ran (redact your PAT and org name)
- The full error message
- Expected vs actual behaviour

---

## Pull Request Checklist

Before submitting, confirm:

- [ ] Script follows all coding standards above
- [ ] Comment-based help is complete
- [ ] No hardcoded credentials, org names, or GUIDs
- [ ] Tested against a real Azure DevOps organization
- [ ] `CHANGELOG.md` updated under an `[Unreleased]` section

---

## License

By contributing, you agree that your contributions will be licensed under the same [MIT License](LICENSE) as this project.
