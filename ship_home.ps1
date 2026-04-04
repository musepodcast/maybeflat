param(
    [Parameter(Mandatory = $true)]
    [string]$Message,
    [string]$Tag,
    [string]$ProductionPath
)

$ErrorActionPreference = "Stop"

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [string]$WorkingDirectory = $PWD.Path
    )

    Push-Location $WorkingDirectory
    try {
        & git @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "git $($Arguments -join ' ') failed in $WorkingDirectory"
        }
    }
    finally {
        Pop-Location
    }
}

function Get-GitOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [string]$WorkingDirectory = $PWD.Path
    )

    Push-Location $WorkingDirectory
    try {
        $output = & git @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "git $($Arguments -join ' ') failed in $WorkingDirectory"
        }
        return $output
    }
    finally {
        Pop-Location
    }
}

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repoRoot

if (-not $ProductionPath) {
    $ProductionPath = Join-Path (Split-Path $repoRoot -Parent) "maybeflat"
}

$resolvedProductionPath = [System.IO.Path]::GetFullPath($ProductionPath)
$resolvedRepoRoot = [System.IO.Path]::GetFullPath($repoRoot)

if ($resolvedProductionPath -eq $resolvedRepoRoot) {
    throw "ProductionPath resolves to the current repo. Use a separate production clone."
}

if (-not (Test-Path $resolvedProductionPath)) {
    throw "ProductionPath does not exist: $resolvedProductionPath"
}

if (-not (Test-Path (Join-Path $resolvedProductionPath ".git"))) {
    throw "ProductionPath is not a git repo: $resolvedProductionPath"
}

if (-not (Test-Path (Join-Path $resolvedProductionPath "deploy_home.ps1"))) {
    throw "ProductionPath does not look like the production maybeflat repo: $resolvedProductionPath"
}

if (-not (Test-Path (Join-Path $resolvedProductionPath ".env.home"))) {
    throw "ProductionPath is missing .env.home: $resolvedProductionPath"
}

$branch = (Get-GitOutput -Arguments @("branch", "--show-current") -WorkingDirectory $repoRoot | Out-String).Trim()
if ($branch -ne "main") {
    throw "ship_home.ps1 only deploys from main. Current branch: $branch"
}

$originUrl = (Get-GitOutput -Arguments @("remote", "get-url", "origin") -WorkingDirectory $repoRoot | Out-String).Trim()
$prodOriginUrl = (Get-GitOutput -Arguments @("remote", "get-url", "origin") -WorkingDirectory $resolvedProductionPath | Out-String).Trim()
if ($originUrl -ne $prodOriginUrl) {
    throw "Dev and production repos point at different origin remotes."
}

$productionStatus = (Get-GitOutput -Arguments @("status", "--porcelain") -WorkingDirectory $resolvedProductionPath | Out-String).Trim()
if ($productionStatus) {
    throw "Production repo has local changes. Commit or discard them before shipping."
}

$devStatus = (Get-GitOutput -Arguments @("status", "--porcelain") -WorkingDirectory $repoRoot | Out-String).Trim()
if (-not $devStatus) {
    throw "No changes to ship."
}

Write-Host "Staging dev changes..."
Invoke-Git -Arguments @("add", ".") -WorkingDirectory $repoRoot

$postStageStatus = (Get-GitOutput -Arguments @("status", "--porcelain") -WorkingDirectory $repoRoot | Out-String).Trim()
if (-not $postStageStatus) {
    throw "Nothing staged after git add ."
}

Write-Host "Committing on main..."
Invoke-Git -Arguments @("commit", "-m", $Message) -WorkingDirectory $repoRoot

if ($Tag) {
    Write-Host "Creating tag $Tag..."
    Invoke-Git -Arguments @("tag", "-a", $Tag, "-m", $Tag) -WorkingDirectory $repoRoot
}

Write-Host "Pushing to GitHub..."
Invoke-Git -Arguments @("push", "origin", "main") -WorkingDirectory $repoRoot

if ($Tag) {
    Write-Host "Pushing tag $Tag..."
    Invoke-Git -Arguments @("push", "origin", $Tag) -WorkingDirectory $repoRoot
}

Write-Host "Updating production repo..."
Invoke-Git -Arguments @("fetch", "--tags", "origin") -WorkingDirectory $resolvedProductionPath
Invoke-Git -Arguments @("checkout", "main") -WorkingDirectory $resolvedProductionPath
Invoke-Git -Arguments @("pull", "--ff-only", "origin", "main") -WorkingDirectory $resolvedProductionPath

Write-Host "Redeploying production..."
Push-Location $resolvedProductionPath
try {
    & powershell -ExecutionPolicy Bypass -File ".\deploy_home.ps1"
    if ($LASTEXITCODE -ne 0) {
        throw "deploy_home.ps1 failed in $resolvedProductionPath"
    }
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "Ship complete."
Write-Host "GitHub updated and production redeployed from $resolvedProductionPath"
