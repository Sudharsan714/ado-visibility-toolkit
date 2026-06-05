# AzureDevOps-Tools

A collection of PowerShell scripts that expose information from Azure DevOps via the REST API — information that is either hidden or inaccessible through the standard UI.

---

## Why This Exists

The Azure DevOps UI has several visibility gaps that make day-to-day administration and auditing difficult:

- **Branch creators are not shown** anywhere in the UI — not on the branch list, not in repo settings.
- **Project and Repository IDs (GUIDs)** are not surfaced, yet they are required by many REST API calls.
- **Pull request filtering** in the UI is limited — no cross-filter on date range, creator, and target branch simultaneously.
- **There is no org-wide branch view** — you must navigate project by project, repo by repo.

These scripts fill those gaps.

---

## Scripts

| Script | What it does |
|---|---|
| [`Get-ADOProjectList.ps1`](#get-adoprojectlistps1) | Lists all projects + IDs in an organization |
| [`Get-ADORepositoryList.ps1`](#get-adorepositorylistps1) | Lists all repositories + IDs in a project |
| [`Get-ADOBranchCreators.ps1`](#get-adopranchcreatorsps1) | Shows who created each branch in a repository |
| [`Get-ADOOrgBranchCreators.ps1`](#get-adoorgbranchcreatorsps1) | Org-wide branch creator report → CSV |
| [`Get-ADOPullRequests.ps1`](#get-adopullrequestsps1) | Queries pull requests with flexible filters |

---

## Requirements

- **PowerShell 5.1** or later (Windows PowerShell or PowerShell 7+)
- A **Personal Access Token (PAT)** with the appropriate scopes (listed per script below)
- Network access to `https://dev.azure.com`

### Creating a PAT

1. Sign in to Azure DevOps and go to **User Settings → Personal Access Tokens**
2. Click **New Token**
3. Set the required scopes (see each script's notes below)
4. Copy the token — it is only shown once

> **Security:** Never hardcode your PAT in a script or commit it to source control.  
> Pass it as a parameter, use `Read-Host -AsSecureString`, or store it in a secrets manager.

---

## Usage

All scripts follow the same pattern:

```powershell
.\<ScriptName>.ps1 -Organization "YourOrg" [options]
```

Use `-Verbose` on any script to see detailed progress output.  
All scripts automatically export a timestamped CSV to the `output/` folder. Use `-ExportCsv "path\to\file.csv"` to override the output location.

### Authentication

All scripts support three authentication methods — choose the one that suits your workflow:

**Option 1 — Environment variable (recommended)**
Set once per session, then run any script without passing the token each time:
```powershell
$env:ADO_PAT = "your-pat-here"
.\Get-ADOOrgBranchCreators.ps1 -Organization "YourOrg"
.\Get-ADOProjectList.ps1 -Organization "YourOrg"
```

**Option 2 — Explicit parameter**
Pass the token directly on each call:
```powershell
.\Get-ADOOrgBranchCreators.ps1 -Organization "YourOrg" -PersonalAccessToken "your-pat-here"
```

**Option 3 — Secure prompt**
Avoids the token ever appearing in your terminal history:
```powershell
$env:ADO_PAT = Read-Host "Enter PAT"
.\Get-ADOOrgBranchCreators.ps1 -Organization "YourOrg"
```

> If neither `-PersonalAccessToken` nor `$env:ADO_PAT` is set, the script will exit with a clear error message.

### Output Folder

Every script saves its CSV report to an `output/` folder automatically created next to the `scripts/` folder:

```
Azure DevOps-Tools/
├── output/                                         ← reports saved here automatically
│   ├── ADO_ProjectList_20260605_120000.csv
│   ├── ADO_RepositoryList_20260605_120001.csv
│   ├── ADO_BranchCreators_20260605_120002.csv
│   ├── ADO_BranchCreators_Report_20260605_120003.csv
│   └── ADO_PullRequests_20260605_120004.csv
├── scripts/
│   ├── Get-ADOProjectList.ps1
│   ├── Get-ADORepositoryList.ps1
│   ├── Get-ADOBranchCreators.ps1
│   ├── Get-ADOOrgBranchCreators.ps1
│   └── Get-ADOPullRequests.ps1
├── README.md
├── CHANGELOG.md
└── LICENSE
```

The `output/` folder is created automatically on first run. You can override the path on any script using `-ExportCsv` (or `-OutputPath` for `Get-ADOOrgBranchCreators.ps1`).

---

## Scripts Reference

### Get-ADOProjectList.ps1

Lists all projects in an Azure DevOps organization, including their IDs, state, visibility, and last updated date.

**Required PAT scope:** `Project and Team > Read`

**Parameters:**

| Parameter | Required | Description |
|---|---|---|
| `-Organization` | ✅ | Azure DevOps organization name |
| `-PersonalAccessToken` | ➖ | PAT with Project read access. Or set `$env:ADO_PAT` |
| `-ExportCsv` | ➖ | Custom CSV path. Defaults to `output\ADO_ProjectList_<timestamp>.csv` |

**Examples:**

```powershell
# Using environment variable (recommended)
$env:ADO_PAT = "your-pat-here"
.\Get-ADOProjectList.ps1 -Organization "MyCompany"

# Using explicit parameter
.\Get-ADOProjectList.ps1 -Organization "MyCompany" -PersonalAccessToken "your-pat-here"

# Export to a custom path
.\Get-ADOProjectList.ps1 -Organization "MyCompany" -ExportCsv ".\projects.csv"
```

---

### Get-ADORepositoryList.ps1

Lists all repositories in a project, including their IDs, default branch, size, and remote URL.

**Required PAT scope:** `Code > Read`

**Parameters:**

| Parameter | Required | Description |
|---|---|---|
| `-Organization` | ✅ | Azure DevOps organization name |
| `-Project` | ✅ | Project name or ID |
| `-PersonalAccessToken` | ➖ | PAT with Code read access. Or set `$env:ADO_PAT` |
| `-IncludeDisabled` | ➖ | Include disabled repositories |
| `-ExportCsv` | ➖ | Custom CSV path. Defaults to `output\ADO_RepositoryList_<timestamp>.csv` |

**Examples:**

```powershell
# Using environment variable (recommended)
$env:ADO_PAT = "your-pat-here"
.\Get-ADORepositoryList.ps1 -Organization "MyCompany" -Project "TeamAlpha"

# Using explicit parameter
.\Get-ADORepositoryList.ps1 -Organization "MyCompany" -Project "TeamAlpha" -PersonalAccessToken "your-pat-here"

# Include disabled repos and export to custom path
.\Get-ADORepositoryList.ps1 -Organization "MyCompany" -Project "TeamAlpha" -IncludeDisabled -ExportCsv ".\repos.csv"
```

---

### Get-ADOBranchCreators.ps1

Lists every branch in a repository alongside the name and email of the person who created it. Supports wildcard filtering by branch name.

**Required PAT scope:** `Code > Read`

**Parameters:**

| Parameter | Required | Description |
|---|---|---|
| `-Organization` | ✅ | Azure DevOps organization name |
| `-Project` | ✅ | Project name or ID |
| `-RepositoryId` | ✅ | Repository name or ID |
| `-PersonalAccessToken` | ➖ | PAT with Code read access. Or set `$env:ADO_PAT` |
| `-Filter` | ➖ | Wildcard filter on branch name. Example: `feature/*` |
| `-ExportCsv` | ➖ | Custom CSV path. Defaults to `output\ADO_BranchCreators_<timestamp>.csv` |

**Examples:**

```powershell
# Using environment variable (recommended)
$env:ADO_PAT = "your-pat-here"
.\Get-ADOBranchCreators.ps1 -Organization "MyCompany" -Project "TeamAlpha" -RepositoryId "MyRepo"

# Using explicit parameter
.\Get-ADOBranchCreators.ps1 -Organization "MyCompany" -Project "TeamAlpha" -RepositoryId "MyRepo" -PersonalAccessToken "your-pat-here"

# Only feature branches
.\Get-ADOBranchCreators.ps1 -Organization "MyCompany" -Project "TeamAlpha" -RepositoryId "MyRepo" -Filter "feature/*"

# Export to custom path
.\Get-ADOBranchCreators.ps1 -Organization "MyCompany" -Project "TeamAlpha" -RepositoryId "MyRepo" -ExportCsv ".\branches.csv"
```

---

### Get-ADOOrgBranchCreators.ps1

Scans every project and repository in an organization and produces a single CSV report showing all branches and who created them. Inaccessible projects or repos are skipped with a warning rather than stopping the script.

**Required PAT scopes:** `Project and Team > Read`, `Code > Read`

**Parameters:**

| Parameter | Required | Description |
|---|---|---|
| `-Organization` | ✅ | Azure DevOps organization name |
| `-PersonalAccessToken` | ➖ | PAT with Project and Code read access. Or set `$env:ADO_PAT` |
| `-OutputPath` | ➖ | Custom CSV path. Defaults to `output\ADO_BranchCreators_Report_<timestamp>.csv` |
| `-ProjectFilter` | ➖ | Array of project names to scan. Omit to scan all. Example: `@("ProjectA","ProjectB")` |
| `-BranchFilter` | ➖ | Wildcard filter on branch name. Example: `feature/*` |

**Examples:**

```powershell
# Using environment variable (recommended)
$env:ADO_PAT = "your-pat-here"
.\Get-ADOOrgBranchCreators.ps1 -Organization "MyCompany"

# Using explicit parameter
.\Get-ADOOrgBranchCreators.ps1 -Organization "MyCompany" -PersonalAccessToken "your-pat-here"

# Specific output path
.\Get-ADOOrgBranchCreators.ps1 -Organization "MyCompany" -OutputPath "C:\Reports\branches.csv"

# Scan only selected projects
.\Get-ADOOrgBranchCreators.ps1 -Organization "MyCompany" -ProjectFilter @("TeamAlpha", "TeamBeta")

# Only feature branches across the org
.\Get-ADOOrgBranchCreators.ps1 -Organization "MyCompany" -BranchFilter "feature/*"
```

> **Note:** Large organizations may take several minutes. Progress is printed per project during the run.

---

### Get-ADOPullRequests.ps1

Retrieves pull requests from a repository with flexible filtering by status, date range, creator, and target branch.

**Required PAT scope:** `Code > Read`

**Parameters:**

| Parameter | Required | Description |
|---|---|---|
| `-Organization` | ✅ | Azure DevOps organization name |
| `-Project` | ✅ | Project name or ID |
| `-RepositoryId` | ✅ | Repository name or ID |
| `-PersonalAccessToken` | ➖ | PAT with Code read access. Or set `$env:ADO_PAT` |
| `-Status` | ➖ | `Active`, `Abandoned`, `Completed`, or `All` (default: `All`) |
| `-StartDate` | ➖ | PRs created on or after this date. Format: `YYYY-MM-DD` |
| `-EndDate` | ➖ | PRs created on or before this date. Format: `YYYY-MM-DD` |
| `-CreatedBy` | ➖ | Filter by creator display name or email (wildcard supported) |
| `-TargetBranch` | ➖ | Filter by target branch name. Example: `main` |
| `-ExportCsv` | ➖ | Custom CSV path. Defaults to `output\ADO_PullRequests_<timestamp>.csv` |

**Examples:**

```powershell
# Using environment variable (recommended)
$env:ADO_PAT = "your-pat-here"
.\Get-ADOPullRequests.ps1 -Organization "MyCompany" -Project "TeamAlpha" -RepositoryId "MyRepo"

# Active PRs targeting main
.\Get-ADOPullRequests.ps1 -Organization "MyCompany" -Project "TeamAlpha" -RepositoryId "MyRepo" -Status "Active" -TargetBranch "main"

# PRs created in Q1 2024, exported to CSV
.\Get-ADOPullRequests.ps1 -Organization "MyCompany" -Project "TeamAlpha" -RepositoryId "MyRepo" -StartDate "2024-01-01" -EndDate "2024-03-31" -ExportCsv ".\prs_q1_2024.csv"

# PRs by a specific person
.\Get-ADOPullRequests.ps1 -Organization "MyCompany" -Project "TeamAlpha" -RepositoryId "MyRepo" -CreatedBy "jane.doe@company.com"
```

---

## Security Notes

- **Rotate your PAT** if it was ever stored in a script file or committed to source control.
- Use the **minimum required scopes** when creating a PAT — never use Full Access.
- PATs should be treated like passwords. Use `$env:ADO_PAT` in your session or store them in a secrets manager (Azure Key Vault, 1Password, etc.) — never hardcode them in scripts.
- `$env:ADO_PAT` is session-scoped and disappears when the terminal is closed — it is never written to disk.
- CSV exports may contain email addresses and organizational data. Handle them accordingly.

---

## Troubleshooting

| Error | Likely cause |
|---|---|
| `401 Authentication failed` | PAT is invalid, expired, or revoked |
| `403 Access denied` | PAT lacks the required scope |
| `404 Not found` | Organization, project, or repository name is incorrect |
| `No results found` | Filters may be too narrow, or the PAT lacks access to certain resources |

Run any script with `-Verbose` to see the exact API URLs being called, which helps diagnose 404 errors.

---

## Contributing

Contributions are welcome. Please open an issue before submitting a pull request for significant changes.

---

## License

MIT License. See [LICENSE](LICENSE) for details.
