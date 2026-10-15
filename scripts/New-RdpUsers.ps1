# Enables RDP and provisions the two session accounts with per-run random passwords.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

Write-Step 'Configuring the RDP service and session users'

Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0 -Force
try {
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction Stop
} catch {
    # The group display name is locale-dependent; fall back to the rule names
    # used on the English runner image.
    Get-NetFirewallRule -Name 'RemoteDesktop-*' -ErrorAction SilentlyContinue | Enable-NetFirewallRule
}
# Network Level Authentication is the platform default; make it explicit so the
# listener never regresses to pre-authentication access.
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 1 -Force
Write-Ok 'RDP listener enabled with Network Level Authentication'

# Rotate the built-in runner admin password for this run only.
$adminPassword = New-RandomPassword
Add-LogMask $adminPassword
$adminOutput = net user 'runneradmin' $adminPassword
if ($LASTEXITCODE -ne 0) { throw "Failed to rotate the runneradmin password: $adminOutput" }
Add-GithubEnv -Name 'RDP_ADMIN_PASS' -Value $adminPassword
Write-Ok 'runneradmin password rotated and masked in logs'

# Dedicated session account with admin and RDP group membership.
$sessionPassword = New-RandomPassword
Add-LogMask $sessionPassword
$createOutput = net user 'ditzz' $sessionPassword /add /fullname:'Session User'
if ($LASTEXITCODE -ne 0) { throw "Failed to create the session user: $createOutput" }
Set-LocalUser -Name 'ditzz' -PasswordNeverExpires $true
$adminGroupOutput = net localgroup 'Administrators' 'ditzz' /add
if ($LASTEXITCODE -ne 0) { throw "Failed to add 'ditzz' to Administrators: $adminGroupOutput" }
$rdpGroupOutput = net localgroup 'Remote Desktop Users' 'ditzz' /add
if ($LASTEXITCODE -ne 0) { throw "Failed to add 'ditzz' to Remote Desktop Users: $rdpGroupOutput" }
Add-GithubEnv -Name 'RDP_SESSION_PASS' -Value $sessionPassword
Write-Ok "Session user 'ditzz' created (Administrators + Remote Desktop Users)"
