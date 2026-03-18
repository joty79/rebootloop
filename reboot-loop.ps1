[CmdletBinding(DefaultParameterSetName = 'Menu')]
param(
    [Parameter(ParameterSetName = 'Action')]
    [ValidateSet('Setup', 'Configure', 'Status', 'Disable', 'Remove', 'Loop')]
    [string]$Action,

    [Parameter(ParameterSetName = 'Action')]
    [switch]$DeleteFiles,

    [Parameter(ParameterSetName = 'Action')]
    [string]$TaskName = 'RebootLoop',

    [Parameter(ParameterSetName = 'Action')]
    [Nullable[int]]$StopTimeoutSeconds,

    [Parameter(ParameterSetName = 'Action')]
    [Nullable[int]]$ShutdownDelaySeconds,

    [Parameter(ParameterSetName = 'Action')]
    [Nullable[int]]$SignInGraceDelaySeconds
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $PSCommandPath
$managerPath = $PSCommandPath
$configPath = Join-Path $scriptRoot 'reboot-loop.config.json'
$disableFlagPath = Join-Path $scriptRoot 'reboot.disabled'
$winlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$defaultStopTimeoutSeconds = 60
$defaultShutdownDelaySeconds = 5
$defaultSignInGraceDelaySeconds = 8
$script:LoopStartupDelayApplied = $false

function Write-Rule {
    param(
        [ConsoleColor]$Color = [ConsoleColor]::DarkGray
    )

    Write-Host ('=' * 62) -ForegroundColor $Color
}

function Write-Banner {
    param(
        [string]$Title,
        [string]$Subtitle
    )

    Clear-Host
    Write-Rule -Color DarkCyan
    Write-Host ("  {0}" -f $Title) -ForegroundColor Cyan
    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
        Write-Host ("  {0}" -f $Subtitle) -ForegroundColor DarkGray
    }
    Write-Rule -Color DarkCyan
    Write-Host ''
}

function Write-Section {
    param(
        [string]$Title
    )

    Write-Host ("[{0}]" -f $Title) -ForegroundColor Yellow
}

function Write-InfoLine {
    param(
        [string]$Text
    )

    Write-Host ("  {0}" -f $Text) -ForegroundColor Gray
}

function Write-SuccessLine {
    param(
        [string]$Text
    )

    Write-Host ("  {0}" -f $Text) -ForegroundColor Green
}

function Write-WarningLine {
    param(
        [string]$Text
    )

    Write-Host ("  {0}" -f $Text) -ForegroundColor Yellow
}

function Write-ErrorLine {
    param(
        [string]$Text
    )

    Write-Host ("  {0}" -f $Text) -ForegroundColor Red
}

function Write-LabelValue {
    param(
        [string]$Label,
        [string]$Value,
        [ConsoleColor]$ValueColor = [ConsoleColor]::White
    )

    Write-Host ("  {0,-24}: " -f $Label) -NoNewline -ForegroundColor DarkGray
    Write-Host $Value -ForegroundColor $ValueColor
}

function Write-MenuItem {
    param(
        [string]$Number,
        [string]$Text
    )

    Write-Host ("  {0}. " -f $Number) -NoNewline -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor White
}

function Try-ActivateCurrentWindow {
    try {
        $wshell = New-Object -ComObject WScript.Shell
        $null = $wshell.AppActivate($PID)
    }
    catch {
    }
}

function Invoke-WindowAttention {
    param(
        [string]$WindowTitle
    )

    Try-ActivateCurrentWindow

    try {
        for ($attempt = 0; $attempt -lt 2; $attempt++) {
            [Console]::Beep(1100, 120)
            Start-Sleep -Milliseconds 80
            [Console]::Beep(1400, 120)
        }
    }
    catch {
    }

    try {
        $originalTitle = $host.UI.RawUI.WindowTitle
        for ($attempt = 0; $attempt -lt 2; $attempt++) {
            $host.UI.RawUI.WindowTitle = "$WindowTitle [ATTENTION]"
            Start-Sleep -Milliseconds 180
            $host.UI.RawUI.WindowTitle = $WindowTitle
            Start-Sleep -Milliseconds 120
        }
        $host.UI.RawUI.WindowTitle = $originalTitle
    }
    catch {
    }

    Try-ActivateCurrentWindow
}

function Test-IsGitRepoFolder {
    $gitMetadataPath = Join-Path $scriptRoot '.git'
    return (Test-Path $gitMetadataPath)
}

function Wait-ForEnter {
    while ($true) {
        $keyInfo = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        if ($keyInfo.VirtualKeyCode -eq 13) {
            return
        }
    }
}

function Read-StartNowDecision {
    while ($true) {
        $keyInfo = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        switch ($keyInfo.VirtualKeyCode) {
            13 { return 'StartNow' }
            27 { return 'Cancel' }
            default {
                [console]::Beep(900, 120)
            }
        }
    }
}

