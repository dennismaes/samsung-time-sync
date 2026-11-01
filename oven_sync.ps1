<#
  Samsung SmartThings oven time sync (Windows PowerShell 5.1+, nothing to install)

  First time:  double-click Setup.cmd
  Daily:       runs by itself as scheduled task "Oven time sync" (hidden, S4U)

  Manual use:
    oven_sync.ps1             set the oven time now (what the task runs)
    oven_sync.ps1 -Setup      setup wizard (also re-authorizes after a 30+ day break)
    oven_sync.ps1 -Install    (re)create the scheduled task only
    oven_sync.ps1 -Uninstall  remove the scheduled task
#>
param(
    [switch]$Setup,
    [switch]$Install,
    [switch]$Uninstall,
    [string]$User,        # used internally when -Install runs elevated
    [switch]$Elevated     # used internally
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Api         = 'https://api.smartthings.com'
$RedirectUri = 'https://httpbin.org/get'
$Scopes      = @('r:devices:*', 'x:devices:*')
$TaskName    = 'Oven time sync'
$ConfigPath  = Join-Path $PSScriptRoot 'oven_config.json'
$LogPath     = Join-Path $PSScriptRoot 'oven_sync.log'

# ------------------------------------------------------------------ helpers
function Write-Log([string]$Message) {
    $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Message
    Write-Host $Message
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
}

function Limit-Log {
    if (Test-Path $LogPath) {
        $lines = @(Get-Content $LogPath)
        if ($lines.Count -gt 1000) { $lines[-500..-1] | Set-Content $LogPath -Encoding UTF8 }
    }
}

function Invoke-Api {
    param([string]$Method, [string]$Uri, [hashtable]$Headers = @{}, $Body, [string]$ContentType)
    $params = @{ Method = $Method; Uri = $Uri; Headers = $Headers; UseBasicParsing = $true }
    if ($null -ne $Body) { $params.Body = $Body; $params.ContentType = $ContentType }
    for ($attempt = 1; ; $attempt++) {
        try {
            return Invoke-RestMethod @params
        } catch {
            if ($_.Exception.Response) {   # the server answered with an error
                $code = [int]$_.Exception.Response.StatusCode
                throw "HTTP $code from $Uri : $($_.ErrorDetails.Message)"
            }
            # no answer at all: PC may have just woken up, wait for the network
            if ($attempt -ge 5) { throw "No connection to SmartThings: $($_.Exception.Message)" }
            Start-Sleep -Seconds 30
        }
    }
}

function Read-Config {
    if (-not (Test-Path $ConfigPath)) { return $null }
    return Get-Content $ConfigPath -Raw | ConvertFrom-Json
}

function Save-Config($Config) {
    # write to a temp file first so a crash never leaves a half-written token
    $tmp = "$ConfigPath.tmp"
    $Config | ConvertTo-Json | Set-Content -Path $tmp -Encoding UTF8
    Move-Item -Path $tmp -Destination $ConfigPath -Force
}

function Get-Token($Config, [hashtable]$Form) {
    $Form.client_id = $Config.client_id
    $body = ($Form.GetEnumerator() | ForEach-Object {
        '{0}={1}' -f $_.Key, [uri]::EscapeDataString([string]$_.Value)
    }) -join '&'
    $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(
        "$($Config.client_id):$($Config.client_secret)"))
    $tok = Invoke-Api -Method Post -Uri "$Api/oauth/token" `
        -Headers @{ Authorization = "Basic $basic" } `
        -Body $body -ContentType 'application/x-www-form-urlencoded'
    if (-not $tok.refresh_token) { throw "Token response without refresh_token: $tok" }
    return $tok
}

