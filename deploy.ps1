<#
Designed to automate the deployment and update of the Sandman API's
Flow is pull Repo to centralized location >  stop services > rename api to api.timestamp and copy data into new api folder > build pip env > start services>
only keep 3 api time stamp folders
#>

# Get Repo's from Git into array
$repos = @{
    "skynet"    = @{ url = "https://github.com/Chalk-Solutions/sandman-web-dashboard-backend.git" }
    "optimizer" = @{ url = "https://github.com/Chalk-Solutions/sandman-web-schedule-optimizer.git" }
    "eta"       = @{ url = "https://github.com/Chalk-Solutions/sandman-web-eta-engine.git" }
    "hyperloop" = @{ url = "https://github.com/Chalk-Solutions/sandman-web-hyperloop.git" }
}

#Hashtable to define source and destination directory
$deployMap = @{
    "skynet"    = @{ source = "C:\repo\skynet"; destination = "C:\skynet"; configPath = "dashboard" }
    "optimizer" = @{ source = "C:\repo\optimizer\cmstx_scheduleroptimizer_core"; destination = "C:\optimizer"; configPath = "" }
    "eta"       = @{ source = "C:\repo\eta"; destination = "C:\etaengine"; configPath = "" }
    "hyperloop" = @{ source = "C:\repo\hyperloop"; destination = "C:\hyperloop"; configPath = "" }
}

#ask for new install or update
#This matters later when pipenv is being installed or not

$installType = Read-Host "Install type? (new/update, default: update)"
if ([string]::IsNullOrWhiteSpace($installType)) { $installType = "update" }
$installType = $installType.Trim().ToLower()

# Verify and/or Create folders required if needed

$basePath = "C:\repo"
$repoDirs = @("optimizer", "hyperloop", "eta", "skynet")

if (-not (Test-Path $basePath)) {
    New-Item -ItemType Directory -Path $basePath
}

foreach ($dir in $repoDirs) {
    $fullPath = Join-Path $basePath $dir
    if (-not (Test-Path $fullPath)) {
        New-Item -ItemType Directory -Path $fullPath
    }
}

# Confirm API needing updated

Write-Host "Select API to update (comma-separated numbers, or 'all'):"

$repoKeys = $repos.Keys | Sort-Object
$i = 1
foreach ($repo in $repoKeys) {
    Write-Host "$i. $repo"
    $i++
}

$selectionInput = Read-Host "Selection (comma-separated numbers, or 'all')"

if ($selectionInput.Trim().ToLower() -eq "all") {
    $selectedRepos = $repoKeys
} else {
    $selectedRepos = $selectionInput.Split(",") | ForEach-Object {
        $index = [int]$_.Trim() - 1
        $repoKeys[$index]
    }
}

# Select Branch

$selectedBranches = @{}

foreach ($repo in $selectedRepos) {
    $url = $repos[$repo].url
    $remoteInfo = git ls-remote --symref $url HEAD
    $default = ($remoteInfo | Select-String "ref: refs/heads/(\S+)\s+HEAD" | ForEach-Object { $_.Matches.Groups[1].Value })
    
    if ([string]::IsNullOrWhiteSpace($default)) {
        $default = "main"
        Write-Host "WARNING: Could not detect default branch for $repo, falling back to 'main'"
    }

    $branchInput = Read-Host "Branch for $repo (default: $default, press Enter to accept)"
    $selectedBranches[$repo] = if ([string]::IsNullOrWhiteSpace($branchInput)) { $default } else { $branchInput }
}

<# Pull repo into c:\repo
if it exists, it will 
fetch current, 
resets (point at commit, removes anything staged and resets working tree to fit committ)
cleans (forces a removal of untracked git directories)
#>

foreach ($repo in $selectedRepos) {
    $repoPath = Join-Path $basePath $repo
    $url = $repos[$repo].url
    $branch = $selectedBranches[$repo]

    Write-Host "Pulling $repo branch: $branch"

   if (Test-Path (Join-Path $repoPath ".git")) {
    git -C $repoPath fetch origin
    git -C $repoPath reset --hard origin/$branch
    git -C $repoPath clean -fd
} else {
    git clone --branch $branch $url $repoPath
}

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Git operation failed for $repo. Aborting."
        exit 1
    }
}

#stopping services

$serviceMap = @{
    "skynet"    = @("sandman-skynet*", "sandman-live*")
    "optimizer" = @("sandman-optimizer*")
    "eta"       = @("sandman-eta*")
    "hyperloop" = @("sandman-hyperloop*")
}

foreach ($repo in $selectedRepos) {
    foreach ($pattern in $serviceMap[$repo]) {
        Get-Service $pattern | Stop-Service -Force
    }
}

stop-service w3svc -force


# After Stop-Service calls and stop-service w3svc -force
Write-Host "Waiting for processes to release handles..."
Start-Sleep -Seconds 10

# Force-kill any remaining python processes holding skynet paths if needed
Get-Process python -ErrorAction SilentlyContinue | Where-Object {
    $_.Modules.FileName -like "*skynet*"
} | Stop-Process -Force

