#Requires -Version 5.1
<#
.SYNOPSIS
    Generates an organization-wide report of all branches and their creators,
    exported to CSV.

.DESCRIPTION
    Scans every project and repository in an Azure DevOps organization and
    collects branch creator information. Results are exported as a CSV report.

    This script addresses a key limitation in the Azure DevOps UI: there is no
    built-in view that shows branch creators across an entire organization.
    This script bridges that gap by iterating all accessible projects and repos.

    Progress is displayed during the run. Inaccessible projects or repositories
    are skipped with a warning rather than terminating the script.

.PARAMETER Organization
    The name of your Azure DevOps organization.
    Example: "MyCompany"

.PARAMETER PersonalAccessToken
    A Personal Access Token (PAT) with Read access to Projects and Code (Repos).
    If omitted, the script will use the $env:ADO_PAT environment variable.
    Recommended: set $env:ADO_PAT in your session instead of passing the token directly.

.PARAMETER OutputPath
    Path for the exported CSV report.
    Defaults to "ADO_BranchCreators_Report_<timestamp>.csv" in the current directory.

.PARAMETER ProjectFilter
    Optional. Comma-separated list of project names to include.
    When omitted, all accessible projects are scanned.
    Example: @("ProjectA", "ProjectB")

.PARAMETER BranchFilter
    Optional. Filter branches by name pattern (wildcard supported).
    Example: "feature/*" returns only branches starting with "feature/"

.EXAMPLE
    .\Get-ADOOrgBranchCreators.ps1 -Organization "MyCompany" -PersonalAccessToken "your-pat-here"

    Scans all projects and exports a CSV to the current directory.

.EXAMPLE
    .\Get-ADOOrgBranchCreators.ps1 -Organization "MyCompany" -PersonalAccessToken "your-pat-here" -OutputPath "C:\Reports\branches.csv"

    Scans all projects and exports the report to the specified path.

.EXAMPLE
    .\Get-ADOOrgBranchCreators.ps1 -Organization "MyCompany" -PersonalAccessToken "your-pat-here" -ProjectFilter @("TeamAlpha", "TeamBeta")

    Scans only the specified projects.

.EXAMPLE
    $env:ADO_PAT = "your-pat-here"
    .\Get-ADOOrgBranchCreators.ps1 -Organization "MyCompany"

    Uses the environment variable for authentication — no need to pass the token directly.

.NOTES
    Required PAT Scopes: Project and Team > Read, Code > Read
    API Version        : 7.1
    Author             : AzureDevOps-Tools

    Performance note: Large organizations with many repositories may take
    several minutes to complete. Progress is shown per project.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory, HelpMessage = "Azure DevOps organization name")]
    [ValidateNotNullOrEmpty()]
    [string]$Organization,

    [Parameter(HelpMessage = "Personal Access Token with Project and Code read access. Or set `$env:ADO_PAT")]
    [string]$PersonalAccessToken,

    [Parameter(HelpMessage = "Output path for the CSV report. Defaults to timestamped file in current directory.")]
    [string]$OutputPath,

    [Parameter(HelpMessage = "List of project names to scan. Omit to scan all projects.")]
    [string[]]$ProjectFilter,

    [Parameter(HelpMessage = "Filter branches by name pattern (wildcard). Example: 'feature/*'")]
    [string]$BranchFilter
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Resolve PAT
# ---------------------------------------------------------------------------
if (-not $PersonalAccessToken) {
    if ($env:ADO_PAT) {
        $PersonalAccessToken = $env:ADO_PAT
        Write-Verbose "Using PAT from environment variable `$env:ADO_PAT"
    } else {
        Write-Error "No PAT provided. Pass -PersonalAccessToken or set `$env:ADO_PAT before running."
        return
    }
}

# ---------------------------------------------------------------------------
# Default output path
# ---------------------------------------------------------------------------
if (-not $OutputPath) {
    $timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputDir  = Join-Path $PSScriptRoot "..\output"
    $outputDir  = [System.IO.Path]::GetFullPath($outputDir)
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir | Out-Null
        Write-Verbose "Created output directory: $outputDir"
    }
    $OutputPath = Join-Path $outputDir "ADO_BranchCreators_Report_$timestamp.csv"
}

# ---------------------------------------------------------------------------
# Auth header + helper
# ---------------------------------------------------------------------------
$base64Pat = [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes(":$PersonalAccessToken")
)
$headers = @{ Authorization = "Basic $base64Pat" }

function Invoke-AdoGet {
    param ([string]$Uri)
    Invoke-RestMethod -Uri $Uri -Method Get -Headers $headers -ErrorAction Stop
}

