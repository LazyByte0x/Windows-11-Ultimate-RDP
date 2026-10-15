# Publishes the session summary, then keeps the session alive with real health
# checks until the requested lifetime elapses. Ending this script ends the job,
# which destroys the environment - that is the intended graceful shutdown.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

$sessionHours = 5.9
if (-not [double]::TryParse($env:SESSION_HOURS_EFFECTIVE, [ref]$sessionHours) -or $sessionHours -le 0) {
    $sessionHours = 5.9
}
$deadline = (Get-Date).AddHours($sessionHours)
$endsAt = $deadline.ToString('yyyy-MM-dd HH:mm') + ' UTC'

# --- Session summary -----------------------------------------------------------
$failedApps = $env:APPS_FAILED
if ($env:APP_BUNDLE -eq 'clean') {
    $appsStatus = 'No applications installed (clean bundle).'
} elseif ([string]::IsNullOrWhiteSpace($failedApps)) {
    $appsStatus = "All applications from the '$($env:APP_BUNDLE)' bundle are installed."
} else {
    $appsStatus = "Bundle '$($env:APP_BUNDLE)' installed, but these failed: $failedApps. Check the install step log."
}

$summary = @"
# ✅ Your Ultimate RDP session is live

### Connect in three steps
1. Install the **Tailscale client** on your device and sign in to the same tailnet used for this workflow.
2. Open your RDP client (Windows: ``mstsc``) and connect to the address below.
3. Sign in with one of the accounts below.

| Property | Value |
|----------|-------|
| **Address (Tailscale IP)** | ``$($env:TAILSCALE_IP)`` |
| **Username 1** | ``runneradmin`` |
| **Password 1** | ``$($env:RDP_ADMIN_PASS)`` |
| **Username 2** | ``ditzz`` |
| **Password 2** | ``$($env:RDP_SESSION_PASS)`` |

### Session details
- **Theme:** $($env:THEME)
- **Applications:** $appsStatus
- **Ends at:** $endsAt - the environment is destroyed shortly after; store nothing here.

> ⚠️ **Privacy note:** these credentials are visible to anyone who can view this
> repository's Actions runs while the session is live. Run the workflow from a
> private fork if that matters to you.

### Common issues
| Symptom | Fix |
|---------|-----|
| Connection timed out | Confirm your Tailscale client is connected, and use the ``100.x.x.x`` IP above |
| No IP in the table | Reopen this Summary after the "Fetch Tailscale IP" step finishes |
| Session ended early | The chosen session lifetime elapsed - start a new run |
| Blank or slow desktop | First logon applies the profile; reconnect once, and expect 4 vCPU / 16 GB-class performance |
"@
Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $summary -Encoding utf8
Write-Ok 'Session summary published (see the Summary tab).'

# --- Health-checked keep-alive -------------------------------------------------
Write-Host "`nSession is live. Health checks run every 5 minutes." -ForegroundColor Green
while ($true) {
    $now = Get-Date
    if ($now -ge $deadline) { break }

    $tailscaleService = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
    $tailscaleOk = ($null -ne $tailscaleService -and $tailscaleService.Status -eq 'Running')
    $rdpListener = Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue
    $rdpOk = ($null -ne $rdpListener)

    if (-not ($tailscaleOk -and $rdpOk)) {
        Write-Host "::notice::Health deviation at $($now.ToString('HH:mm:ss')) - Tailscale service running: $tailscaleOk; RDP listener on 3389: $rdpOk"
    }
    $remaining = $deadline - $now
    Write-Host ("[{0:HH:mm:ss}] Session healthy - {1:00}h {2:00}m remaining." -f $now, [int][Math]::Floor($remaining.TotalHours), $remaining.Minutes)
    Start-Sleep -Seconds 300
}

Write-Host "`nSession window complete. Ending this job destroys the environment." -ForegroundColor Yellow
exit 0
