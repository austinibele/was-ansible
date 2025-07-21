<#
 .SYNOPSIS
    Bootstrap AWS CLI v2, Docker, and ECR login on Windows.
 .NOTES
    Equivalent to the provided Linux Bash script.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------------
# Helper: Write consistently‑formatted status lines
function Write-Step($msg) { Write-Host ">> $msg" }
# ----------------------------------------------------------------------

# ----------------------------------------------------------------------
# 1) Install AWS CLI ----------------------------------------------------
# ----------------------------------------------------------------------
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Step "AWS CLI not found – installing…"
    $msi = "$env:TEMP\AWSCLIV2.msi"
    Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile $msi
    Start-Process msiexec.exe -Wait -ArgumentList "/i `"$msi`" /qn"
    Remove-Item $msi -Force
    $awsVersion = try { aws --version 2>&1 } catch { "version check failed" }
    Write-Step "Installed AWS CLI: $awsVersion"
} else {
    $awsVersion = try { aws --version 2>&1 } catch { "version check failed" }
    Write-Step "AWS CLI already present: $awsVersion"
}

# ----------------------------------------------------------------------
# 2) Install (or repair) Docker ----------------------------------------
# ----------------------------------------------------------------------
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Step "Docker not found – installing…"

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        # winget ≥ 1.4 supports unattended licence acceptance
        winget install --id Docker.DockerDesktop -e `
                       --accept-package-agreements --accept-source-agreements
    }
    elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        choco install docker-desktop -y --no-progress
    }
    else {
        # Fallback: download current Docker Desktop installer and run it quietly
        $exe = "$env:TEMP\DockerDesktopInstaller.exe"
        Invoke-WebRequest -Uri "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe" -OutFile $exe
        Start-Process $exe -Wait -ArgumentList "install --quiet"
        Remove-Item $exe -Force
    }

    # Ensure the invoking user can run Docker without elevation
    try {
        Add-LocalGroupMember -Group "docker-users" -Member $env:USERNAME -ErrorAction SilentlyContinue
    } catch { }
    $dockerVersion = try { docker --version } catch { "version check failed" }
    Write-Step "Installed Docker: $dockerVersion"
}
else {
    $dockerVersion = try { docker --version } catch { "version check failed" }
    Write-Step "Docker already present: $dockerVersion"
}

# ----------------------------------------------------------------------
# 3) Log in to ECR ------------------------------------------------------
# ----------------------------------------------------------------------
try {
    $loginPassword = aws ecr get-login-password --region us-east-1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to get ECR login password"
    }
    
    $loginPassword | docker login --username AWS --password-stdin 349514606126.dkr.ecr.us-east-1.amazonaws.com/myvisausa/crm-api
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to login to ECR"
    }
    
    Write-Step "ECR login complete."
} catch {
    Write-Error "ECR login failed: $($_.Exception.Message)"
    throw
}