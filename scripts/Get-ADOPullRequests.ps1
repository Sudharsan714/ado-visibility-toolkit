#Requires -Version 5.1
<#
.SYNOPSIS
    Retrieves pull requests from an Azure DevOps repository with flexible filtering.

.DESCRIPTION
    Queries pull requests from a specific Azure DevOps repository. Supports
    filtering by date range, status, creator, and target branch. Results can
    be displayed in the console or exported to CSV.

    The Azure DevOps UI limits PR visibility and does not allow advanced
    cross-filter queries. This script provides full filtering flexibility
    via the REST API.

.PARAMETER Organization
    The name of your Azure DevOps organization.
    Example: "MyCompany"

.PARAMETER Project
    The name or ID of the Azure DevOps project.
    Example: "MyProject"

.PARAMETER RepositoryId
    The name or ID (GUID) of the Git repository.
    Use Get-ADORepositoryList.ps1 to find Repository IDs.

.PARAMETER PersonalAccessToken
    A Personal Access Token (PAT) with at least Read access to Code (Repos).

.PARAMETER Status
    Filter by pull request status.
    Valid values: Active, Abandoned, Completed, All
    Defaults to "All".

.PARAMETER StartDate
    Optional. Return only PRs created on or after this date.
    Example: "2024-01-01" or "2024-01-01T00:00:00Z"

.PARAMETER EndDate
    Optional. Return only PRs created on or before this date.
    Example: "2024-12-31" or "2024-12-31T23:59:59Z"

.PARAMETER CreatedBy
    Optional. Filter by the display name or email of the PR creator.
    Wildcard supported. Example: "john*" or "john.doe@company.com"

.PARAMETER TargetBranch
    Optional. Filter by target branch name.
    Example: "main" or "develop"

.PARAMETER ExportCsv
    Optional. Path to export results as a CSV file.
    Example: "C:\Reports\pull_requests.csv"

.EXAMPLE
    .\Get-ADOPullRequests.ps1 -Organization "MyCompany" -Project "MyProject" -RepositoryId "MyRepo" -PersonalAccessToken "your-pat-here"

    Retrieves all pull requests (any status) for the specified repository.

.EXAMPLE
    .\Get-ADOPullRequests.ps1 -Organization "MyCompany" -Project "MyProject" -RepositoryId "MyRepo" -PersonalAccessToken "your-pat-here" -Status "Active"

    Retrieves only active (open) pull requests.

.EXAMPLE
    .\Get-ADOPullRequests.ps1 -Organization "MyCompany" -Project "MyProject" -RepositoryId "MyRepo" -PersonalAccessToken "your-pat-here" -StartDate "2024-01-01" -EndDate "2024-12-31" -ExportCsv ".\prs_2024.csv"

    Retrieves all PRs created in 2024 and exports to CSV.

.EXAMPLE
    .\Get-ADOPullRequests.ps1 -Organization "MyCompany" -Project "MyProject" -RepositoryId "MyRepo" -PersonalAccessToken "your-pat-here" -CreatedBy "jane*" -TargetBranch "main"

    Retrieves PRs targeting "main" created by anyone matching "jane*".

.NOTES
    Required PAT Scopes: Code > Read
    API Version        : 7.1
    Author             : AzureDevOps-Tools

    Note: Date filtering uses the ADO API's searchCriteria.minTime / maxTime
    parameters, which filter on PR creation date.
    More info: https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-requests/get-pull-requests
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

    [Parameter(HelpMessage = "Filter by PR status: Active, Abandoned, Completed, All")]
    [ValidateSet("Active", "Abandoned", "Completed", "All")]
    [string]$Status = "All",

    [Parameter(HelpMessage = "Return PRs created on or after this date. Format: YYYY-MM-DD")]
    [string]$StartDate,

    [Parameter(HelpMessage = "Return PRs created on or before this date. Format: YYYY-MM-DD")]
    [string]$EndDate,

    [Parameter(HelpMessage = "Filter by creator display name or email (wildcard supported)")]
    [string]$CreatedBy,

    [Parameter(HelpMessage = "Filter by target branch name. Example: 'main'")]
    [string]$TargetBranch,

    [Parameter(HelpMessage = "Optional path to export results as CSV")]
    [string]$ExportCsv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Validate and normalise dates