function Read-DeleteFolderDecision {
    while ($true) {
        $keyInfo = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        switch ($keyInfo.VirtualKeyCode) {
            89 { return 'DeleteFolder' }
            78 { return 'KeepFolder' }
            13 { return 'KeepFolder' }
            27 { return 'KeepFolder' }
            default {
                [console]::Beep(900, 120)
            }
        }
    }
}

function Read-LoopDecision {
    param(
        [int]$StopTimeoutSeconds
    )

    $countdownTop = [Console]::CursorTop
    $countdownWidth = [Math]::Max(30, $Host.UI.RawUI.WindowSize.Width - 1)
    [Console]::CursorVisible = $false

    try {
        for ($remainingSeconds = $StopTimeoutSeconds; $remainingSeconds -ge 0; $remainingSeconds--) {
            [Console]::SetCursorPosition(0, $countdownTop)
            $countdownText = ("  Auto reboot in {0,3} seconds. Press Esc to cancel." -f $remainingSeconds)
            Write-Host ($countdownText.PadRight($countdownWidth)) -NoNewline -ForegroundColor Cyan

            $targetTime = [DateTime]::UtcNow.AddSeconds(1)
            while ([DateTime]::UtcNow -lt $targetTime) {
                if ([Console]::KeyAvailable) {
                    $keyInfo = [Console]::ReadKey($true)
                    switch ($keyInfo.Key) {
                        'Escape' {
                            Write-Host ''
                            return 'OpenMenu'
                        }
                        'Enter' {
                            Write-Host ''
                            return 'RebootNow'
                        }
                    }
                }

                Start-Sleep -Milliseconds 50
            }
        }
    }
    finally {
        [Console]::CursorVisible = $true
    }

    Write-Host ''
    return 'RebootNow'
}

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-QualifiedUserName {
    $currentIdentityName = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $identityParts = $currentIdentityName -split '\\', 2

    if ($identityParts.Count -eq 2) {
        return @{
            Domain = $identityParts[0]
            User = $identityParts[1]
        }
    }

    return @{
        Domain = $env:COMPUTERNAME
        User = $env:USERNAME
    }
}

function Get-RebootConfiguration {
    if (-not (Test-Path $configPath)) {
        return @{
            StopTimeoutSeconds = $defaultStopTimeoutSeconds
            ShutdownDelaySeconds = $defaultShutdownDelaySeconds
            SignInGraceDelaySeconds = $defaultSignInGraceDelaySeconds
            Exists = $false
        }
    }

    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    return @{
        StopTimeoutSeconds = [int]$config.StopTimeoutSeconds
        ShutdownDelaySeconds = [int]$config.ShutdownDelaySeconds
        SignInGraceDelaySeconds = if ($null -ne $config.SignInGraceDelaySeconds) { [int]$config.SignInGraceDelaySeconds } else { $defaultSignInGraceDelaySeconds }
        Exists = $true
    }
}

function Assert-PositiveInteger {
    param(
        [Nullable[int]]$Value,
        [string]$Name,
        [int]$Minimum,
        [int]$Maximum
    )

    if ($null -eq $Value) {
        return
    }

    if ($Value -lt $Minimum -or $Value -gt $Maximum) {
        throw "$Name must be between $Minimum and $Maximum."
    }
}

function Save-RebootConfiguration {
    param(
        [int]$ResolvedStopTimeoutSeconds,
        [int]$ResolvedShutdownDelaySeconds,
        [int]$ResolvedSignInGraceDelaySeconds
    )

    [pscustomobject]@{
        StopTimeoutSeconds = $ResolvedStopTimeoutSeconds
        ShutdownDelaySeconds = $ResolvedShutdownDelaySeconds
        SignInGraceDelaySeconds = $ResolvedSignInGraceDelaySeconds
    } |
        ConvertTo-Json |
        Set-Content -Path $configPath -Encoding ASCII
}

function Read-IntegerPrompt {
    param(
        [string]$Prompt,
        [int]$DefaultValue,
        [int]$Minimum,
        [int]$Maximum
    )

    while ($true) {
        $inputText = Read-Host "$Prompt [$DefaultValue]"
        if ([string]::IsNullOrWhiteSpace($inputText)) {
            return $DefaultValue
        }

        $parsedValue = 0
        if ([int]::TryParse($inputText, [ref]$parsedValue) -and $parsedValue -ge $Minimum -and $parsedValue -le $Maximum) {
            return $parsedValue
        }

        Write-Warning "Enter a number between $Minimum and $Maximum."
    }
}

