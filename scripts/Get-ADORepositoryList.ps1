#Requires -Version 5.1
<#
.SYNOPSIS
    Lists all repositories in an Azure DevOps project.

.DESCRIPTION
    Retrieves all Git repositories from the specified Azure DevOps project
    using the REST API. Supports outputting results to the console or
    exporting to a CSV file.

    This script addresses a limitation in the Azure DevOps UI where Repository
    IDs (GUIDs) are not directly visible, which are often required when using
    other REST API calls (e.g., querying branches or pull requests).

.PARAMETER Organization
    The name of your Azure DevOps organization.
    Example: "MyCompany"

.PARAMETER Project
    The name or ID of the Azure DevOps project.
    Example: "MyProject"

.PARAMETER PersonalAccessToken
    A Personal Access Token (PAT) with at least Read access to Code (Repos).
    If omitted, the script will use the $env:ADO_PAT environment variable.
    Recommended: set $env:ADO_PAT in your session instead of passing the token directly.

.PARAMETER IncludeDisabled
    Switch. When specified, includes disabled repositories in the results.
    By default, disabled repositories are excluded.

.PARAMETER ExportCsv
    Optional. Path to export results as a CSV file.
    Example: "C:\Reports\repositories.csv"

.EXAMPLE
    .\Get-ADORepositoryList.ps1 -Organization "MyCompany" -Project "MyProject" -PersonalAccessToken "your-pat-here"

    Lists all active repositories in the specified project.

.EXAMPLE
    .\Get-ADORepositoryList.ps1 -Organization "MyCompany" -Project "MyProject" -PersonalAccessToken "your-pat-here" -IncludeDisabled -ExportCsv ".\repos.csv"

    Lists all repositories including disabled ones and exports to CSV.

.EXAMPLE
    $env:ADO_PAT = "your-pat-here"
    .\Get-ADORepositoryList.ps1 -Organization "MyCompany" -Project "MyProject"

    Uses the environment variable for authentication — no need to pass the token directly.

.NOTES
    Required PAT Scopes: Code > Read
    API Version        : 7.1
    Author             : AzureDevOps-Tools
    More info          : https://learn.microsoft.com/en-us/rest/api/azure/devops/git/repositories/list
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory, HelpMessage = "Azure DevOps organization name")]
    [ValidateNotNullOrEmpty()]
    [string]$Organization,

    [Parameter(Mandatory, HelpMessage = "Project name or ID")]
    [ValidateNotNullOrEmpty()]
    [string]$Project,

    [Parameter(HelpMessage = "Personal Access Token with Code read access. Or set `$env:ADO_PAT")]
    [string]$PersonalAccessToken,

    [Parameter(HelpMessage = "Include disabled repositories in results")]
    [switch]$IncludeDisabled,

    [Parameter(HelpMessage = "Optional path to export results as CSV")]
    [string]$ExportCsv
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
# Auth header
# ---------------------------------------------------------------------------
$base64Pat = [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes(":$PersonalAccessToken")
)
$headers = @{ Authorization = "Basic $base64Pat" }

# ---------------------------------------------------------------------------
# Fetch repositories
# ---------------------------------------------------------------------------
$apiVersion = "7.1"
$uri = "https://dev.azure.com/$Organization/$Project/_apis/git/repositories?api-version=$apiVersion"

Write-Verbose "Fetching repositories from project: $Project"
Write-Verbose "GET $uri"

try {
    $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -ErrorAction Stop
}
catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    switch ($statusCode) {
        401 { Write-Error "Authentication failed. Verify your PAT is valid and has 'Code > Read' scope."; return }
        403 { Write-Error "Access denied. Your PAT does not have sufficient permissions."; return }
        404 { Write-Error "Project '$Project' not found in organization '$Organization'."; return }
        default { Write-Error "API request failed: $($_.Exception.Message)"; return }
    }
}

# ---------------------------------------------------------------------------
# Filter and format results
# ---------------------------------------------------------------------------
$repos = @($response.value)

if (-not $IncludeDisabled) {
    $repos = @($repos | Where-Object { $_.isDisabled -ne $true })
}

if ($repos.Count -eq 0) {
    Write-Warning "No repositories found in project '$Project'."
    return
}

$results = @($repos | ForEach-Object {
    [PSCustomObject]@{
        RepositoryName    = $_.name
        RepositoryId      = $_.id
        DefaultBranch     = $_.defaultBranch -replace '^refs/heads/', ''
        IsDisabled        = $_.isDisabled
        Size_KB           = [math]::Round($_.size / 1KB, 1)
        RemoteUrl         = $_.remoteUrl
    }
})

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
$results | Format-Table -AutoSize

Write-Host "Total repositories found: $($results.Count)" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Export CSV
# ---------------------------------------------------------------------------
if (-not $ExportCsv) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\output"))
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir | Out-Null
        Write-Verbose "Created output directory: $outputDir"
    }
    $ExportCsv = Join-Path $outputDir "ADO_RepositoryList_$timestamp.csv"
}

try {
    $results | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
    Write-Host "Results exported to: $ExportCsv" -ForegroundColor Green
}
catch {
    Write-Error "Failed to export CSV: $($_.Exception.Message)"
}
