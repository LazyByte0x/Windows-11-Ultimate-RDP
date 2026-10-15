# Shared helpers for the Ultimate RDP workflow scripts.
# Target runtime: PowerShell 7 (workflow steps use shell: pwsh).

Set-StrictMode -Version Latest

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "    OK: $Message" -ForegroundColor Green
}

function Write-Warn {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "    WARN: $Message" -ForegroundColor Yellow
}

function Add-GithubEnv {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value
    )
    # Add-Content with explicit UTF-8: the ">>" operator in Windows PowerShell writes UTF-16,
    # which corrupts GITHUB_ENV parsing. Keep this helper the only writer.
    Add-Content -Path $env:GITHUB_ENV -Value "$Name=$Value" -Encoding utf8
}

function New-RandomPassword {
    param([int]$Length = 20)
    # Ambiguous characters (l, I, 1, O, 0) are excluded because session users type these by hand.
    # The first character comes from letters only so the value can never start with '-' or '/'
    # and be mistaken for a flag by command-line tools such as net.exe.
    $letters = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ'
    $chars = "$letters" + '23456789!@#%^*-_=+'
    $bytes = [byte[]]::new($Length)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $first = $letters[$bytes[0] % $letters.Length]
    $rest = -join ($bytes | Select-Object -Skip 1 | ForEach-Object { $chars[$_ % $chars.Length] })
    return -join ($first, $rest)
}

function ConvertTo-SecurePassword {
    # The session password starts its life as plaintext by design: it is
    # generated here, displayed in the run Summary (the credential delivery
    # channel), and must be handed to the LocalAccounts cmdlets. The rule is
    # suppressed for this single, documented conversion point only.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    param([Parameter(Mandatory)][string]$Password)
    return ConvertTo-SecureString $Password -AsPlainText -Force
}

function Invoke-DownloadWithRetry {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$OutFile,
        [int]$Attempts = 3,
        [int]$TimeoutSec = 60
    )
    $response = $null
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $Uri -OutFile $OutFile -TimeoutSec $TimeoutSec `
                -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) UltimateRDP/7.4' -PassThru
            return $response
        } catch {
            Write-Warn "Download attempt $attempt/$Attempts for '$Uri' failed: $($_.Exception.Message)"
            if ($attempt -lt $Attempts) { Start-Sleep -Seconds (10 * $attempt) }
        }
    }
    return $null
}

function Test-ImageResponse {
    param([Parameter(Mandatory)]$Response)
    $contentType = ''
    if ($Response.Headers['Content-Type']) {
        $contentType = ($Response.Headers['Content-Type'] -join ';')
    }
    return ($contentType -match '^image/')
}

Export-ModuleMember -Function @(
    'Write-Step',
    'Write-Ok',
    'Write-Warn',
    'Add-GithubEnv',
    'New-RandomPassword',
    'ConvertTo-SecurePassword',
    'Invoke-DownloadWithRetry',
    'Test-ImageResponse'
)