# ------------------------------------------------------------------ daily run
function Invoke-Sync {
    $cfg = Read-Config
    if (-not $cfg -or -not $cfg.refresh_token) { throw "Not set up yet. Double-click Setup.cmd." }

    # A refresh returns a new access token AND a new refresh token.
    # Save the new refresh token immediately, before anything else.
    try {
        $tok = Get-Token $cfg @{ grant_type = 'refresh_token'; refresh_token = $cfg.refresh_token }
    } catch {
        throw "$_`nLogin expired or invalid? Run Setup.cmd again."
    }
    $cfg.refresh_token = $tok.refresh_token
    Save-Config $cfg

    # PC local time; invariant culture so ':' is never replaced by a locale separator
    $now = (Get-Date).ToString("yyyy-MM-dd'T'HH:mm:ss", [Globalization.CultureInfo]::InvariantCulture)
    $payload = @{
        commands = @(
            @{
                component  = 'main'
                capability = 'execute'
                command    = 'execute'
                arguments  = @('/configuration/vs/0', @{ 'x.com.samsung.da.currentTime' = $now })
            }
        )
    }
    Write-Log "Setting oven time to $now"
    $res = Invoke-Api -Method Post -Uri "$Api/v1/devices/$($cfg.device_id)/commands" `
        -Headers @{ Authorization = "Bearer $($tok.access_token)" } `
        -Body (ConvertTo-Json -InputObject $payload -Depth 10 -Compress) -ContentType 'application/json'
    Write-Log "OK: $(ConvertTo-Json -InputObject $res -Depth 10 -Compress)"
}

# ------------------------------------------------------------------ scheduled task
function Register-SyncTask([string]$ForUser) {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -WorkingDirectory $PSScriptRoot
    $trigger  = New-ScheduledTaskTrigger -Daily -At '03:05'   # just after a DST switch (03:00)
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    # S4U = "Run whether user is logged on or not" + "Do not store password":
    # runs in the background session, so no console window ever appears.
    $principal = New-ScheduledTaskPrincipal -UserId $ForUser -LogonType S4U -RunLevel Limited
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
        -Settings $settings -Principal $principal -Force | Out-Null
}

