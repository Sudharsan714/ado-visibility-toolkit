# Security Policy

## Supported Versions

| Version | Supported |
|---|---|
| 1.x (latest) | ✅ Active |

---

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub Issues.**

If you discover a security vulnerability in this project, please report it responsibly by opening a [GitHub Security Advisory](../../security/advisories/new) (private disclosure).

Include as much of the following as possible:

- A description of the vulnerability
- The script(s) affected
- Steps to reproduce
- Potential impact
- Any suggested fix (optional)

You will receive a response within **72 hours** acknowledging the report. After the issue is investigated and resolved, a patched release will be published and you will be credited in the changelog (unless you prefer to remain anonymous).

---

## Security Design of This Project

This project is designed with a minimal-trust, read-only approach:

**PAT scopes — minimum required:**
| Script | Required scopes |
|---|---|
| `Get-ADOProjectList` | Project and Team → Read |
| `Get-ADORepositoryList` | Code → Read |
| `Get-ADOBranchCreators` | Code → Read |
| `Get-ADOOrgBranchCreators` | Project and Team → Read, Code → Read |
| `Get-ADOPullRequests` | Code → Read |

**No write operations** — all scripts use `GET` requests only. No data in your Azure DevOps organization is modified.

**No credential storage** — PATs are passed as runtime parameters only. This project never writes credentials to disk, the registry, or environment variables.

**No telemetry** — no data is sent anywhere other than the Azure DevOps REST API endpoint you specify.

---

## User Responsibilities

- **Rotate PATs regularly** and revoke them when no longer needed
- **Never commit a PAT** to source control — use `Read-Host -AsSecureString` or a secrets manager
- **CSV exports may contain sensitive data** (email addresses, branch names, project structure) — handle output files accordingly and add `output/*.csv` to your `.gitignore`
- Use **scoped PATs** with the minimum permissions listed above — never Full Access

---

## Known Limitations

- Scripts communicate over HTTPS to `https://dev.azure.com`. Ensure your network environment does not perform TLS inspection that could expose credentials in transit.
- PATs are passed as plain strings in the PowerShell session. Avoid running scripts in shared terminal sessions where process memory could be inspected.
