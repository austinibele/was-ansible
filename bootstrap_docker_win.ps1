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
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {  #  [oai_citation:0‡Microsoft for Developers](https://devblogs.microsoft.com/scripting/use-a-powershell-function-to-see-if-a-command-exists/?utm_source=chatgpt.com)
    Write-Step "AWS CLI not found – installing…"
    $msi = "$env:TEMP\AWSCLIV2.msi"
    Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile $msi  #  [oai_citation:1‡AWS Documentation](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html?utm_source=chatgpt.com)
    Start-Process msiexec.exe -Wait -ArgumentList "/i `"$msi`" /qn"
    Remove-Item $msi -Force
    Write-Step "Installed AWS CLI: $(aws --version 2>&1)"
} else {
    Write-Step "AWS CLI already present: $(aws --version 2>&1)"
}

# ----------------------------------------------------------------------
# 2) Install (or repair) Docker ----------------------------------------
# ----------------------------------------------------------------------
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {  #  [oai_citation:2‡Microsoft for Developers](https://devblogs.microsoft.com/scripting/use-a-powershell-function-to-see-if-a-command-exists/?utm_source=chatgpt.com)
    Write-Step "Docker not found – installing…"

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        # winget ≥ 1.4 supports unattended licence acceptance
        winget install --id Docker.DockerDesktop -e `
                       --accept-package-agreements --accept-source-agreements  #  [oai_citation:3‡Microsoft Learn](https://learn.microsoft.com/en-us/windows/package-manager/winget/install?utm_source=chatgpt.com) [oai_citation:4‡Winget.run](https://winget.run/pkg/Docker/DockerDesktop?utm_source=chatgpt.com)
    }
    elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        choco install docker-desktop -y --no-progress                          #  [oai_citation:5‡Chocolatey Software](https://community.chocolatey.org/packages/docker-desktop?utm_source=chatgpt.com)
    }
    else {
        # Fallback: download current Docker Desktop installer and run it quietly
        $exe = "$env:TEMP\DockerDesktopInstaller.exe"
        Invoke-WebRequest -Uri "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe" -OutFile $exe  #  [oai_citation:6‡Docker Community Forums](https://forums.docker.com/t/unattended-installation-of-docker-desktop-which-parameters-can-be-used-besides-install-quiet/74081?utm_source=chatgpt.com)
        Start-Process $exe -Wait -ArgumentList "install --quiet"
        Remove-Item $exe -Force
    }

    # Ensure the invoking user can run Docker without elevation
    try {
        Add-LocalGroupMember -Group "docker-users" -Member $env:USERNAME -ErrorAction SilentlyContinue  #  [oai_citation:7‡GeeksforGeeks](https://www.geeksforgeeks.org/devops/add-myself-to-the-docker-users-group-on-windows/?utm_source=chatgpt.com) [oai_citation:8‡Stack Overflow](https://stackoverflow.com/questions/61530874/how-do-i-add-myself-to-the-docker-users-group-on-windows?utm_source=chatgpt.com)
    } catch { }
    Write-Step "Installed Docker: $(docker --version)"
}
else {
    Write-Step "Docker already present: $(docker --version)"
}

# ----------------------------------------------------------------------
# 3) Log in to ECR ------------------------------------------------------
# ----------------------------------------------------------------------
aws ecr get-login-password --region us-east-1 `                       #  [oai_citation:9‡AWS Documentation](https://docs.aws.amazon.com/cli/latest/reference/ecr/get-login-password.html?utm_source=chatgpt.com)
| docker login --username AWS --password-stdin  \
    349514606126.dkr.ecr.us-east-1.amazonaws.com/myvisausa/crm-api
Write-Step "ECR login complete."