#Requires -Version 5.1
<#
.SYNOPSIS
    Lists all projects in an Azure DevOps organization.

.DESCRIPTION
    Retrieves all projects from the specified Azure DevOps organization using
    the REST API. Supports outputting results to the console or exporting to
    a CSV file.

    This script addresses a limitation in the Azure DevOps UI where Project IDs
    (GUIDs) are not directly visible, which are often required when using other
    REST API calls.

.PARAMETER Organization
    The name of your Azure DevOps organization.
    Example: "MyCompany"

.PARAMETER PersonalAccessToken
    A Personal Access Token (PAT) with at least Read access to Projects.
    If omitted, the script will use the $env:ADO_PAT environment variable.
    Recommended: set $env:ADO_PAT in your session instead of passing the token directly.

.PARAMETER ExportCsv
    Optional. Path to export results as a CSV file.
    Example: "C:\Reports\projects.csv"

.EXAMPLE
    .\Get-ADOProjectList.ps1 -Organization "MyCompany" -PersonalAccessToken "your-pat-here"

    Lists all projects in the "MyCompany" organization to the console.

.EXAMPLE
    .\Get-ADOProjectList.ps1 -Organization "MyCompany" -PersonalAccessToken "your-pat-here" -ExportCsv ".\projects.csv"

    Lists all projects and exports the results to a CSV file.

.EXAMPLE
    $pat = Read-Host -Prompt "Enter PAT" -AsSecureString
    $plainPat = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pat)
    )
    .\Get-ADOProjectList.ps1 -Organization "MyCompany" -PersonalAccessToken $plainPat

    Prompts securely for a PAT before running.

.EXAMPLE
    $env:ADO_PAT = "your-pat-here"
    .\Get-ADOProjectList.ps1 -Organization "MyCompany"

    Uses the environment variable for authentication — no need to pass the token directly.

.NOTES
    Required PAT Scopes: Project and Team > Read
    API Version        : 7.1
    Author             : AzureDevOps-Tools
    More info          : https://learn.microsoft.com/en-us/rest/api/azure/devops/core/projects/list
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory, HelpMessage = "Azure DevOps organization name")]
    [ValidateNotNullOrEmpty()]
    [string]$Organization,

    [Parameter(HelpMessage = "Personal Access Token with Project read access. Or set `$env:ADO_PAT")]
    [string]$PersonalAccessToken,

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
# Pagination loop
# ---------------------------------------------------------------------------
$apiVersion  = "7.1"
$top         = 100
$skip        = 0
$allProjects = [System.Collections.Generic.List[object]]::new()

Write-Verbose "Fetching projects from organization: $Organization"

do {
    $uri = "https://dev.azure.com/$Organization/_apis/projects" +
           "?api-version=$apiVersion&`$top=$top&`$skip=$skip"

    Write-Verbose "GET $uri"

    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -ErrorAction Stop
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        switch ($statusCode) {
            401 { Write-Error "Authentication failed. Verify your PAT is valid and has 'Project and Team > Read' scope."; return }
            403 { Write-Error "Access denied. Your PAT does not have sufficient permissions."; return }
            404 { Write-Error "Organization '$Organization' not found. Check the organization name."; return }
            default { Write-Error "API request failed: $($_.Exception.Message)"; return }
        }
    }

    $page = @($response.value)
    if ($page.Count -gt 0) {
        $allProjects.AddRange($page)
        Write-Verbose "Retrieved $($page.Count) project(s) (total so far: $($allProjects.Count))"
    }

    $skip += $top

} while ($page.Count -eq $top)

# ---------------------------------------------------------------------------
# Format results
# ---------------------------------------------------------------------------
if ($allProjects.Count -eq 0) {
    Write-Warning "No projects found in organization '$Organization'."
    return
}

$results = @($allProjects | ForEach-Object {
    [PSCustomObject]@{
        ProjectName  = $_.name
        ProjectId    = $_.id
        State        = $_.state
        Visibility   = $_.visibility
        LastUpdated  = if ($_.lastUpdateTime) { [datetime]$_.lastUpdateTime } else { $null }
        Description  = $_.description
    }
})

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
$results | Format-Table -AutoSize

Write-Host "Total projects found: $($results.Count)" -ForegroundColor Cyan

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
    $ExportCsv = Join-Path $outputDir "ADO_ProjectList_$timestamp.csv"
}

try {
    $results | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
    Write-Host "Results exported to: $ExportCsv" -ForegroundColor Green
}
catch {
    Write-Error "Failed to export CSV: $($_.Exception.Message)"
}