function Resolve-RebootConfiguration {
    param(
        [Nullable[int]]$RequestedStopTimeoutSeconds,
        [Nullable[int]]$RequestedShutdownDelaySeconds,
        [Nullable[int]]$RequestedSignInGraceDelaySeconds,
        [switch]$PromptForMissingValues
    )

    Assert-PositiveInteger -Value $RequestedStopTimeoutSeconds -Name 'StopTimeoutSeconds' -Minimum 5 -Maximum 3600
    Assert-PositiveInteger -Value $RequestedShutdownDelaySeconds -Name 'ShutdownDelaySeconds' -Minimum 0 -Maximum 3600
    Assert-PositiveInteger -Value $RequestedSignInGraceDelaySeconds -Name 'SignInGraceDelaySeconds' -Minimum 0 -Maximum 300

    $currentConfig = Get-RebootConfiguration
    $resolvedStopTimeoutSeconds = $RequestedStopTimeoutSeconds
    $resolvedShutdownDelaySeconds = $RequestedShutdownDelaySeconds
    $resolvedSignInGraceDelaySeconds = $RequestedSignInGraceDelaySeconds

    if ($null -eq $resolvedStopTimeoutSeconds) {
        if ($PromptForMissingValues) {
            $resolvedStopTimeoutSeconds = Read-IntegerPrompt -Prompt 'Seconds to wait before auto rebooting' -DefaultValue $currentConfig.StopTimeoutSeconds -Minimum 5 -Maximum 3600
        }
        else {
            $resolvedStopTimeoutSeconds = $currentConfig.StopTimeoutSeconds
        }
    }

    if ($null -eq $resolvedShutdownDelaySeconds) {
        if ($PromptForMissingValues) {
            $resolvedShutdownDelaySeconds = Read-IntegerPrompt -Prompt 'Shutdown delay after choosing reboot' -DefaultValue $currentConfig.ShutdownDelaySeconds -Minimum 0 -Maximum 3600
        }
        else {
            $resolvedShutdownDelaySeconds = $currentConfig.ShutdownDelaySeconds
        }
    }

    if ($null -eq $resolvedSignInGraceDelaySeconds) {
        if ($PromptForMissingValues) {
            $resolvedSignInGraceDelaySeconds = Read-IntegerPrompt -Prompt 'Seconds to wait after sign-in before countdown starts' -DefaultValue $currentConfig.SignInGraceDelaySeconds -Minimum 0 -Maximum 300
        }
        else {
            $resolvedSignInGraceDelaySeconds = $currentConfig.SignInGraceDelaySeconds
        }
    }

    return @{
        StopTimeoutSeconds = [int]$resolvedStopTimeoutSeconds
        ShutdownDelaySeconds = [int]$resolvedShutdownDelaySeconds
        SignInGraceDelaySeconds = [int]$resolvedSignInGraceDelaySeconds
    }
}

function Get-ScheduledTaskInfo {
    param(
        [string]$ScheduledTaskName
    )

    try {
        return Get-ScheduledTask -TaskName $ScheduledTaskName -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Get-PreferredPowerShellExe {
    $pwshCommand = Get-Command 'pwsh.exe' -ErrorAction SilentlyContinue
    if ($null -ne $pwshCommand -and -not [string]::IsNullOrWhiteSpace($pwshCommand.Source)) {
        return $pwshCommand.Source
    }

    $windowsPowerShellCommand = Get-Command 'powershell.exe' -ErrorAction SilentlyContinue
    if ($null -ne $windowsPowerShellCommand -and -not [string]::IsNullOrWhiteSpace($windowsPowerShellCommand.Source)) {
        return $windowsPowerShellCommand.Source
    }

    throw 'Neither pwsh.exe nor powershell.exe was found on this system.'
}

function Get-SelfElevationArguments {
    param(
        [AllowEmptyString()]
        [string]$RequestedAction,
        [switch]$UseDeleteFiles,
        [string]$ScheduledTaskName,
        [Nullable[int]]$RequestedStopTimeoutSeconds,
        [Nullable[int]]$RequestedShutdownDelaySeconds,
        [Nullable[int]]$RequestedSignInGraceDelaySeconds
    )

    $argumentList = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        ('"{0}"' -f $managerPath)
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedAction)) {
        $argumentList += '-Action'
        $argumentList += $RequestedAction
    }

    if ($UseDeleteFiles) {
        $argumentList += '-DeleteFiles'
    }

    if ($ScheduledTaskName -ne 'RebootLoop') {
        $argumentList += '-TaskName'
        $argumentList += ('"{0}"' -f $ScheduledTaskName)
    }

    if ($null -ne $RequestedStopTimeoutSeconds) {
        $argumentList += '-StopTimeoutSeconds'
        $argumentList += $RequestedStopTimeoutSeconds
    }

    if ($null -ne $RequestedShutdownDelaySeconds) {
        $argumentList += '-ShutdownDelaySeconds'
        $argumentList += $RequestedShutdownDelaySeconds
    }

    if ($null -ne $RequestedSignInGraceDelaySeconds) {
        $argumentList += '-SignInGraceDelaySeconds'
        $argumentList += $RequestedSignInGraceDelaySeconds
    }

    return ($argumentList -join ' ')
}

