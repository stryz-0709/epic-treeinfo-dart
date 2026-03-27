param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$GitArgs
)

$repoPath = Join-Path $PSScriptRoot "mobile\epic-treeinfo-dart"

if (-not (Test-Path $repoPath)) {
    Write-Error "V-Ranger repo path not found: $repoPath"
    exit 1
}

if (-not (Test-Path (Join-Path $repoPath ".git"))) {
    Write-Error "Not a Git repository: $repoPath"
    exit 1
}

if (-not $GitArgs -or $GitArgs.Count -eq 0) {
    git -C $repoPath status -sb
    exit $LASTEXITCODE
}

git -C $repoPath @GitArgs
exit $LASTEXITCODE
