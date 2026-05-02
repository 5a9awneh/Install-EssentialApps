#Requires -RunAsAdministrator

# Generic prompt function
function Get-UserInput {
    param (
        [string]$Prompt,
        [string]$DefaultAnswer,
        [int]$Timeout
    )
    Write-Host "$Prompt (default: $DefaultAnswer)" -ForegroundColor Yellow
    $answer = $DefaultAnswer
    $startTime = Get-Date
    while ((Get-Date) -lt $startTime.AddSeconds($Timeout)) {
        $countdown = [math]::Round($Timeout - (Get-Date).Subtract($startTime).TotalSeconds)
        Write-Host "`rRespond in $countdown seconds... (y/n)" -ForegroundColor Yellow -NoNewline
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.KeyChar -eq 'y' -or $key.KeyChar -eq 'n') {
                $answer = $key.KeyChar
                break
            }
            else {
                Write-Host "`nInvalid response. Please enter 'y' or 'n'."
            }
        }
        Start-Sleep -Milliseconds 100
    }
    Write-Host "`n"
    return $answer
}

# Function to test if a path exists
function Test-PathExists {
    param ([string]$Path)
    if (!(Test-Path -Path $Path)) {
        throw "File not found: $Path"
    }
}

# Logging
$LogFile = Join-Path $PSScriptRoot 'Install-EssentialApps.log'
function Write-Log {
    param ([string]$Message)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $Message" | Add-Content -Path $LogFile
}

# Trim log entries older than 90 days
function Invoke-LogRotation {
    if (!(Test-Path $LogFile)) { return }
    $cutoff = (Get-Date).AddDays(-90)
    $kept = Get-Content $LogFile | Where-Object {
        if ($_ -match '^\d{4}-\d{2}-\d{2}') {
            try { [datetime]::ParseExact($_.Substring(0, 19), 'yyyy-MM-dd HH:mm:ss', $null) -ge $cutoff }
            catch { $true }
        }
        else { $true }
    }
    $kept | Set-Content $LogFile
}

