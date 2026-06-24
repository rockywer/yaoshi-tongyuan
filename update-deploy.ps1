Param(
    [switch]$Force,
    [switch]$PublishGhPages
)

Set-StrictMode -Version Latest

Write-Host "Starting update-deploy..."

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "git not found in PATH. Install git or run in an environment with git available."
    exit 1
}

# Ensure current branch (safe-guard)
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -ne 'main' -and -not $Force) {
    Write-Error "Current branch is '$branch'. Switch to 'main' or pass -Force to override."
    exit 1
}

Write-Host "Pulling latest changes from origin/$branch..."
git pull origin $branch

# Frontend build step if a web/ directory exists
$buildDir = $null
if (Test-Path "web") {
    Write-Host "Found 'web' directory — attempting frontend build if applicable."
    if (Test-Path "web/package.json") {
        Push-Location web
        if (Get-Command npm -ErrorAction SilentlyContinue) {
            Write-Host "Running npm install and npm run build..."
            npm install
            npm run build
        } else {
            Write-Host "npm not found; skipping frontend build."
        }
        Pop-Location
    } else {
        Write-Host "No package.json in web/; skipping frontend build."
    }

    # detect common build output folders
    $candidates = @("web/dist", "web/build", "web/public", "web/out")
    foreach ($c in $candidates) {
        if (Test-Path $c) { $buildDir = (Get-Item $c).FullName; break }
    }
    if (-not $buildDir) { Write-Host "No build output found in web/ (checked: $($candidates -join ', '))." }
    else { Write-Host "Detected build output: $buildDir" }
}

# If requested, publish to gh-pages
if ($PublishGhPages) {
    if (-not $buildDir) {
        Write-Error "Publish requested but no build output detected. Run build first."
        exit 1
    }

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("gh-pages-" + [System.Guid]::NewGuid().ToString())
    Write-Host "Preparing temporary worktree at $tempDir"

    try {
        git worktree add $tempDir gh-pages 2>$null
    } catch {
        Write-Host "Remote gh-pages branch may not exist; creating orphan gh-pages worktree."
        git worktree add -B gh-pages $tempDir
    }

    # Clean and copy
    Get-ChildItem -Path $tempDir -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item -Path (Join-Path $buildDir '*') -Destination $tempDir -Recurse -Force

    Push-Location $tempDir
    git add -A
    $has = git status --porcelain
    if ($has) {
        git commit -m "chore(deploy): publish to gh-pages [ci skip]" || Write-Host "Commit failed or nothing to commit."

        # Try to push without force; if non-fast-forward, attempt to pull and reconcile then push
        git push origin gh-pages
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Initial push failed (non-fast-forward). Attempting to fetch and rebase..."
            git fetch origin gh-pages
            git pull --rebase origin gh-pages
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Rebase failed. Manual intervention required to reconcile gh-pages."
                Pop-Location
                git worktree remove $tempDir -f
                exit 1
            }
            git push origin gh-pages
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Push still failed after rebase. Manual intervention required."
                Pop-Location
                git worktree remove $tempDir -f
                exit 1
            }
        }

        Write-Host "Published to gh-pages branch (no force push used)."
    } else {
        Write-Host "No changes to publish to gh-pages."
    }
    Pop-Location

    # remove worktree
    git worktree remove $tempDir -f
}

# Stage and commit any built/updated assets on main
git add -A
$status = git status --porcelain
if ($status) {
    Write-Host "Committing generated changes to $branch..."
    git commit -m "chore: update deployment artifacts"
    git push origin $branch
} else {
    Write-Host "No changes detected on $branch; nothing to commit."
}

Write-Host "update-deploy finished."