function Install-SyncTask {
    $me = "$env:USERDOMAIN\$env:USERNAME"
    try {
        Register-SyncTask $me
    } catch {
        Write-Host "Windows needs administrator approval to create a background task."
        Write-Host "Click 'Yes' in the prompt that appears..."
        $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"",
            '-Install', '-Elevated', '-User', "`"$me`"")
        if ($p.ExitCode -ne 0) { throw "Creating the scheduled task failed (see $LogPath)." }
    }
    if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
        throw "Scheduled task was not created."
    }
    Write-Log "Scheduled task '$TaskName' created: daily at 03:05, or at the next start-up if the PC was off."
}

# ------------------------------------------------------------------ setup wizard
function Invoke-Setup {
    Write-Host "== Samsung oven time sync: setup ==`n"
    $cfg = Read-Config

    if ($cfg -and $cfg.client_id -and $cfg.client_secret) {
        Write-Host "Reusing the SmartThings app from oven_config.json (client ID $($cfg.client_id))."
        Write-Host "(Delete oven_config.json to start completely fresh.)`n"
    } else {
        Write-Host "STEP 1/3: the SmartThings app"
        Write-Host "  [1] Create it automatically with a token from account.smartthings.com"
        Write-Host "  [2] I already created it with the SmartThings CLI (I have a Client ID + Secret)`n"
        $how = (Read-Host 'Choose 1 or 2').Trim()

        if ($how -eq '2') {
            $clientId     = (Read-Host 'Client ID').Trim()
            $clientSecret = (Read-Host 'Client Secret').Trim()
        } else {
            Write-Host "`n  a. Your browser opens https://account.smartthings.com/tokens"
            Write-Host "  b. Log in, click 'Generate new token', tick ALL boxes under 'Apps' and 'Devices'."
            Write-Host "  c. Copy the token. (It's only used right now; delete it afterwards if you like.)`n"
            Start-Process 'https://account.smartthings.com/tokens'
            $pat = (Read-Host 'Paste the token here').Trim()

            $suffix = -join ((97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
            $app = @{
                appName         = "oven-time-sync-$suffix"   # must be globally unique
                displayName     = 'Oven time sync'
                description     = 'Daily sync of the oven clock'
                appType         = 'API_ONLY'
                classifications = @('CONNECTED_SERVICE')
                singleInstance  = $true
                oauth           = @{
                    clientName   = 'Oven time sync'
                    scope        = $Scopes
                    redirectUris = @($RedirectUri)
                }
            }
            try {
                $res = Invoke-Api -Method Post -Uri "$Api/v1/apps" `
                    -Headers @{ Authorization = "Bearer $pat" } `
                    -Body (ConvertTo-Json -InputObject $app -Depth 10) -ContentType 'application/json'
            } catch {
                if ("$_" -match 'HTTP 40[13]') {
                    throw ("$_`n`nSmartThings refused to create the app with this token.`n" +
                           "Create it with the SmartThings CLI instead (see README, 'Plan B'),`n" +
                           "then run Setup.cmd again and choose option 2.")
                }
                throw
            }
            $clientId     = $res.oauthClientId
            $clientSecret = $res.oauthClientSecret
        }
        if (-not $clientId -or -not $clientSecret) { throw "Client ID or Secret is empty." }
        $cfg = [pscustomobject]@{
            client_id     = $clientId
            client_secret = $clientSecret
            refresh_token = $null
            device_id     = $null
        }
        Save-Config $cfg   # keep the secret even if the next step is interrupted
        Write-Host "App saved.`n"
    }

    Write-Host "STEP 2/3: allow access to your devices"
    $authUrl = "$Api/oauth/authorize?client_id=$($cfg.client_id)&response_type=code" +
               "&redirect_uri=$([uri]::EscapeDataString($RedirectUri))" +
               "&scope=$([uri]::EscapeDataString($Scopes -join ' '))"
    Write-Host "  a. Your browser opens the SmartThings login. Log in, pick your location, click Authorize."
    Write-Host "  b. You land on a page from httpbin.org. Copy the full URL from the address bar.`n"
    Start-Process $authUrl
    $pasted = (Read-Host 'Paste the URL here').Trim()
    $code = if ($pasted -match '[?&]code=([^&#]+)') { [uri]::UnescapeDataString($Matches[1]) } else { $pasted }

    $tok = Get-Token $cfg @{ grant_type = 'authorization_code'; code = $code; redirect_uri = $RedirectUri }
    $cfg.refresh_token = $tok.refresh_token
    Save-Config $cfg

    Write-Host "`nSTEP 3/3: pick your oven"
    $devices = @((Invoke-Api -Method Get -Uri "$Api/v1/devices" `
        -Headers @{ Authorization = "Bearer $($tok.access_token)" }).items)
    if ($devices.Count -eq 0) { throw "No devices found in this SmartThings account." }
    for ($i = 0; $i -lt $devices.Count; $i++) {
        $name = if ($devices[$i].label) { $devices[$i].label } else { $devices[$i].name }
        Write-Host ("  [{0}] {1}" -f $i, $name)
    }
    $choice = [int](Read-Host 'Number of your oven')
    $cfg.device_id = $devices[$choice].deviceId
    Save-Config $cfg

    Write-Host "`nTesting: setting the oven time now..."
    Invoke-Sync

    Write-Host "`nCreating the scheduled task..."
    Install-SyncTask

    Write-Host "`nAll done! The oven clock will now be synced daily. Log: $LogPath"
}

# ------------------------------------------------------------------ main
try {
    if ($Setup) {
        Invoke-Setup
    } elseif ($Install) {
        if ($User) { Register-SyncTask $User } else { Install-SyncTask }
    } elseif ($Uninstall) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Scheduled task '$TaskName' removed."
    } else {
        Limit-Log
        Invoke-Sync
    }
} catch {
    Write-Log "ERROR: $_"
    if ($Elevated) { Read-Host 'Press Enter to close' }
    exit 1
}
