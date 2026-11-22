<#
.SYNOPSIS
Helper commands for testing M.A.N.T.A. with the manta-dora-test repository.

.EXAMPLES
  # 1) Create feature branch + Commit #1 and push (run AFTER GitHub webhook is active!)
  .\scripts\manta-test-helpers.ps1 -Action pr-commit-1

  # 2) After opening PR on GitHub, add Commit #2 to trigger push + pull_request(synchronize)
  .\scripts\manta-test-helpers.ps1 -Action pr-commit-2

  # 3) Check PostgreSQL commits, pull_requests.first_commit_at, deployments, DLQ
  .\scripts\manta-test-helpers.ps1 -Action db-check

  # 4) Send Production Health FAIL / PASS signals (for MTTR testing)
  .\scripts\manta-test-helpers.ps1 -Action health-fail -ProjectId "<UUID>" -HealthSecret "<SECRET>"
  .\scripts\manta-test-helpers.ps1 -Action health-pass -ProjectId "<UUID>" -HealthSecret "<SECRET>"

  # 5) Send a poison webhook payload to test 5x retry + Dead Letters Queue (/dead-letters)
  .\scripts\manta-test-helpers.ps1 -Action send-poison-dlq
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("pr-commit-1", "pr-commit-2", "db-check", "health-fail", "health-pass", "send-poison-dlq")]
    [string]$Action,

    [string]$BranchName = "test/dora-lead-time-pr",
    [string]$ApiBaseUrl = "http://localhost:8000",
    [string]$TenantId = "11111111-1111-1111-1111-111111111111",
    [string]$ProjectId = "",
    [string]$HealthSecret = ""
)

$ErrorActionPreference = "Stop"

switch ($Action) {
    "pr-commit-1" {
        git checkout main
        git pull origin main
        git checkout -b $BranchName
        $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        Add-Content -Path "docs\test-log.md" -Value "`n- [$ts] Commit #1 on $BranchName (initial feature commit)"
        git add docs\test-log.md
        git commit -m "docs: first commit for DORA lead time test ($ts)"
        git push -u origin $BranchName
        Write-Host "`nDone! Now open a Pull Request on GitHub from '$BranchName' into 'main'." -ForegroundColor Green
    }

    "pr-commit-2" {
        $currentBranch = (git rev-parse --abbrev-ref HEAD).Trim()
        if ($currentBranch -eq "main") {
            throw "Switch to your feature branch first (e.g. git checkout $BranchName)."
        }
        $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        Add-Content -Path "docs\test-log.md" -Value "- [$ts] Commit #2 on $currentBranch (PR synchronize test)"
        git add docs\test-log.md
        git commit -m "docs: second commit on open PR ($ts)"
        git push
        Write-Host "`nDone! Check GitHub Recent Deliveries and run '-Action db-check' before merging the PR." -ForegroundColor Green
    }

    "db-check" {
        $sql = @"
\echo '=== RECENT WEBHOOK EVENTS ==='
SELECT id, provider, event_type, status, attempts, left(coalesce(error_message, ''), 60) AS err, received_at
FROM webhook_events ORDER BY received_at DESC LIMIT 10;

\echo '=== RECENT COMMITS ==='
SELECT left(sha, 10) AS sha_short, pull_request_id, authored_at, left(author_pseudonym_id, 16) AS author_pseudo
FROM commits ORDER BY created_at DESC LIMIT 10;

\echo '=== PULL REQUESTS (check first_commit_at BEFORE merging!) ==='
SELECT external_pr_number AS pr_num, left(title, 35) AS title, state, first_commit_at, merged_at, left(coalesce(merge_commit_sha, ''), 10) AS merge_sha
FROM pull_requests ORDER BY created_at DESC LIMIT 5;

\echo '=== DEPLOYMENTS ==='
SELECT id, environment, status, is_change_failure, authoritative_signal_source, left(commit_sha, 10) AS sha_short, deployed_at
FROM deployments ORDER BY deployed_at DESC LIMIT 10;

\echo '=== DEPLOYMENT <-> PR LINKS ==='
SELECT deployment_id, pull_request_id FROM deployment_pull_requests ORDER BY created_at DESC LIMIT 10;

\echo '=== PRODUCTION FAILURES (MTTR) ==='
SELECT id, status, probe_source, started_at, resolved_at, recovery_time_seconds
FROM production_failures ORDER BY created_at DESC LIMIT 5;

\echo '=== DEAD LETTER EVENTS ==='
SELECT id, provider, error_class, total_attempts, is_resolved, quarantined_at
FROM dead_letter_events ORDER BY quarantined_at DESC LIMIT 5;
"@
        $sql | docker exec -i manta_postgres psql -U manta_user -d manta_db
    }

    "health-fail" {
        if (-not $ProjectId -or -not $HealthSecret) {
            throw "Provide -ProjectId '<PROJECT_UUID>' and -HealthSecret '<PLAINTEXT_SECRET>'."
        }
        $uri = "$($ApiBaseUrl.TrimEnd('/'))/api/v1/webhooks/projects/$ProjectId/health"
        $resp = Invoke-RestMethod -Method Post -Uri $uri `
            -Headers @{ "X-Webhook-Secret" = $HealthSecret } `
            -ContentType "application/json" `
            -Body '{"status":"FAIL","probe_source":"webhook","severity":"SEV-1"}'
        $resp | ConvertTo-Json -Depth 5
    }

    "health-pass" {
        if (-not $ProjectId -or -not $HealthSecret) {
            throw "Provide -ProjectId '<PROJECT_UUID>' and -HealthSecret '<PLAINTEXT_SECRET>'."
        }
        $uri = "$($ApiBaseUrl.TrimEnd('/'))/api/v1/webhooks/projects/$ProjectId/health"
        $resp = Invoke-RestMethod -Method Post -Uri $uri `
            -Headers @{ "X-Webhook-Secret" = $HealthSecret } `
            -ContentType "application/json" `
            -Body '{"status":"PASS","probe_source":"webhook"}'
        $resp | ConvertTo-Json -Depth 5
    }

    "send-poison-dlq" {
        $uri = "$($ApiBaseUrl.TrimEnd('/'))/api/v1/webhooks/github"
        $deliveryId = [guid]::NewGuid().ToString()
        $resp = Invoke-RestMethod -Method Post -Uri $uri `
            -Headers @{
                "X-GitHub-Event" = "push"
                "X-GitHub-Delivery" = $deliveryId
                "X-Tenant-ID" = $TenantId
            } `
            -ContentType "application/json" `
            -Body '{"ref":"refs/heads/main","repository":"poison-test-payload"}'
        $resp | ConvertTo-Json -Depth 5
        Write-Host "`nPoison event queued (delivery=$deliveryId). Wait ~35 seconds (5 retries: 2+4+8+16s), then open /dead-letters." -ForegroundColor Yellow
    }
}