function Ensure-Elevated {
    param(
        [string]$RequestedAction,
        [switch]$UseDeleteFiles,
        [string]$ScheduledTaskName,
        [Nullable[int]]$RequestedStopTimeoutSeconds,
        [Nullable[int]]$RequestedShutdownDelaySeconds,
        [Nullable[int]]$RequestedSignInGraceDelaySeconds
    )

    if (Test-IsAdministrator) {
        return
    }

    $elevationArgs = Get-SelfElevationArguments `
        -RequestedAction $RequestedAction `
        -UseDeleteFiles:$UseDeleteFiles `
        -ScheduledTaskName $ScheduledTaskName `
        -RequestedStopTimeoutSeconds $RequestedStopTimeoutSeconds `
        -RequestedShutdownDelaySeconds $RequestedShutdownDelaySeconds `
        -RequestedSignInGraceDelaySeconds $RequestedSignInGraceDelaySeconds

    $powerShellExe = Get-PreferredPowerShellExe
    Start-Process -FilePath $powerShellExe -ArgumentList $elevationArgs -Verb RunAs | Out-Null
    exit 0
}

function Invoke-Loop {
    $currentConfig = Get-RebootConfiguration

    try {
        $host.UI.RawUI.WindowTitle = 'BSOD BOOT TEST'
    }
    catch {
    }

    if (Test-Path $disableFlagPath) {
        Write-Banner -Title 'BSOD BOOT TEST IS STOPPED' -Subtitle 'The stop flag is active, so no reboot will happen.'
        Write-Section 'Next Step'
        Write-InfoLine 'Run reboot-loop.ps1 and choose Start BSOD boot test to enable it again.'
        Start-Sleep -Seconds 5
        return
    }

    if (-not $script:LoopStartupDelayApplied) {
        $script:LoopStartupDelayApplied = $true
        Invoke-WindowAttention -WindowTitle 'BSOD BOOT TEST'

        if ($currentConfig.SignInGraceDelaySeconds -gt 0) {
            Write-Banner -Title 'BSOD BOOT TEST' -Subtitle 'Waiting for Windows to settle after sign-in'
            Write-Section 'Startup Delay'
            Write-InfoLine 'This short delay helps the window appear cleanly and gives it a better chance to grab attention.'
            Write-LabelValue -Label 'Delay' -Value ("{0} seconds" -f $currentConfig.SignInGraceDelaySeconds) -ValueColor Cyan
            Write-Host ''

            $delayTop = [Console]::CursorTop
            $delayWidth = [Math]::Max(40, $Host.UI.RawUI.WindowSize.Width - 1)
            for ($remainingDelay = $currentConfig.SignInGraceDelaySeconds; $remainingDelay -ge 1; $remainingDelay--) {
                [Console]::SetCursorPosition(0, $delayTop)
                $delayText = ("  Countdown starts in {0,3} seconds..." -f $remainingDelay)
                Write-Host ($delayText.PadRight($delayWidth)) -NoNewline -ForegroundColor DarkGray
                Start-Sleep -Seconds 1
            }

            Write-Host ''
        }

        Invoke-WindowAttention -WindowTitle 'BSOD BOOT TEST'
    }

    Write-Banner -Title 'BSOD BOOT TEST' -Subtitle 'Automatic reboot cycle after sign-in'
    Write-Section 'Status'
    Write-LabelValue -Label 'Launch source' -Value 'Task Scheduler after sign-in'
    Write-LabelValue -Label 'Sign-in delay' -Value ("{0} seconds" -f $currentConfig.SignInGraceDelaySeconds) -ValueColor Cyan
    Write-LabelValue -Label 'Stop window' -Value ("{0} seconds" -f $currentConfig.StopTimeoutSeconds) -ValueColor Cyan
    Write-LabelValue -Label 'Shutdown delay' -Value ("{0} seconds" -f $currentConfig.ShutdownDelaySeconds) -ValueColor Cyan
    Write-Host ''
    Write-Section 'Controls'
    Write-SuccessLine 'Press Enter to reboot immediately.'
    Write-WarningLine 'Press Esc to cancel this reboot and open the menu.'
    Write-InfoLine 'If no key is pressed, the PC will reboot automatically.'
    Write-Host ''
    $loopDecision = Read-LoopDecision -StopTimeoutSeconds $currentConfig.StopTimeoutSeconds

    if ($loopDecision -eq 'OpenMenu') {
        Write-Host ''
        Write-Banner -Title 'REBOOT CANCELED FOR NOW' -Subtitle 'The current reboot was canceled. Choose what to do next.'
        Invoke-MenuSession -IncludeReturnToCountdown
        return
    }

    Write-Host ''
    Write-SuccessLine ("Initiating reboot in {0} seconds..." -f $currentConfig.ShutdownDelaySeconds)
    & shutdown.exe /r /t $currentConfig.ShutdownDelaySeconds /f | Out-Null
}

