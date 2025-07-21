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

    Write-Step "Installed Tailscale: $(tailscale version)"
} else {
    Write-Step "Tailscale already present: $(tailscale version)"
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
tailscale status > $null 2>&1
if ($LASTEXITCODE -eq 0 -and (tailscale status) -notmatch 'Logged out') {
    Write-Step "Tailscale already connected to tailnet."
}
else {
    Write-Step "Tailscale is not logged in – attempting login…"
    if ($env:TAILSCALE_AUTHKEY) {
        Write-Step "Using provided TAILSCALE_AUTHKEY."
        tailscale up --authkey $env:TAILSCALE_AUTHKEY
    } else {
        Write-Step "No TAILSCALE_AUTHKEY provided. Launching interactive login…"
        tailscale up
    }
}

# ----------------------------------------------------------------------
# 4) Display Tailscale IP address(es)
# ----------------------------------------------------------------------
$ips = tailscale ip --4
Write-Step "Tailscale IPv4 address(es) for this node: $ips"