function Get-PagedResults {
    <#
    .SYNOPSIS Helper to handle ADO API pagination (100-item pages).
    #>
    param ([string]$BaseUri)

    $top     = 100
    $skip    = 0
    $all     = [System.Collections.Generic.List[object]]::new()

    do {
        $separator = if ($BaseUri -match '\?') { '&' } else { '?' }
        $uri       = "$BaseUri${separator}`$top=$top&`$skip=$skip"

        Write-Verbose "GET $uri"
        $response = Invoke-AdoGet $uri

        $page = @($response.value)
        if ($page.Count -gt 0) {
            $all.AddRange($page)
        }

        $skip += $top

    } while ($page.Count -eq $top)

    return $all
}

# ---------------------------------------------------------------------------
# Fetch projects
# ---------------------------------------------------------------------------
Write-Host "Connecting to organization: $Organization" -ForegroundColor Cyan

try {
    $projects = @(Get-PagedResults "https://dev.azure.com/$Organization/_apis/projects?api-version=7.1")
}
catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    switch ($statusCode) {
        401 { Write-Error "Authentication failed. Verify your PAT and that it has 'Project and Team > Read' scope."; return }
        403 { Write-Error "Access denied to organization '$Organization'."; return }
        404 { Write-Error "Organization '$Organization' not found."; return }
        default { Write-Error "Failed to retrieve projects: $($_.Exception.Message)"; return }
    }
}

if ($ProjectFilter) {
    $projects = @($projects | Where-Object { $_.name -in $ProjectFilter })
    Write-Host "Project filter applied. Scanning $(@($projects).Count) project(s)." -ForegroundColor Yellow
}

if (@($projects).Count -eq 0) {
    Write-Warning "No projects found (or none matched the filter)."
    return
}

Write-Host "Found $(@($projects).Count) project(s). Starting scan...`n" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Scan all projects → repos → branches
# ---------------------------------------------------------------------------
$results         = [System.Collections.Generic.List[PSCustomObject]]::new()
$projectIndex    = 0
$skippedRepos    = 0
$skippedProjects = 0

foreach ($project in $projects) {

    $projectIndex++
    $projectName = $project.name
    $projectId   = $project.id

    Write-Host "[$projectIndex/$(@($projects).Count)] Project: $projectName" -ForegroundColor White

    # --- Repositories ---
    try {
        $repos = Invoke-AdoGet "https://dev.azure.com/$Organization/$projectId/_apis/git/repositories?api-version=7.1"
    }
    catch {
        Write-Warning "  Skipping project '$projectName' - could not retrieve repositories: $($_.Exception.Message)"
        $skippedProjects++
        continue
    }

    $activeRepos = @($repos.value | Where-Object { $_.isDisabled -ne $true })

    if ($activeRepos.Count -eq 0) {
        Write-Host "  No active repositories found." -ForegroundColor DarkGray
        continue
    }

    foreach ($repo in $activeRepos) {

        $repoName = $repo.name
        $repoId   = $repo.id

        Write-Host "  Repo: $repoName" -ForegroundColor DarkCyan

        # --- Branches ---
        try {
            $branches = @(Get-PagedResults "https://dev.azure.com/$Organization/$projectId/_apis/git/repositories/$repoId/refs?filter=heads/&api-version=7.1")
        }
        catch {
            Write-Warning "    Skipping repo '$repoName': $($_.Exception.Message)"
            $skippedRepos++
            continue
        }

        if ($branches.Count -eq 0) {
            Write-Host "    No branches found." -ForegroundColor DarkGray
            continue
        }

        foreach ($branch in $branches) {

            $branchName = $branch.name -replace '^refs/heads/', ''

            if ($BranchFilter -and ($branchName -notlike $BranchFilter)) {
                continue
            }

            $null = $results.Add([PSCustomObject]@{
                ProjectName    = $projectName
                ProjectId      = $projectId
                RepositoryName = $repoName
                RepositoryId   = $repoId
                BranchName     = $branchName
                CreatedByName  = $branch.creator.displayName
                CreatedByEmail = $branch.creator.uniqueName
                ObjectId       = $branch.objectId
            })
        }

        Write-Host "    Branches collected: $($branches.Count)" -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------
# Export CSV
# ---------------------------------------------------------------------------
Write-Host ""

if ($results.Count -eq 0) {
    Write-Warning "No branch data collected. Nothing to export."
    return
}

try {
    $results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
}
catch {
    Write-Error "Failed to write CSV to '$OutputPath': $($_.Exception.Message)"
    return
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Report Summary" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Total branches   : $($results.Count)"
Write-Host " Projects scanned : $(@($projects).Count - $skippedProjects) / $(@($projects).Count)"
Write-Host " Repos skipped    : $skippedRepos"
Write-Host " Output file      : $OutputPath" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