function Invoke-Setup {
    param(
        [string]$ScheduledTaskName,
        [Nullable[int]]$RequestedStopTimeoutSeconds,
        [Nullable[int]]$RequestedShutdownDelaySeconds,
        [Nullable[int]]$RequestedSignInGraceDelaySeconds
    )

    $resolvedConfig = Resolve-RebootConfiguration `
        -RequestedStopTimeoutSeconds $RequestedStopTimeoutSeconds `
        -RequestedShutdownDelaySeconds $RequestedShutdownDelaySeconds `
        -RequestedSignInGraceDelaySeconds $RequestedSignInGraceDelaySeconds `
        -PromptForMissingValues

    Ensure-Elevated `
        -RequestedAction 'Setup' `
        -ScheduledTaskName $ScheduledTaskName `
        -RequestedStopTimeoutSeconds $resolvedConfig.StopTimeoutSeconds `
        -RequestedShutdownDelaySeconds $resolvedConfig.ShutdownDelaySeconds `
        -RequestedSignInGraceDelaySeconds $resolvedConfig.SignInGraceDelaySeconds

    $userInfo = Get-QualifiedUserName
    $qualifiedUserName = '{0}\{1}' -f $userInfo.Domain, $userInfo.User

    Write-Banner -Title 'START BSOD BOOT TEST' -Subtitle 'Setup for AutoLogon and Scheduled Task'
    Write-Section 'Account'
    Write-LabelValue -Label 'User' -Value $qualifiedUserName -ValueColor Cyan
    Write-InfoLine 'Enter the local account password once for Windows AutoLogon.'
    Write-InfoLine 'If this local account has no password, just press Enter.'
    Write-LabelValue -Label 'AutoLogon mode' -Value 'Persistent until stopped' -ValueColor Yellow
    Write-Host ''

    $securePassword = Read-Host "Enter the Windows password for $qualifiedUserName" -AsSecureString
    $passwordPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)

    try {
        $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPtr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPtr)
    }

    if ($null -eq $plainPassword) {
        $plainPassword = ''
    }

    Save-RebootConfiguration `
        -ResolvedStopTimeoutSeconds $resolvedConfig.StopTimeoutSeconds `
        -ResolvedShutdownDelaySeconds $resolvedConfig.ShutdownDelaySeconds `
        -ResolvedSignInGraceDelaySeconds $resolvedConfig.SignInGraceDelaySeconds

    New-ItemProperty -Path $winlogonPath -Name 'AutoAdminLogon' -PropertyType String -Value '1' -Force | Out-Null
    New-ItemProperty -Path $winlogonPath -Name 'DefaultUserName' -PropertyType String -Value $userInfo.User -Force | Out-Null
    New-ItemProperty -Path $winlogonPath -Name 'DefaultDomainName' -PropertyType String -Value $userInfo.Domain -Force | Out-Null
    New-ItemProperty -Path $winlogonPath -Name 'DefaultPassword' -PropertyType String -Value $plainPassword -Force | Out-Null
    Remove-ItemProperty -Path $winlogonPath -Name 'AutoLogonCount' -ErrorAction SilentlyContinue

    Remove-Item -Path $disableFlagPath -Force -ErrorAction SilentlyContinue

    $taskArguments = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        ('"{0}"' -f $managerPath)
        '-Action'
        'Loop'
    ) -join ' '

    $powerShellExe = Get-PreferredPowerShellExe
    $taskAction = New-ScheduledTaskAction -Execute $powerShellExe -Argument $taskArguments
    $taskTrigger = New-ScheduledTaskTrigger -AtLogOn -User $qualifiedUserName
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId $qualifiedUserName -LogonType Interactive -RunLevel Highest
    $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -StartWhenAvailable

    Unregister-ScheduledTask -TaskName $ScheduledTaskName -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $ScheduledTaskName -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Settings $taskSettings -Description 'Runs reboot-loop.ps1 at logon for reboot loop testing.' -Force | Out-Null

    Write-Host ''
    Write-Section 'Setup Complete'
    Write-SuccessLine 'Everything is configured.'
    Write-LabelValue -Label 'Scheduled Task' -Value $ScheduledTaskName -ValueColor Cyan
    Write-LabelValue -Label 'Script' -Value $managerPath -ValueColor Cyan
    Write-LabelValue -Label 'Sign-in delay' -Value ("{0} seconds" -f $resolvedConfig.SignInGraceDelaySeconds) -ValueColor Cyan
    Write-LabelValue -Label 'Stop window' -Value ("{0} seconds" -f $resolvedConfig.StopTimeoutSeconds) -ValueColor Cyan
    Write-LabelValue -Label 'Shutdown delay' -Value ("{0} seconds" -f $resolvedConfig.ShutdownDelaySeconds) -ValueColor Cyan
    Write-LabelValue -Label 'AutoLogon' -Value 'Enabled until you stop the test' -ValueColor Yellow
    Write-LabelValue -Label 'PowerShell host' -Value $powerShellExe -ValueColor Cyan
    if ([string]::IsNullOrEmpty($plainPassword)) {
        Write-WarningLine 'Blank local-account password detected. AutoLogon was configured with an empty password.'
    }
    Write-Host ''
    Write-Section 'What Happens Next'
    Write-InfoLine 'After the next sign-in, you will see this script window again.'
    Write-InfoLine 'It stays visible on purpose so you can cancel the reboot with Esc and open the menu.'
    Write-InfoLine 'From now on, the PC should continue the test without more input until you stop it.'
    Write-Host ''
    Write-Section 'Confirm'
    Write-SuccessLine 'Press Enter to reboot now and start the test.'
    Write-WarningLine 'Press Esc to cancel for now.'
    Write-Host ''

    $startNowDecision = Read-StartNowDecision

    if ($startNowDecision -eq 'StartNow') {
        Write-Host ''
        Write-SuccessLine ("Rebooting in {0} seconds to start the test..." -f $resolvedConfig.ShutdownDelaySeconds)
        & shutdown.exe /r /t $resolvedConfig.ShutdownDelaySeconds /f | Out-Null
        return
    }

    if ($startNowDecision -eq 'Cancel') {
        Write-Host ''
        Write-SuccessLine 'Setup is complete.'
        Write-InfoLine 'The reboot loop will start the next time you reboot or sign out and sign back in.'
        return
    }

    throw "Unexpected setup decision value: $startNowDecision"
}