# Rename current api folder
$timestamp = Get-Date -Format "MMddyyHHmm"

foreach ($repo in $selectedRepos) {
    $destination = $deployMap[$repo].destination
    $apiPath = Join-Path $destination "api"
    $archivePath = Join-Path $destination "api.$timestamp"

    if (Test-Path $apiPath) {
        try {
            Rename-Item -Path $apiPath -NewName "api.$timestamp" -ErrorAction Stop
            Write-Host "Archived $repo api to $archivePath"
        } catch {
            Write-Host "ERROR: Could not rename $apiPath - $_"
            Write-Host "Aborting deployment for $repo"
            start-service w3svc -force
            exit 1
        }
    } else {
        Write-Host "No existing api folder found for $repo, skipping archive"
    }
}

# Copy directory content from c:\repo to c:\*api*\api
# Copy config.ini out of archive

foreach ($repo in $selectedRepos) {
    $source = $deployMap[$repo].source
    $destination = $deployMap[$repo].destination
    $apiPath = Join-Path $destination "api"
    $archivePath = Join-Path $destination "api.$timestamp"

    # Create fresh api folder
    New-Item -ItemType Directory -Path $apiPath

    # Copy repo contents
    Copy-Item -Path "$source\*" -Destination $apiPath -Recurse -Force

    # Restore config.ini
    $configSubPath = $deployMap[$repo].configPath
    $configSource = if ($configSubPath) { Join-Path $archivePath "$configSubPath\config.ini" } else { Join-Path $archivePath "config.ini" }
    $configDest = if ($configSubPath) { Join-Path $apiPath "$configSubPath\config.ini" } else { Join-Path $apiPath "config.ini" }
    if (Test-Path $configSource) {
        Copy-Item -Path $configSource -Destination $configDest -Force
        Write-Host "Restored config.ini for $repo"
    } else {
        Write-Host "WARNING: No config.ini found in archive for $repo"
    }

    # Restore winsw
    $winswSource = Join-Path $archivePath "winsw"
    $winswDest = Join-Path $apiPath "winsw"
    if (Test-Path $winswSource) {
        Copy-Item -Path $winswSource -Destination $winswDest -Recurse -Force
        Write-Host "Restored winsw for $repo"
    } else {
        Write-Host "WARNING: No winsw found in archive for $repo"
    }

    # Pipenv or venv restore
    if ($installType -eq "new") {
        Set-Location $apiPath
        pipenv install
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: pipenv install failed for $repo. Aborting."
            exit 1
        }
    } else {
        $venvSource = Join-Path $archivePath ".venv"
        $venvDest = Join-Path $apiPath ".venv"
        if (Test-Path $venvSource) {
            Move-Item -Path $venvSource -Destination $venvDest -Recurse -Force
            Write-Host "Restored .venv for $repo"
        } else {
            Write-Host "WARNING: No .venv found in archive for $repo"
        }
    }
}


# Verify we are good to start services

$confirm = Read-Host "pipenv install complete. Start services? (y/n)"
if ($confirm.Trim().ToLower() -ne "y") {
    Write-Host "Aborting. Services not started."
    exit 0
}

# start all sandman services

Get-service *sandman* | Start-Service

# verify services running and provide log of failure

Write-Host "Waiting 15 seconds to verify services..."
Start-Sleep -Seconds 15

Write-Host "`n--- Deployment Health Report ---"

$failed = @()

Get-Service *sandman* | ForEach-Object {
    if ($_.Status -ne "Running") {
        $failed += $_.Name
    }
}

if ($failed.Count -eq 0) {
    Write-Host "All sandman services running."
    foreach ($repo in $selectedRepos) {
    $destination = $deployMap[$repo].destination

    $archives = Get-ChildItem -Path $destination -Directory -Filter "api.*" |
        Sort-Object Name -Descending

    if ($archives.Count -gt 3) {
        $archives | Select-Object -Skip 3 | ForEach-Object {
            Remove-Item -Path $_.FullName -Recurse -Force
            Write-Host "Removed old archive: $($_.FullName)"
        }
    }
}
} else {
    Write-Host "WARNING: The following services are not running:"
    foreach ($svc in $failed) {
        Write-Host "  $svc"
        
        # Strip sandman- prefix and map to log folder
        $logFolder = switch -Wildcard ($svc) {
            "*skynet*"    { "skynet" }
            "*optimizer*" { "optimizer" }
            "*eta*"       { "eta" }
            "*hyperloop*" { "hyperloop" }
            "*live*"      { "skynet" }
            default       { $null }
        }

        if ($logFolder) {
            $logPath = "C:\services\logs\$logFolder\$svc.err.log"
            if (Test-Path $logPath) {
                Write-Host "  Last 10 lines from $logPath :"
                Get-Content $logPath -Tail 10 | ForEach-Object { Write-Host "    $_" }
            } else {
                Write-Host "  Log not found: $logPath"
            }
        }
    }
}