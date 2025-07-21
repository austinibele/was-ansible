<#
.SYNOPSIS
    Windows analogue of the Linux Tailscale bootstrap script.
.DESCRIPTION
    * Installs (or verifies) Tailscale.
    * Ensures the "Tailscale" Windows service is running and set to Automatic.
    * Connects the node to a tailnet, using $env:TAILSCALE_AUTHKEY if present.
    * Prints the node's IPv4 address(es).
.NOTES
    Requires PowerShell 5+ and (initially) administrative rights.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step($Message) { Write-Host ">> $Message" }

# ----------------------------------------------------------------------
# 1) Install (or verify) Tailscale
# ----------------------------------------------------------------------
if (-not (Get-Command tailscale -ErrorAction SilentlyContinue)) {
    Write-Step "Tailscale not found – installing…"

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id Tailscale.Tailscale -e `
                       --accept-package-agreements --accept-source-agreements
    }
    elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        choco install tailscale -y --no-progress
    }
    else {
        $installer = "$env:TEMP\tailscale.exe"
        Invoke-WebRequest -Uri "https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe" `
                          -OutFile $installer
        Start-Process $installer -ArgumentList " /quiet" -Wait
        Remove-Item $installer -Force
    }

    $tailscaleVersion = try { tailscale version } catch { "version check failed" }
    Write-Step "Installed Tailscale: $tailscaleVersion"
} else {
    $tailscaleVersion = try { tailscale version } catch { "version check failed" }
    Write-Step "Tailscale already present: $tailscaleVersion"
}

# ----------------------------------------------------------------------
# 2) Ensure Tailscale Windows service is active
# ----------------------------------------------------------------------
$svc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
if (-not $svc) {
    throw "Tailscale service not found after installation."
}
if ($svc.Status -ne 'Running') {
    Write-Step "Starting Tailscale service…"
    Set-Service -Name 'Tailscale' -StartupType Automatic
    Start-Service -Name 'Tailscale'
} else {
    Write-Step "Tailscale service already running."
}

# ----------------------------------------------------------------------
# 3) Connect to tailnet
# ----------------------------------------------------------------------
try {
    $statusOutput = tailscale status 2>&1
    $statusExitCode = $LASTEXITCODE
} catch {
    $statusExitCode = 1
}

if ($statusExitCode -eq 0 -and $statusOutput -notmatch 'Logged out') {
    Write-Step "Tailscale already connected to tailnet."
}
else {
    Write-Step "Tailscale is not logged in – attempting login…"
    try {
        if ($env:TAILSCALE_AUTHKEY) {
            Write-Step "Using provided TAILSCALE_AUTHKEY."
            tailscale up --authkey $env:TAILSCALE_AUTHKEY
        } else {
            Write-Step "No TAILSCALE_AUTHKEY provided. Launching interactive login…"
            tailscale up
        }
        
        if ($LASTEXITCODE -ne 0) {
            throw "Tailscale login failed with exit code $LASTEXITCODE"
        }
    } catch {
        Write-Error "Failed to connect to Tailscale: $($_.Exception.Message)"
        throw
    }
}

# ----------------------------------------------------------------------
# 4) Display Tailscale IP address(es)
# ----------------------------------------------------------------------
try {
    $ips = tailscale ip --4
    if ($LASTEXITCODE -ne 0) {
        Write-Step "Unable to retrieve Tailscale IP address"
    } else {
        Write-Step "Tailscale IPv4 address(es) for this node: $ips"
    }
} catch {
    Write-Step "Unable to retrieve Tailscale IP address: $($_.Exception.Message)"
}