# Define the applications to install
$applications = @(
    @{Name = "Acrobat Reader"; Path = "Software\Essentials\AcroRdrDC_en_US.exe"; Args = "/sPB" },
    @{Name = "Google Chrome"; Path = "Software\Essentials\ChromeStandaloneSetup64.exe"; Args = "/silent /install" },
    @{Name = "Teams"; Path = "Software\Essentials\teamsbootstrapper.exe"; Args = "-p -o `"$(Join-Path -Path $PSScriptRoot -ChildPath 'Software\Essentials\MSTeams-x64.msix')`"" },
    @{Name = "K-Lite Codec Pack"; Path = "Software\Essentials\K-Lite_Codec_Pack_Standard.exe"; Args = "/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /LOADINF=`"$(Join-Path -Path $PSScriptRoot -ChildPath 'Software\Essentials\klcp_standard_unattended.ini')`"" },
    @{Name = "7-Zip"; Path = "Software\Essentials\7z-x64.exe"; Args = "/S" },
    @{Name = "Microsoft Office 365"; Path = "Software\Essentials\Office365\_Office365-64\setup.exe"; Args = "/configure `"$(Join-Path -Path $PSScriptRoot -ChildPath 'Software\Essentials\Office365\_Office365-64\_installOfficeProPlus64.xml')`"" },
    @{Name = "Azure Information Protection Viewer"; Path = "Software\Essentials\PurviewInfoProtectionViewer.exe"; Args = "/quiet" },
    @{Name = ".NET Desktop Runtime"; Path = "Software\Essentials\windowsdesktop-runtime-8.0.25-win-x64.exe"; Args = "/quiet /norestart" },
    # @{Name = "Dell Command Update"; Path = "Software\Essentials\DellCommandUpdate\DCU_Setup.exe"; Args = "/s /v`"/qn /norestart`"" },
    @{Name = "Dell SupportAssist"; Path = "Software\Essentials\SupportAssistOfflineDeployment_MS_x64.exe"; Args = "-silent" }
)

# Define the function to install an application
function Install-Application {
    param ([hashtable]$app)
    try {
        $appPath = Join-Path -Path $PSScriptRoot -ChildPath $app.Path
        Test-PathExists -Path $appPath

        Write-Host "⏳ Installing $($app.Name)..." -ForegroundColor Yellow
        Write-Log "START  $($app.Name)"
        $proc = Start-Process -FilePath $appPath -ArgumentList $app.Args -Wait -PassThru
        # 0 = success; 3010/1641 = success, reboot required
        $successCodes = @(0, 3010, 1641)
        if ($proc.ExitCode -notin $successCodes) {
            throw "Installer exited with code $($proc.ExitCode)"
        }
        Write-Host "✔️ Installed $($app.Name) successfully" -ForegroundColor Green
        Write-Log "OK     $($app.Name)"

        # For Dell Command Update, configure after installation
        # if ($app.Name -eq "Dell Command Update") {
        #     Configure-DellCommandUpdate
        # }

        return $true
    }
    catch {
        Write-Host "❌ Error installing $($app.Name): $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "FAIL   $($app.Name) — $($_.Exception.Message)"
        return $false
    }
}

# Function to configure Dell Command Update via XML Import
function Configure-DellCommandUpdate {
    try {
        Write-Host "⏳ Configuring Dell Command Update..." -ForegroundColor Yellow

        # Auto-detect DCU CLI path (64-bit or 32-bit)
        $dcuCli = "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe"
        if (!(Test-Path $dcuCli)) {
            $dcuCli = "C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe"
        }

        if (!(Test-Path $dcuCli)) {
            Write-Host "⚠️ Dell Command Update CLI not found" -ForegroundColor Yellow
            return $false
        }

        # Path to your settings XML
        $xmlPath = Join-Path -Path $PSScriptRoot -ChildPath "Software\Essentials\DellCommandUpdate\MySettings.xml"

        if (!(Test-Path $xmlPath)) {
            Write-Host "⚠️ MySettings.xml not found at: $xmlPath" -ForegroundColor Yellow
            return $false
        }

        # Import settings from XML
        & $dcuCli /configure -importSettings="$xmlPath" -silent

        Write-Host "✔️ Dell Command Update configured successfully" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "❌ Error configuring Dell Command Update: $($Error[0].Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Define the function to display the menu and handle user input
function Display-Menu {
    param (
        [array]$applications,
        [int]$currentIndex
    )
    Clear-Host
    # [Add your ASCII art here — use Write-Host @"..."@ -ForegroundColor Cyan]
    Write-Host "Software Installer" -ForegroundColor Cyan
    Write-Host "Select applications to install:`n"
    for ($i = 0; $i -lt $applications.Count; $i++) {
        $app = $applications[$i]
        $checked = if ($app.Selected) { "[X]" } else { "[ ]" }
        if ($i -eq $currentIndex) {
            Write-Host "> $checked $($app.Name)" -ForegroundColor Yellow
        }
        else {
            if ($app.Selected) {
                Write-Host "  $checked $($app.Name)" -ForegroundColor Green
            }
            else {
                Write-Host "  $checked $($app.Name)" -ForegroundColor Gray
            }
        }
    }
    Write-Host "`n----------------------------------"
    Write-Host "  [Space]`tSelect/Deselect"
    Write-Host "  [Up/Down]`tMove up/down"
    Write-Host "  [Enter]`tInstall"
    Write-Host "  [q]`t`tQuit`n`n"
}

# Initialize the applications with default selection
foreach ($app in $applications) {
    $app.Selected = $false
}

# Initialize the current index
$currentIndex = 0

# Loop until the user finishes or quits
while ($true) {
    Display-Menu -applications $applications -currentIndex $currentIndex
    $key = [Console]::ReadKey($true)
    if ($key.Key -eq [System.ConsoleKey]::Enter) {
        if (($applications | Where-Object { $_.Selected }).Count -gt 0) {
            break
        }
        else {
            Write-Host "`nPlease select at least one application to install." -ForegroundColor Yellow
            Start-Sleep 1
        }
    }
    switch ($key.Key) {
        "UpArrow" {
            if ($currentIndex -gt 0) {
                $currentIndex--
            }
        }
        "DownArrow" {
            if ($currentIndex -lt $applications.Count - 1) {
                $currentIndex++
            }
        }
        "Spacebar" {
            $app = $applications[$currentIndex]
            $app.Selected = !$app.Selected
            # Debug: Check the state of all selected apps after every space press.
            # $applications | ForEach-Object { Write-Host "DEBUG: $($_.Name) - Selected: $($_.Selected)" }
        }
        "Q" {
            Write-Host "Exiting."
            exit
        }
    }
}

# Get the selected applications
$selectedApps = @($applications | Where-Object { $_.Selected -eq $true })

# Sanity check: If there are no selected apps, exit early
$totalApps = $selectedApps.Count

# Debug output: See what's being selected (optional, for troubleshooting)
# Write-Host "`n---- DEBUG: Selected Applications Before Install ----"
# foreach ($app in $selectedApps) {
#     Write-Host "$($app.Name) - Path: $($app.Path) - Args: $($app.Args)"
# }

# Don't continue if nothing was selected
if ($totalApps -eq 0) {
    Write-Host "`n[WARNING]: No applications were selected! Exiting." -ForegroundColor Yellow
    exit
}

# Process the installation of each selected app
$currentApp = 0
$progressActivity = "Installing applications"
$successfulInstalls = 0

Invoke-LogRotation
Write-Log "--- Install session started ---"

foreach ($app in $selectedApps) {
    $currentApp++
    $progress = [math]::Round(($currentApp / $totalApps) * 100)
    Write-Progress -Activity $progressActivity -Status "Installing $($app.Name)" -PercentComplete $progress
    # Attempt installation and update success count
    if (Install-Application -app $app) {
        $successfulInstalls++
    }
}

# Mark the progress as complete once installation is done
Write-Progress -Activity $progressActivity -Status "All installations complete" -PercentComplete 100
Write-Progress -Activity $progressActivity -Completed

# Summary of installations
Write-Host "`n$successfulInstalls of $totalApps applications installed successfully." -ForegroundColor Cyan
Write-Log "--- Session complete: $successfulInstalls/$totalApps installed ---"

# Only prompt for restart if there are successful installations
if ($successfulInstalls -gt 0) {
    # Auto-restart in 5 seconds unless interrupted by user
    $restart = Get-UserInput -Prompt "Restart now" -DefaultAnswer "n" -Timeout 5
    if ($restart -eq 'y') {
        try {
            Restart-Computer -Force
        }
        catch {
            Write-Host "`r❌ Error restarting computer: $($Error[0].Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "`r🚫 Restart cancelled." -ForegroundColor Yellow
    }
}
else {
    Write-Host "`n🚫 No applications were successfully installed. Restart not required." -ForegroundColor Yellow
}
Start-Sleep 3
exit