function Invoke-Disable {
    param(
        [string]$ScheduledTaskName
    )

    Ensure-Elevated -RequestedAction 'Disable' -ScheduledTaskName $ScheduledTaskName

    Set-Content -Path $disableFlagPath -Value 'disabled' -Encoding ASCII
    Unregister-ScheduledTask -TaskName $ScheduledTaskName -Confirm:$false -ErrorAction SilentlyContinue

    New-ItemProperty -Path $winlogonPath -Name 'AutoAdminLogon' -PropertyType String -Value '0' -Force | Out-Null
    Remove-ItemProperty -Path $winlogonPath -Name 'DefaultPassword' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $winlogonPath -Name 'AutoLogonCount' -ErrorAction SilentlyContinue

    Write-Banner -Title 'BOOT TEST STOPPED' -Subtitle 'The reboot loop has been disabled.'
    Write-SuccessLine 'AutoLogon has been turned off and the scheduled task was removed.'
    Write-LabelValue -Label 'Disable flag' -Value $disableFlagPath -ValueColor Cyan
}

function Invoke-Configure {
    param(
        [Nullable[int]]$RequestedStopTimeoutSeconds,
        [Nullable[int]]$RequestedShutdownDelaySeconds,
        [Nullable[int]]$RequestedSignInGraceDelaySeconds
    )

    $resolvedConfig = Resolve-RebootConfiguration `
        -RequestedStopTimeoutSeconds $RequestedStopTimeoutSeconds `
        -RequestedShutdownDelaySeconds $RequestedShutdownDelaySeconds `
        -RequestedSignInGraceDelaySeconds $RequestedSignInGraceDelaySeconds `
        -PromptForMissingValues

    Save-RebootConfiguration `
        -ResolvedStopTimeoutSeconds $resolvedConfig.StopTimeoutSeconds `
        -ResolvedShutdownDelaySeconds $resolvedConfig.ShutdownDelaySeconds `
        -ResolvedSignInGraceDelaySeconds $resolvedConfig.SignInGraceDelaySeconds

    Write-Banner -Title 'TIMERS UPDATED' -Subtitle 'The next reboot cycle will use the new values.'
    Write-LabelValue -Label 'Sign-in delay' -Value ("{0} seconds" -f $resolvedConfig.SignInGraceDelaySeconds) -ValueColor Cyan
    Write-LabelValue -Label 'Stop window' -Value ("{0} seconds" -f $resolvedConfig.StopTimeoutSeconds) -ValueColor Cyan
    Write-LabelValue -Label 'Shutdown delay' -Value ("{0} seconds" -f $resolvedConfig.ShutdownDelaySeconds) -ValueColor Cyan
}

function Invoke-Remove {
    param(
        [switch]$RemoveFiles,
        [string]$ScheduledTaskName,
        [switch]$PromptForDeleteFolder
    )

    Ensure-Elevated -RequestedAction 'Remove' -UseDeleteFiles:$RemoveFiles -ScheduledTaskName $ScheduledTaskName

    Invoke-Disable -ScheduledTaskName $ScheduledTaskName

    if (-not $RemoveFiles) {
        Write-Host ''
        Write-Banner -Title 'CLEANUP COMPLETE' -Subtitle 'The tool has been disabled but the folder is still present.'

        if ($PromptForDeleteFolder) {
            Write-Section 'Folder Cleanup'
            Write-WarningLine 'Press Y to delete this folder too.'
            Write-InfoLine 'Press N, Enter, or Esc to keep the folder.'
            Write-Host ''

            $deleteFolderDecision = Read-DeleteFolderDecision
            if ($deleteFolderDecision -eq 'DeleteFolder') {
                $RemoveFiles = $true
            }
            else {
                Write-InfoLine 'Folder kept in place.'
                return
            }
        }
        else {
            Write-InfoLine 'Re-run with -Action Remove -DeleteFiles to remove the folder contents too.'
            return
        }
    }

    if (Test-IsGitRepoFolder) {
        Write-Host ''
        Write-Banner -Title 'FOLDER DELETE BLOCKED' -Subtitle 'This folder looks like a git repo/worktree, so automatic deletion was skipped.'
        Write-WarningLine 'The boot-test cleanup is complete, but the folder was intentionally kept.'
        Write-LabelValue -Label 'Folder' -Value $scriptRoot -ValueColor Cyan
        return
    }

    $cleanupScriptPath = Join-Path $env:TEMP ("remove-reboot-loop-{0}.cmd" -f [guid]::NewGuid().Guid)
    $cleanupScriptLines = @(
        '@echo off',
        'cd /d "%TEMP%"',
        'timeout /t 2 /nobreak >nul',
        ('rmdir /s /q "{0}"' -f $scriptRoot),
        ':retry',
        ('if exist "{0}" (' -f $scriptRoot),
        '    timeout /t 2 /nobreak >nul',
        ('    rmdir /s /q "{0}"' -f $scriptRoot),
        ('    if exist "{0}" goto retry' -f $scriptRoot),
        ')',
        'del /f /q "%~f0"'
    )

    Set-Content -Path $cleanupScriptPath -Value $cleanupScriptLines -Encoding ASCII
    Set-Location $env:TEMP
    Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$cleanupScriptPath`"" -WindowStyle Hidden

    Write-Host ''
    Write-Banner -Title 'FOLDER REMOVAL SCHEDULED' -Subtitle 'Cleanup is complete and deletion will finish from %TEMP%.'
    Write-LabelValue -Label 'Folder' -Value $scriptRoot -ValueColor Cyan
}

