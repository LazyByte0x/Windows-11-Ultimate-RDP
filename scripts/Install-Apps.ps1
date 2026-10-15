# Installs the selected application bundle in parallel, with a sequential retry
# for anything that failed. The owning workflow step runs with continue-on-error
# so a failed package never blocks the session from coming up.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

Write-Step 'Installing the application bundle'

$bundleApps = @{
    all       = @('Google.Chrome', 'Valve.Steam', 'OBSProject.OBSStudio', 'Google.GoogleDrive', 'Rainmeter.Rainmeter')
    streaming = @('Google.Chrome', 'OBSProject.OBSStudio', 'Rainmeter.Rainmeter')
    minimal   = @('Google.Chrome')
}
$bundle = $env:APP_BUNDLE
if (-not $bundleApps.ContainsKey($bundle)) {
    Write-Host "::error::Unknown app bundle '$bundle'. Supported: all, streaming, minimal." -ForegroundColor Red
    exit 1
}
$apps = @($bundleApps[$bundle])
if ($apps.Count -eq 0) { Write-Ok 'Nothing to install.'; exit 0 }

# The msstore source sometimes prompts for agreements and is not needed here.
# Both source operations are cosmetic for this run, so failures only warn.
try { winget source remove msstore *> $null } catch { Write-Warn 'Could not remove the msstore source (non-fatal).' }
try { winget source update *> $null } catch { Write-Warn 'Could not update winget sources (non-fatal).' }

function Install-ChromeFromEnterpriseMsi {
    # winget's community manifest can lag behind Google's rolling installer
    # binary (APPINSTALLER_CLI_ERROR_INSTALLER_HASH_MISMATCH). The enterprise
    # MSI URL always serves the current stable build, so instead of a pinned
    # hash the integrity check here is the Authenticode signature chain.
    $msiFile = Join-Path $env:TEMP 'chrome-enterprise.msi'
    $response = Invoke-DownloadWithRetry -Uri 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi' -OutFile $msiFile
    if ($null -eq $response) { Write-Warn 'Chrome fallback: enterprise MSI download failed.'; return $false }

    $signature = Get-AuthenticodeSignature -FilePath $msiFile
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Google') {
        Write-Warn "Chrome fallback: signature verification failed ($($signature.Status) / $($signature.SignerCertificate.Subject))."
        return $false
    }
    Write-Ok "Chrome MSI signature verified: $($signature.SignerCertificate.Subject)"

    # 3010 = installed successfully, reboot pending - not a failure here.
    $msiExit = (Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', "`"$msiFile`"", '/qn', '/norestart') -Wait -PassThru).ExitCode
    if ($msiExit -eq 0 -or $msiExit -eq 3010) {
        Write-Ok 'Google Chrome installed from the signed enterprise MSI.'
        return $true
    }
    Write-Warn "Chrome fallback: msiexec exited with $msiExit."
    return $false
}

# Parallel installs. Each job writes winget output to its own log and returns
# only the exit code, keeping the job output parseable.
$jobs = @{}
foreach ($appId in $apps) {
    Write-Host "Launching parallel install: $appId"
    $jobs[$appId] = Start-Job -ScriptBlock {
        param($AppId)
        $log = Join-Path $env:TEMP "winget-$AppId.log"
        winget install --id=$AppId -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity *> $log
        Write-Output $LASTEXITCODE
    } -ArgumentList $appId
}

$results = @{}
foreach ($appId in $apps) {
    $exitCode = [int](Receive-Job -Job $jobs[$appId] -Wait)
    Remove-Job -Job $jobs[$appId] -Force
    $results[$appId] = $exitCode
}

# One sequential retry per failure, after refreshing the sources: manifest
# staleness (hash mismatch) and source races are the usual suspects, and both
# clear once a fresh manifest lands.
foreach ($appId in @($results.Keys | Where-Object { $results[$_] -ne 0 })) {
    $hex = '0x{0:x8}' -f ($results[$appId] -band 0xFFFFFFFF)
    Write-Warn "$appId failed in parallel (exit $hex). Refreshing sources and retrying sequentially..."
    try { winget source update *> $null } catch { }
    Start-Sleep -Seconds 15
    $log = Join-Path $env:TEMP "winget-$appId.log"
    winget install --id=$appId -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity *> $log
    $results[$appId] = $LASTEXITCODE
    if ($results[$appId] -eq 0) { Write-Ok "$appId installed on retry." }
}

# Bundle extras that depend on a successful base install.
if ($results.ContainsKey('Rainmeter.Rainmeter') -and $results['Rainmeter.Rainmeter'] -eq 0) {
    $mondFile = Join-Path $env:TEMP 'Mond.rmskin'
    $response = Invoke-DownloadWithRetry -Uri 'https://github.com/raiguard/Mond/releases/download/v3.4.0/Mond.v3.4.0.rmskin' -OutFile $mondFile
    $rainmeterExe = Join-Path $env:ProgramFiles 'Rainmeter\Rainmeter.exe'
    if ($null -ne $response -and (Test-Path $rainmeterExe)) {
        Start-Process -FilePath $rainmeterExe -ArgumentList @('!Install', "`"$mondFile`"") -Wait
        Write-Ok 'Rainmeter Mond skin installed.'
    } else {
        Write-Warn 'Mond skin skipped (download failed or Rainmeter missing).'
    }
}

if ($results.ContainsKey('OBSProject.OBSStudio') -and $results['OBSProject.OBSStudio'] -eq 0) {
    $profileDir = Join-Path $env:APPDATA 'obs-studio\basic\profiles\Untitled'
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    $obsConfig = @'
[General]
Name=Untitled
[Video]
BaseCX=1920
BaseCY=1080
OutputCX=1280
OutputCY=720
FPSCommon=30
[Output]
Mode=Simple
StreamEncoder=x264
RecFormat=mkv
RecQuality=Small
RecEncoder=x264
[AdvOut]
RecPreset=ultrafast
RecBitrate=2500
'@
    # Out-File with UTF-8 no BOM: OBS reads ini files as plain text.
    $obsConfig | Out-File -FilePath (Join-Path $profileDir 'basic.ini') -Encoding utf8NoBOM
    Write-Ok 'Lightweight OBS recording profile applied.'
}

# Chrome is part of every non-clean bundle and its winget manifest is the one
# most likely to trail Google's rolling builds - give it a direct fallback.
if ($results.ContainsKey('Google.Chrome') -and $results['Google.Chrome'] -ne 0) {
    Write-Warn 'winget could not install Google Chrome. Trying the signed Google enterprise MSI fallback...'
    if (Install-ChromeFromEnterpriseMsi) { $results['Google.Chrome'] = 0 }
}

$stillFailed = @($results.Keys | Where-Object { $results[$_] -ne 0 })
foreach ($appId in $stillFailed) {
    Write-Host "::error::$appId could not be installed. Last lines of the winget log:" -ForegroundColor Red
    $log = Join-Path $env:TEMP "winget-$appId.log"
    if (Test-Path $log) {
        Get-Content -Path $log -Tail 40 | ForEach-Object { Write-Host "    | $_" }
    } else {
        Write-Host '    | (no winget log found on the runner)'
    }
}
Add-GithubEnv -Name 'APPS_FAILED' -Value ($stillFailed -join ', ')
if ($stillFailed.Count -gt 0) { exit 1 }
Write-Ok 'All bundle applications installed.'

# Explicit exit 0: the Actions runner appends "exit $LASTEXITCODE" to pwsh
# steps, and the stale nonzero code from a failed winget attempt above would
# otherwise fail this step even when every app ended up installed.
exit 0
