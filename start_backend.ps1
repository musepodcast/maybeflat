$ErrorActionPreference = "Stop"

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$ArgumentList = @(),

        [Parameter(Mandatory = $true)]
        [string]$FailureMessage
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw $FailureMessage
    }
}

function Resolve-BackendPythonCommand {
    param(
        [string]$ConfiguredPythonPath
    )

    if ($ConfiguredPythonPath) {
        return $ConfiguredPythonPath
    }

    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCommand) {
        return $pythonCommand.Source
    }

    $candidatePaths = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python311\python.exe"),
        (Join-Path $env:ProgramFiles "Python312\python.exe"),
        (Join-Path $env:ProgramFiles "Python311\python.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Python312\python.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Python311\python.exe")
    ) | Where-Object { $_ }

    foreach ($candidatePath in $candidatePaths) {
        if (Test-Path $candidatePath) {
            return $candidatePath
        }
    }

    throw @"
Unable to find a Python interpreter for the Maybeflat backend.

Install Python 3.11 or 3.12 from python.org, or point the script at it directly:
`$env:MAYBEFLAT_PYTHON = 'C:\Path\To\python.exe'
.\start_backend.ps1
"@
}

function Get-PythonVersionInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonPath
    )

    $versionJson = & $PythonPath -c "import json, sys; print(json.dumps({'major': sys.version_info[0], 'minor': sys.version_info[1], 'micro': sys.version_info[2], 'executable': sys.executable}))"
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect Python interpreter '$PythonPath'."
    }

    try {
        return $versionJson | ConvertFrom-Json
    } catch {
        throw "Unable to parse version details from Python interpreter '$PythonPath'."
    }
}

function Test-PythonModuleAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonPath,

        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )

    & $PythonPath -c "import $ModuleName"
    return ($LASTEXITCODE -eq 0)
}

function Format-PythonVersion {
    param(
        [Parameter(Mandatory = $true)]
        $VersionInfo
    )

    return "{0}.{1}.{2}" -f $VersionInfo.major, $VersionInfo.minor, $VersionInfo.micro
}

function Test-BackendPythonVersion {
    param(
        [Parameter(Mandatory = $true)]
        $VersionInfo
    )

    return ($VersionInfo.major -eq 3 -and @([int]11, [int]12) -contains [int]$VersionInfo.minor)
}

function Remove-BackendVenv {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackendDir,

        [Parameter(Mandatory = $true)]
        [string]$VenvDir
    )

    $resolvedBackendDir = [System.IO.Path]::GetFullPath($BackendDir)
    $resolvedVenvDir = [System.IO.Path]::GetFullPath($VenvDir)
    $expectedVenvDir = [System.IO.Path]::GetFullPath((Join-Path $BackendDir ".venv"))

    if ($resolvedVenvDir -ne $expectedVenvDir) {
        throw "Refusing to remove unexpected virtual environment path '$resolvedVenvDir'."
    }

    if (-not $resolvedVenvDir.StartsWith($resolvedBackendDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove virtual environment outside the backend directory."
    }

    Remove-Item -LiteralPath $resolvedVenvDir -Recurse -Force
}

function Assert-SupportedBackendPython {
    param(
        [Parameter(Mandatory = $true)]
        $VersionInfo,

        [Parameter(Mandatory = $true)]
        [string]$ContextLabel,

        [switch]$RequiresVenvReset
    )

    if (Test-BackendPythonVersion $VersionInfo) {
        return
    }

    $nextSteps = if ($RequiresVenvReset) {
        "3. Remove 'backend_api\.venv' so it can be recreated with the supported interpreter.`n4. Rerun .\start_backend.ps1"
    } else {
        "3. Rerun .\start_backend.ps1"
    }

    throw @"
Maybeflat backend dependencies require Python 3.11 or 3.12.
$ContextLabel is Python $(Format-PythonVersion $VersionInfo) at:
$($VersionInfo.executable)

Python 3.14 currently falls through to a source build for pydantic-core, which fails here.

Fix options:
1. Install a normal Python 3.11 or 3.12 release from python.org with pip and venv enabled.
2. Point this script at that interpreter:
   `$env:MAYBEFLAT_PYTHON = 'C:\Path\To\python.exe'
$nextSteps
"@
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendDir = Join-Path $root "backend_api"
$venvDir = Join-Path $backendDir ".venv"
$backendTempDir = Join-Path $backendDir ".tmp"
$pythonCommand = Resolve-BackendPythonCommand $env:MAYBEFLAT_PYTHON
$venvPython = Join-Path $backendDir ".venv\Scripts\python.exe"

Set-Location $backendDir

if (-not (Test-Path $backendTempDir)) {
    New-Item -ItemType Directory -Path $backendTempDir | Out-Null
}

$env:TEMP = $backendTempDir
$env:TMP = $backendTempDir

$selectedPython = Get-PythonVersionInfo $pythonCommand
Assert-SupportedBackendPython -VersionInfo $selectedPython -ContextLabel "The configured Python interpreter"

if (Test-Path $venvPython) {
    $recreateVenv = $false
    $venvVersion = $null

    try {
        $venvVersion = Get-PythonVersionInfo $venvPython
    } catch {
        Write-Host "Recreating backend virtual environment because the existing one is broken..."
        $recreateVenv = $true
    }

    if (($venvVersion -ne $null) -and (-not (Test-BackendPythonVersion $venvVersion))) {
        Write-Host "Recreating backend virtual environment because it uses unsupported Python $(Format-PythonVersion $venvVersion)..."
        $recreateVenv = $true
    }

    if ($recreateVenv) {
        Remove-BackendVenv -BackendDir $backendDir -VenvDir $venvDir
    }
}

if (-not (Test-Path $venvPython)) {
    Write-Host "Creating backend virtual environment..."
    Invoke-CheckedCommand -FilePath $pythonCommand -ArgumentList @("-m", "venv", ".venv") -FailureMessage "Virtual environment creation failed."
}

if (-not (Test-Path $venvPython)) {
    throw "Virtual environment was not created."
}

$venvVersion = Get-PythonVersionInfo $venvPython
Assert-SupportedBackendPython -VersionInfo $venvVersion -ContextLabel "The backend virtual environment"

if (-not (Test-PythonModuleAvailable -PythonPath $venvPython -ModuleName "pip")) {
    Write-Host "Bootstrapping pip in the backend virtual environment..."
    Invoke-CheckedCommand -FilePath $venvPython -ArgumentList @("-m", "ensurepip", "--upgrade") -FailureMessage "Unable to install pip into the backend virtual environment."
}

Write-Host "Installing backend dependencies..."
Invoke-CheckedCommand -FilePath $venvPython -ArgumentList @("-m", "pip", "install", "-r", "requirements.txt") -FailureMessage "Backend dependency installation failed. See the pip output above."

Write-Host "Starting Maybeflat backend on http://127.0.0.1:8002"
& $venvPython -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8002
if ($LASTEXITCODE -ne 0) {
    throw "Backend server exited unexpectedly."
}
