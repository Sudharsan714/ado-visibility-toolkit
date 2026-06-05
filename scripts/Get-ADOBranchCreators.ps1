#Requires -Version 5.1
<#
.SYNOPSIS
    Lists all branches and their creators for a specific Azure DevOps repository.

.DESCRIPTION
    Retrieves all Git branches from a specific repository and displays who
    created each branch. This information is not visible in the Azure DevOps UI,
    making it difficult to track branch ownership without this script.

    Supports filtering by branch name pattern, and optionally exports results
    to CSV.

.PARAMETER Organization
    The name of your Azure DevOps organization.
    Example: "MyCompany"

.PARAMETER Project
    The name or ID of the Azure DevOps project.
    Example: "MyProject"

.PARAMETER RepositoryId
    The name or ID (GUID) of the Git repository.
    Use Get-ADORepositoryList.ps1 to find Repository IDs.
    Example: "MyRepo" or "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

.PARAMETER PersonalAccessToken
    A Personal Access Token (PAT) with at least Read access to Code (Repos).

.PARAMETER Filter
    Optional. Filter branches by name pattern (wildcard supported).
    Example: "feature/*" returns only branches starting with "feature/"

.PARAMETER ExportCsv
    Optional. Path to export results as a CSV file.
    Example: "C:\Reports\branches.csv"

.EXAMPLE
    .\Get-ADOBranchCreators.ps1 -Organization "MyCompany" -Project "MyProject" -RepositoryId "MyRepo" -PersonalAccessToken "your-pat-here"

    Lists all branches and their creators for the specified repository.

.EXAMPLE
    .\Get-ADOBranchCreators.ps1 -Organization "MyCompany" -Project "MyProject" -RepositoryId "MyRepo" -PersonalAccessToken "your-pat-here" -Filter "feature/*"

    Lists only branches matching the "feature/*" pattern.

.EXAMPLE
    .\Get-ADOBranchCreators.ps1 -Organization "MyCompany" -Project "MyProject" -RepositoryId "MyRepo" -PersonalAccessToken "your-pat-here" -ExportCsv ".\branches.csv"

    Lists all branches and exports the results to a CSV file.

.NOTES
    Required PAT Scopes: Code > Read
    API Version        : 7.1
    Author             : AzureDevOps-Tools
    More info          : https://learn.microsoft.com/en-us/rest/api/azure/devops/git/refs/list
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory, HelpMessage = "Azure DevOps organization name")]
    [ValidateNotNullOrEmpty()]
    [string]$Organization,

    [Parameter(Mandatory, HelpMessage = "Project name or ID")]
    [ValidateNotNullOrEmpty()]
    [string]$Project,

    [Parameter(Mandatory, HelpMessage = "Repository name or ID. Use Get-ADORepositoryList.ps1 to find IDs.")]
    [ValidateNotNullOrEmpty()]
    [string]$RepositoryId,

    [Parameter(Mandatory, HelpMessage = "Personal Access Token with Code read access")]
    [ValidateNotNullOrEmpty()]
    [string]$PersonalAccessToken,

    [Parameter(HelpMessage = "Filter branches by name pattern (wildcard). Example: 'feature/*'")]
    [string]$Filter,

    [Parameter(HelpMessage = "Optional path to export results as CSV")]
    [string]$ExportCsv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Auth header
# ---------------------------------------------------------------------------
$base64Pat = [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes(":$PersonalAccessToken")
)
$headers = @{ Authorization = "Basic $base64Pat" }

# ---------------------------------------------------------------------------
# Pagination loop
# ---------------------------------------------------------------------------
$apiVersion  = "7.1"
$top         = 100
$skip        = 0
$allBranches = [System.Collections.Generic.List[object]]::new()

Write-Verbose "Fetching branches from repository: $RepositoryId"

do {
    $uri = "https://dev.azure.com/$Organization/$Project/_apis/git/repositories/$RepositoryId/refs" +
           "?filter=heads/&api-version=$apiVersion&`$top=$top&`$skip=$skip"

    Write-Verbose "GET $uri"

    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -ErrorAction Stop
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        switch ($statusCode) {
            401 { Write-Error "Authentication failed. Verify your PAT is valid and has 'Code > Read' scope."; return }
            403 { Write-Error "Access denied. Your PAT does not have sufficient permissions."; return }
            404 { Write-Error "Repository '$RepositoryId' not found in project '$Project'."; return }
            default { Write-Error "API request failed: $($_.Exception.Message)"; return }
        }
    }

    $page = @($response.value)
    if ($page.Count -gt 0) {
        $allBranches.AddRange($page)
        Write-Verbose "Retrieved $($page.Count) branch(es) (total so far: $($allBranches.Count))"
    }

    $skip += $top

} while ($page.Count -eq $top)

# ---------------------------------------------------------------------------
# Filter and format results
# ---------------------------------------------------------------------------
if ($allBranches.Count -eq 0) {
    Write-Warning "No branches found in repository '$RepositoryId'."
    return
}

$results = @($allBranches | ForEach-Object {
    [PSCustomObject]@{
        BranchName       = $_.name -replace '^refs/heads/', ''
        CreatedByName    = $_.creator.displayName
        CreatedByEmail   = $_.creator.uniqueName
        ObjectId         = $_.objectId
    }
})

if ($Filter) {
    $results = @($results | Where-Object { $_.BranchName -like $Filter })
    Write-Verbose "Filter '$Filter' applied. Matching branches: $($results.Count)"
}

if ($results.Count -eq 0) {
    Write-Warning "No branches matched the filter: '$Filter'"
    return
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
$results | Format-Table -AutoSize

Write-Host "Total branches found: $($results.Count)" -ForegroundColor Cyan

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
    $ExportCsv = Join-Path $outputDir "ADO_BranchCreators_$timestamp.csv"
}

try {
    $results | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
    Write-Host "Results exported to: $ExportCsv" -ForegroundColor Green
}
catch {
    Write-Error "Failed to export CSV: $($_.Exception.Message)"
}
