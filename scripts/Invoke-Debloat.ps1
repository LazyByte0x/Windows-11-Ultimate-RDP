# Removes consumer bloatware, disables telemetry services, and applies performance tweaks.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

Write-Step 'Debloating and optimizing Windows'

# Consumer bloatware. Missing packages are not an error - the image changes over time.
$packagePatterns = @(
    '*Microsoft.People*',
    '*Microsoft.Wallet*',
    '*Microsoft.ZuneMusic*',
    '*Microsoft.ZuneVideo*',
    '*Microsoft.XboxApp*',
    '*Microsoft.YourPhone*',
    '*Microsoft.WindowsFeedbackHub*',
    '*Microsoft.GetHelp*'
)
foreach ($pattern in $packagePatterns) {
    Get-AppxPackage -Name $pattern -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
}
Write-Ok 'Consumer bloatware removed'

foreach ($serviceName in @('DiagTrack', 'dmwappushservice')) {
    Set-Service -Name $serviceName -StartupType Disabled -ErrorAction SilentlyContinue
}
Write-Ok 'Telemetry services disabled'

# Activate the Ultimate Performance plan. The GUID is extracted with a regex
# because powercfg output formatting varies across images and locales.
powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 | Out-Null
$schemeLine = (powercfg /list) | Where-Object { $_ -like '*Ultimate*' } | Select-Object -First 1
if ($null -eq $schemeLine) { throw 'Ultimate Performance power plan not found after duplication.' }
$guidMatch = [regex]::Match($schemeLine, '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}')
if (-not $guidMatch.Success) { throw "Could not parse the Ultimate Performance plan GUID from: $schemeLine" }
powercfg /setactive $guidMatch.Value | Out-Null
Write-Ok "Ultimate Performance plan active ($($guidMatch.Value))"

# Disable mouse acceleration for raw pointer input.
Set-ItemProperty -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed' -Value '0'
Set-ItemProperty -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold1' -Value '0'
Set-ItemProperty -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold2' -Value '0'
Write-Ok 'Mouse acceleration disabled'

exit 0