function Invoke-Status {
    param(
        [string]$ScheduledTaskName
    )

    $currentConfig = Get-RebootConfiguration
    $taskInfo = Get-ScheduledTaskInfo -ScheduledTaskName $ScheduledTaskName
    $autoLogonEnabled = $false

    try {
        $autoLogonEnabled = ((Get-ItemProperty -Path $winlogonPath -Name 'AutoAdminLogon' -ErrorAction Stop).AutoAdminLogon -eq '1')
    }
    catch {
        $autoLogonEnabled = $false
    }

    Write-Banner -Title 'CURRENT BSOD BOOT TEST STATUS' -Subtitle 'Quick health check for the configured test.'
    Write-LabelValue -Label 'Task name' -Value $ScheduledTaskName -ValueColor Cyan
    Write-LabelValue -Label 'Scheduled task' -Value ([bool]($null -ne $taskInfo)) -ValueColor Cyan
    Write-LabelValue -Label 'Disable flag' -Value (Test-Path $disableFlagPath) -ValueColor Cyan
    Write-LabelValue -Label 'AutoLogon enabled' -Value $autoLogonEnabled -ValueColor Cyan
    Write-LabelValue -Label 'Sign-in delay' -Value ("{0} seconds" -f $currentConfig.SignInGraceDelaySeconds) -ValueColor Cyan
    Write-LabelValue -Label 'Stop window' -Value ("{0} seconds" -f $currentConfig.StopTimeoutSeconds) -ValueColor Cyan
    Write-LabelValue -Label 'Shutdown delay' -Value ("{0} seconds" -f $currentConfig.ShutdownDelaySeconds) -ValueColor Cyan
    Write-LabelValue -Label 'Config file' -Value $configPath -ValueColor Cyan
    Write-LabelValue -Label 'Manager path' -Value $managerPath -ValueColor Cyan
}

