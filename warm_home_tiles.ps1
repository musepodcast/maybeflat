param(
    [ValidateSet("standard", "overnight")]
    [string]$Profile = "standard",

    [int]$PauseSeconds = 20
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repoRoot

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [string]$WorkingDirectory
    )

    if ($WorkingDirectory) {
        Push-Location $WorkingDirectory
    }

    try {
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "$FilePath $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        if ($WorkingDirectory) {
            Pop-Location
        }
    }
}

if ($PauseSeconds -lt 0) {
    throw "PauseSeconds must be zero or greater."
}

if (-not (Test-Path ".env.home")) {
    throw "Missing .env.home. Copy .env.home.example to .env.home first."
}

$dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCommand) {
    throw "Docker Desktop is required on this machine. Install Docker Desktop and make sure 'docker' is on PATH."
}

$stages = @(
    @{
        Name = "Extending coastline tiles through zoom 5"
        MaxZoom = "5"
        EdgeModes = "coastline"
    },
    @{
        Name = "Backfilling combined edge tiles through zoom 5"
        MaxZoom = "5"
        EdgeModes = "both"
    },
    @{
        Name = "Backfilling country boundary tiles through zoom 5"
        MaxZoom = "5"
        EdgeModes = "country"
    }
)

if ($Profile -eq "overnight") {
    $stages += @{
        Name = "Finishing the full shared tile pyramid through zoom 6"
        MaxZoom = "6"
        EdgeModes = "coastline,country,both"
    }
}

foreach ($stage in $stages) {
    Write-Host $stage.Name
    Invoke-External -FilePath "docker" -Arguments @(
        "compose",
        "-f",
        "docker-compose.home.yml",
        "--env-file",
        ".env.home",
        "exec",
        "-T",
        "api",
        "python",
        "generate_tiles.py",
        "--max-zoom",
        $stage.MaxZoom,
        "--edge-modes",
        $stage.EdgeModes
    )

    if ($PauseSeconds -gt 0 -and $stage -ne $stages[-1]) {
        Write-Host "Pausing $PauseSeconds seconds before the next backfill stage..."
        Start-Sleep -Seconds $PauseSeconds
    }
}

Write-Host ""
Write-Host "Home tile backfill complete."
