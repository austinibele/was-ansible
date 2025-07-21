# -------------------------------------------------------------------------------------
# ----------------------------- ENVIRONMENT VARIABLES ---------------------------------
# -------------------------------------------------------------------------------------
$pat = $env:PAT

# ----------------------------------------------------------------------------
# Git global configuration (user info and auth rewrite)
# ----------------------------------------------------------------------------

git config --global user.email "austin.ibele@gmail.com"
git config --global user.name  "austinibele"

if ($pat) {
    $gitInsteadOfKey = "url.`"https://$pat@github.com/`".insteadOf"
    Write-Host "Configuring git to use PAT for github.com URLs..."
    git config --global $gitInsteadOfKey "https://github.com/"
} else {
    Write-Warning "PAT environment variable not set; skipping git credential rewrite."
}

# ----------------------------------------------------------------------------------
# Clone (or update) repository and run build/start
# ----------------------------------------------------------------------------------

$repoUrl  = "https://github.com/myvisausa/whatsapp-server.git"
$repoName = ($repoUrl.Split('/')[-1]).Replace('.git','')

# Determine base directory for cloning (prefer REPO_BASE_DIR env var, then USERPROFILE)
$baseDir = $env:REPO_BASE_DIR
if (-not $baseDir) { $baseDir = $env:USERPROFILE }
if (-not $baseDir) { $baseDir = (Get-Location) }
if (-not (Test-Path $baseDir)) { New-Item -ItemType Directory -Path $baseDir | Out-Null }

$repoDir = Join-Path $baseDir $repoName

Write-Host "Repository directory will be: $repoDir"

if (Test-Path $repoDir) {
    if (Test-Path (Join-Path $repoDir ".git")) {
        Write-Host "Repository already exists. Pulling latest changes..."
        git -C $repoDir pull --ff-only
    } else {
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $backupDir = "${repoDir}_backup_$timestamp"
        Write-Warning "Directory '$repoDir' exists but is not a git repository. Backing up to '$backupDir' and recloning."
        Move-Item -Path $repoDir -Destination $backupDir -Force
        git clone $repoUrl $repoDir
    }
} else {
    git clone $repoUrl $repoDir
}

# Enter the repository directory
Push-Location $repoDir

# Ensure npm is available
$npmCmd = Get-Command npm.cmd -ErrorAction SilentlyContinue
if (-not $npmCmd) {
    $possibleNpm = "C:\Program Files\nodejs\npm.cmd"
    if (Test-Path $possibleNpm) {
        $npmCmd = $possibleNpm
    } else {
        Throw "npm.cmd not found. Node.js installation may have failed."
    }
}

# Install dependencies, build, and start the application
Write-Host "Running 'npm install'..."
& $npmCmd install
if ($LASTEXITCODE -ne 0) { Throw "npm install failed." }

Write-Host "Running 'npm run build'..."
& $npmCmd run build
if ($LASTEXITCODE -ne 0) { Throw "npm run build failed." }

Write-Host "Running 'npm run start'..."
& $npmCmd run start

# Return to original location after script completes (if start exits)
Pop-Location