function Get-MenuSelection {
    param(
        [switch]$IncludeReturnToCountdown
    )

    Write-Banner -Title 'BSOD BOOT TEST MANAGER' -Subtitle 'One file for setup, loop control, timers, and cleanup'
    Write-Section 'Menu'
    Write-MenuItem -Number '1' -Text 'Start BSOD boot test'
    Write-MenuItem -Number '2' -Text 'Show current status'
    Write-MenuItem -Number '3' -Text 'Stop reboot test'
    Write-MenuItem -Number '4' -Text 'Stop and clean up'
    if ($IncludeReturnToCountdown) {
        Write-MenuItem -Number '5' -Text 'Return to reboot countdown'
    }
    Write-Host ''
    Write-InfoLine 'Tip: option 1 asks for the reboot timers during setup.'
    Write-Host ''

    $selectionPrompt = if ($IncludeReturnToCountdown) { 'Choose 1-5' } else { 'Choose 1-4' }
    $selection = Read-Host $selectionPrompt
    switch ($selection) {
        '1' { return @{ Action = 'Setup'; DeleteFiles = $false; PromptForDeleteFolder = $false } }
        '2' { return @{ Action = 'Status'; DeleteFiles = $false; PromptForDeleteFolder = $false } }
        '3' { return @{ Action = 'Disable'; DeleteFiles = $false; PromptForDeleteFolder = $false } }
        '4' { return @{ Action = 'Remove'; DeleteFiles = $false; PromptForDeleteFolder = $true } }
        '5' {
            if ($IncludeReturnToCountdown) {
                return @{ Action = 'Loop'; DeleteFiles = $false; PromptForDeleteFolder = $false }
            }
        }
        default {
            if ($IncludeReturnToCountdown) {
                throw 'Invalid selection. Use 1, 2, 3, 4, or 5.'
            }

            throw 'Invalid selection. Use 1, 2, 3, or 4.'
        }
    }
}

function Invoke-SelectedAction {
    param(
        [string]$SelectedAction,
        [switch]$SelectedDeleteFiles,
        [switch]$SelectedPromptForDeleteFolder,
        [Nullable[int]]$SelectedStopTimeoutSeconds,
        [Nullable[int]]$SelectedShutdownDelaySeconds,
        [Nullable[int]]$SelectedSignInGraceDelaySeconds
    )

    switch ($SelectedAction) {
        'Setup' {
            Invoke-Setup `
                -ScheduledTaskName $TaskName `
                -RequestedStopTimeoutSeconds $SelectedStopTimeoutSeconds `
                -RequestedShutdownDelaySeconds $SelectedShutdownDelaySeconds `
                -RequestedSignInGraceDelaySeconds $SelectedSignInGraceDelaySeconds
        }
        'Configure' {
            Invoke-Configure `
                -RequestedStopTimeoutSeconds $SelectedStopTimeoutSeconds `
                -RequestedShutdownDelaySeconds $SelectedShutdownDelaySeconds `
                -RequestedSignInGraceDelaySeconds $SelectedSignInGraceDelaySeconds
        }
        'Status' {
            Invoke-Status -ScheduledTaskName $TaskName
        }
        'Disable' {
            Invoke-Disable -ScheduledTaskName $TaskName
        }
        'Remove' {
            Invoke-Remove -RemoveFiles:$SelectedDeleteFiles -ScheduledTaskName $TaskName -PromptForDeleteFolder:$SelectedPromptForDeleteFolder
        }
        'Loop' {
            Invoke-Loop
        }
    }
}

function Invoke-MenuSession {
    param(
        [switch]$IncludeReturnToCountdown
    )

    while ($true) {
        $menuSelection = Get-MenuSelection -IncludeReturnToCountdown:$IncludeReturnToCountdown
        Invoke-SelectedAction `
            -SelectedAction $menuSelection.Action `
            -SelectedDeleteFiles:$menuSelection.DeleteFiles `
            -SelectedPromptForDeleteFolder:$menuSelection.PromptForDeleteFolder `
            -SelectedStopTimeoutSeconds $StopTimeoutSeconds `
            -SelectedShutdownDelaySeconds $ShutdownDelaySeconds `
            -SelectedSignInGraceDelaySeconds $SignInGraceDelaySeconds

        if ($menuSelection.Action -eq 'Loop') {
            return
        }

        if ($menuSelection.Action -in @('Setup', 'Disable', 'Remove')) {
            return
        }

        Write-Host ''
        Write-InfoLine 'Press Enter to return to the menu.'
        Wait-ForEnter
    }
}

if ($PSCmdlet.ParameterSetName -eq 'Menu') {
    Ensure-Elevated -RequestedAction '' -ScheduledTaskName $TaskName
    Invoke-MenuSession
    return
}

switch ($Action) {
    'Setup' {
        Invoke-SelectedAction -SelectedAction 'Setup' -SelectedStopTimeoutSeconds $StopTimeoutSeconds -SelectedShutdownDelaySeconds $ShutdownDelaySeconds -SelectedSignInGraceDelaySeconds $SignInGraceDelaySeconds
    }
    'Configure' {
        Invoke-SelectedAction -SelectedAction 'Configure' -SelectedStopTimeoutSeconds $StopTimeoutSeconds -SelectedShutdownDelaySeconds $ShutdownDelaySeconds -SelectedSignInGraceDelaySeconds $SignInGraceDelaySeconds
    }
    'Status' { Invoke-SelectedAction -SelectedAction 'Status' }
    'Disable' { Invoke-SelectedAction -SelectedAction 'Disable' }
    'Remove' { Invoke-SelectedAction -SelectedAction 'Remove' -SelectedDeleteFiles:$DeleteFiles }
    'Loop' { Invoke-SelectedAction -SelectedAction 'Loop' }
}