# ---------------------------------------------------------------------------
function ConvertTo-IsoDate {
    param ([string]$Input, [string]$ParamName)
    try {
        $dt = [datetime]::Parse($Input)
        return $dt.ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    catch {
        Write-Error "$ParamName '$Input' is not a valid date. Use format YYYY-MM-DD or YYYY-MM-DDTHH:mm:ssZ"
        exit 1
    }
}

if ($StartDate) { $StartDate = ConvertTo-IsoDate $StartDate "-StartDate" }
if ($EndDate)   { $EndDate   = ConvertTo-IsoDate $EndDate   "-EndDate"   }

if ($StartDate -and $EndDate -and ([datetime]$StartDate -gt [datetime]$EndDate)) {
    Write-Error "-StartDate must be earlier than -EndDate."
    return
}

# ---------------------------------------------------------------------------
# Auth header
# ---------------------------------------------------------------------------
$base64Pat = [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes(":$PersonalAccessToken")
)
$headers = @{ Authorization = "Basic $base64Pat" }

# ---------------------------------------------------------------------------
# Build query string
# ---------------------------------------------------------------------------
$apiVersion   = "7.1"
$queryParams  = [System.Collections.Generic.List[string]]::new()

$queryParams.Add("api-version=$apiVersion")
$queryParams.Add("searchCriteria.repositoryId=$RepositoryId")

if ($Status -ne "All") {
    $queryParams.Add("searchCriteria.status=$($Status.ToLower())")
}
if ($StartDate) {
    $queryParams.Add("searchCriteria.minTime=$StartDate")
}
if ($EndDate) {
    $queryParams.Add("searchCriteria.maxTime=$EndDate")
}
if ($TargetBranch) {
    $targetRef = if ($TargetBranch -like "refs/*") { $TargetBranch } else { "refs/heads/$TargetBranch" }
    $queryParams.Add("searchCriteria.targetRefName=$targetRef")
}

# ---------------------------------------------------------------------------
# Pagination loop
# ---------------------------------------------------------------------------
$top    = 100
$skip   = 0
$allPRs = [System.Collections.Generic.List[object]]::new()

Write-Verbose "Fetching pull requests from repository: $RepositoryId"

do {
    $queryParams_page = $queryParams.Clone()
    $queryParams_page.Add("`$top=$top")
    $queryParams_page.Add("`$skip=$skip")

    $uri = "https://dev.azure.com/$Organization/$Project/_apis/git/pullrequests?$($queryParams_page -join '&')"

    Write-Verbose "GET $uri"

    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -ErrorAction Stop
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        switch ($statusCode) {
            401 { Write-Error "Authentication failed. Verify your PAT has 'Code > Read' scope."; return }
            403 { Write-Error "Access denied. Your PAT does not have sufficient permissions."; return }
            404 { Write-Error "Repository '$RepositoryId' not found in project '$Project'."; return }
            default { Write-Error "API request failed: $($_.Exception.Message)"; return }
        }
    }

    $page = @($response.value)
    if ($page.Count -gt 0) {
        $allPRs.AddRange($page)
        Write-Verbose "Retrieved $($page.Count) PR(s) (total so far: $($allPRs.Count))"
    }

    $skip += $top

} while ($page.Count -eq $top)

# ---------------------------------------------------------------------------
# Filter and format results
# ---------------------------------------------------------------------------
if ($allPRs.Count -eq 0) {
    Write-Warning "No pull requests found matching the specified criteria."
    return
}

$results = @($allPRs | ForEach-Object {
    [PSCustomObject]@{
        PullRequestId   = $_.pullRequestId
        Title           = $_.title
        Status          = $_.status
        CreatedBy       = $_.createdBy.displayName
        CreatedByEmail  = $_.createdBy.uniqueName
        CreationDate    = [datetime]$_.creationDate
        ClosedDate      = if ($_.closedDate) { [datetime]$_.closedDate } else { $null }
        SourceBranch    = $_.sourceRefName -replace '^refs/heads/', ''
        TargetBranch    = $_.targetRefName -replace '^refs/heads/', ''
        MergeStatus     = $_.mergeStatus
        ReviewerCount   = if ($_.reviewers) { $_.reviewers.Count } else { 0 }
        Url             = $_.url -replace '_apis/git/repositories/.*/pullRequests', '_git/' + $RepositoryId + '/pullRequest'
    }
})

# Client-side creator filter (API does not support partial name matching)
if ($CreatedBy) {
    $results = @($results | Where-Object {
        $_.CreatedBy -like $CreatedBy -or $_.CreatedByEmail -like $CreatedBy
    })
    Write-Verbose "Creator filter '$CreatedBy' applied. Matching PRs: $($results.Count)"
}

if ($results.Count -eq 0) {
    Write-Warning "No pull requests matched all specified filters."
    return
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
$results | Format-Table PullRequestId, Title, Status, CreatedBy, CreationDate, SourceBranch, TargetBranch -AutoSize

Write-Host "Total pull requests found: $($results.Count)" -ForegroundColor Cyan

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
    $ExportCsv = Join-Path $outputDir "ADO_PullRequests_$timestamp.csv"
}

try {
    $results | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
    Write-Host "Results exported to: $ExportCsv" -ForegroundColor Green
}
catch {
    Write-Error "Failed to export CSV: $($_.Exception.Message)"
}
