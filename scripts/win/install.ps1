# Detect, (re)install, or upgrade Chocolatey and then install git.

# -------------------------------------------------------------------------------------
# ----------------------------- ENVIRONMENT VARIABLES ---------------------------------
# -------------------------------------------------------------------------------------
$tsAuthKey = $env:TAILSCALE_AUTHKEY
# --------------------------------

function Ensure-Chocolatey {
    # Try to locate choco.exe in the current PATH
    $chocoCmd = Get-Command choco.exe -ErrorAction SilentlyContinue
    if ($chocoCmd) {
        Write-Host "Chocolatey detected at $($chocoCmd.Source). Upgrading if necessary..."
        & $chocoCmd.Source upgrade chocolatey -y --no-progress
        return
    }

    # If choco.exe not found but the directory exists, assume a broken/partial install.
    $chocoDir = Join-Path $env:ProgramData "chocolatey"
    if (Test-Path $chocoDir) {
        Write-Warning "Chocolatey directory exists but choco.exe not found. Previous installation may be corrupted."
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $backupDir = "${chocoDir}_backup_$timestamp"
        Write-Host "Backing up existing Chocolatey directory to $backupDir"
        Move-Item -Path $chocoDir -Destination $backupDir -Force
    }

    # Fresh install
    Write-Host "Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

# Ensure Chocolatey is present and healthy
Ensure-Chocolatey

# Path to choco.exe (reliable even if current session PATH isn't updated yet)
$ChocoExe = Join-Path (Join-Path $env:ProgramData "chocolatey") "bin\choco.exe"

if (-not (Test-Path $ChocoExe)) {
    Throw "Chocolatey installation failed or choco.exe is missing at $ChocoExe"
}

# Install required packages
& $ChocoExe install git -y --no-progress
& $ChocoExe install nodejs-lts -y --no-progress
& $ChocoExe install tailscale -y --no-progress

# Refresh environment variables so the current session picks up any new PATH entries (npm, node, tailscale)
$ChocoInstallDir = $env:ChocolateyInstall
if (-not $ChocoInstallDir) {
    $ChocoInstallDir = Join-Path $env:ProgramData "chocolatey"
}
$refreshEnvCmd = Join-Path $ChocoInstallDir "bin\refreshenv.cmd"
if (Test-Path $refreshEnvCmd) {
    Write-Host "Refreshing environment variables..."
    & cmd /c $refreshEnvCmd
}

# ----------------------------------------------------------------------------
# Bring up Tailscale (if auth key provided)
# ----------------------------------------------------------------------------

$tailscaleCmd = Get-Command tailscale.exe -ErrorAction SilentlyContinue
if ($tailscaleCmd) {
    if ($tsAuthKey) {
        Write-Host "Starting Tailscale connection..."
        try {
            & $tailscaleCmd.Source up --authkey $tsAuthKey --accept-dns=true --accept-routes=true
        } catch {
            Write-Warning "'tailscale up' returned an error (possibly already logged in). Continuing..."
        }
    } else {
        Write-Warning "TAILSCALE_AUTHKEY environment variable not set; skipping 'tailscale up'."
    }
} else {
    Write-Warning "tailscale.exe not found in PATH after installation."
}
