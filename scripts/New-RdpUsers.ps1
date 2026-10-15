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

function Set-LocalUserPassword {
    param(
        [Parameter(Mandatory)][string]$UserName,
        [Parameter(Mandatory)][securestring]$Password
    )
    if (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue) {
        Set-LocalUser -Name $UserName -Password $Password
    } else {
        New-LocalUser -Name $UserName -Password $Password -AccountNeverExpires
        Set-LocalUser -Name $UserName -PasswordNeverExpires $true
    }
}

function Add-LocalGroupMemberSafe {
    param(
        [Parameter(Mandatory)][string]$GroupName,
        [Parameter(Mandatory)][string]$MemberName
    )
    $isMember = Get-LocalGroupMember -Group $GroupName -Member $MemberName -ErrorAction SilentlyContinue
    if (-not $isMember) {
        Add-LocalGroupMember -Group $GroupName -Member $MemberName
    }
}

# Per-run random credentials, rotated through the LocalAccounts cmdlets instead
# of net.exe: "net user /add" asks for Y/N confirmation on passwords longer than
# 14 characters (a legacy LM-hash prompt) and cannot get an answer in a
# non-interactive shell. The cmdlets have no such limit, so the 20-character
# passwords work as designed.
#
# The passwords are deliberately NOT registered with ::add-mask::: masking
# redacts the value everywhere it would be printed, including the job Summary
# page, which is the intended delivery channel for these credentials. The
# exposure model (visible to anyone who can view this repository's Actions
# runs, random per run, destroyed with the session) is documented in the README
# and in the Summary privacy note.

# Rotate the built-in runner admin password for this run only.
$adminPassword = New-RandomPassword
$adminPasswordSecure = ConvertTo-SecureString $adminPassword -AsPlainText -Force
Set-LocalUserPassword -UserName 'runneradmin' -Password $adminPasswordSecure
Add-GithubEnv -Name 'RDP_ADMIN_PASS' -Value $adminPassword
Write-Ok 'runneradmin password rotated'

# Dedicated session account with admin and RDP group membership.
$sessionPassword = New-RandomPassword
$sessionPasswordSecure = ConvertTo-SecureString $sessionPassword -AsPlainText -Force
Set-LocalUserPassword -UserName 'ditzz' -Password $sessionPasswordSecure
Add-LocalGroupMemberSafe -GroupName 'Administrators' -MemberName 'ditzz'
Add-LocalGroupMemberSafe -GroupName 'Remote Desktop Users' -MemberName 'ditzz'
Add-GithubEnv -Name 'RDP_SESSION_PASS' -Value $sessionPassword
Write-Ok "Session user 'ditzz' provisioned (Administrators + Remote Desktop Users)"
