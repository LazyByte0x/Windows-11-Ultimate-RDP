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

# One sequential retry per failure - MSI mutex contention and source races are
# the usual suspects, and they clear once the parallel batch has drained.
foreach ($appId in @($results.Keys | Where-Object { $results[$_] -ne 0 })) {
    $hex = '0x{0:x8}' -f ($results[$appId] -band 0xFFFFFFFF)
    Write-Warn "$appId failed in parallel (exit $hex). Retrying sequentially..."
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

$stillFailed = @($results.Keys | Where-Object { $results[$_] -ne 0 })
foreach ($appId in $stillFailed) {
    Write-Host "::error::$appId could not be installed. Inspect %TEMP%\winget-$appId.log on the runner." -ForegroundColor Red
}
Add-GithubEnv -Name 'APPS_FAILED' -Value ($stillFailed -join ', ')
if ($stillFailed.Count -gt 0) { exit 1 }
Write-Ok 'All bundle applications installed.'
