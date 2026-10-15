# Fails fast on missing configuration before any expensive setup work runs.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

Write-Step 'Pre-flight validation'

# 1. The Tailscale key must exist. Failing here is cheap; failing after the app
#    installs would waste ten minutes of runner time.
if ([string]::IsNullOrWhiteSpace($env:TAILSCALE_AUTH_KEY)) {
    Write-Host '::error::TAILSCALE_AUTH_KEY secret is not set. Add it under Settings > Secrets and variables > Actions.' -ForegroundColor Red
    exit 1
}
Write-Ok 'TAILSCALE_AUTH_KEY secret is present'

# 2. Theme must be one of the supported values.
$theme = $env:THEME
if ($theme -notin @('dark', 'light')) {
    Write-Host "::error::Invalid theme '$theme'. Expected 'dark' or 'light'." -ForegroundColor Red
    exit 1
}
Write-Ok "Theme: $theme"

# 3. Clamp the session lifetime to 1-6 hours. Hosted runners cap jobs at 360
#    minutes, so the effective lifetime stops a few minutes short of it to allow
#    a graceful shutdown instead of a timeout failure.
$sessionHours = 5.9
if (-not [double]::TryParse($env:SESSION_HOURS, [ref]$sessionHours)) { $sessionHours = 5.9 }
$sessionHours = [Math]::Max(1, [Math]::Min($sessionHours, 6))
if ($sessionHours -gt 5.9) { $sessionHours = 5.9 }
Add-GithubEnv -Name 'SESSION_HOURS_EFFECTIVE' -Value "$sessionHours"
Write-Ok "Session lifetime: $sessionHours hours"

# 4. Validate the wallpaper early: download once to its final location and keep
#    it only if the response is really an image.
if ([string]::IsNullOrWhiteSpace($env:WALLPAPER_URL)) {
    Add-GithubEnv -Name 'WALLPAPER_FILE' -Value ''
    Write-Warn 'No wallpaper URL provided - the default desktop background will be kept.'
} else {
    $wallpaperFile = Join-Path $env:PUBLIC 'wallpaper.jpg'
    $response = Invoke-DownloadWithRetry -Uri $env:WALLPAPER_URL -OutFile $wallpaperFile -Attempts 2
    if ($null -ne $response -and (Test-ImageResponse $response)) {
        Add-GithubEnv -Name 'WALLPAPER_FILE' -Value $wallpaperFile
        Write-Ok 'Wallpaper URL is reachable and serves an image'
    } else {
        if (Test-Path $wallpaperFile) { Remove-Item -Path $wallpaperFile -Force }
        Add-GithubEnv -Name 'WALLPAPER_FILE' -Value ''
        Write-Warn 'Wallpaper URL is unreachable or does not serve an image - the default background will be kept.'
    }
}

exit 0
