# debloat.ps1 — Post-install cleanup for Windows 11 VM
# Runs once via FirstLogonCommands in autounattend.xml

$ErrorActionPreference = "SilentlyContinue"

# --- Remove bloat Appx packages ---
$bloatPackages = @(
    "Clipchamp.Clipchamp"
    "Microsoft.549981C3F5F10"         # Cortana
    "Microsoft.BingNews"
    "Microsoft.BingWeather"
    "Microsoft.GamingApp"
    "Microsoft.GetHelp"
    "Microsoft.Getstarted"            # Tips
    "Microsoft.MicrosoftOfficeHub"
    "Microsoft.MicrosoftSolitaireCollection"
    "Microsoft.People"
    "Microsoft.PowerAutomateDesktop"
    "Microsoft.Todos"
    "Microsoft.WindowsAlarms"
    "Microsoft.WindowsCommunicationsApps"  # Mail & Calendar
    "Microsoft.WindowsFeedbackHub"
    "Microsoft.WindowsMaps"
    "Microsoft.WindowsSoundRecorder"
    "Microsoft.Xbox.TCUI"
    "Microsoft.XboxGameOverlay"
    "Microsoft.XboxGamingOverlay"
    "Microsoft.XboxIdentityProvider"
    "Microsoft.XboxSpeechToTextOverlay"
    "Microsoft.YourPhone"
    "Microsoft.ZuneMusic"
    "Microsoft.ZuneVideo"
    "MicrosoftCorporationII.QuickAssist"
    "MicrosoftTeams"
)

foreach ($pkg in $bloatPackages) {
    Get-AppxPackage -Name $pkg -AllUsers | Remove-AppxPackage -AllUsers
    Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq $pkg | Remove-AppxProvisionedPackage -Online
}

# --- Disable telemetry services ---
$telemetryServices = @(
    "DiagTrack"                       # Connected User Experiences and Telemetry
    "dmwappushservice"                # WAP Push Message Routing
)

foreach ($svc in $telemetryServices) {
    Stop-Service -Name $svc -Force
    Set-Service -Name $svc -StartupType Disabled
}

# --- Disable telemetry via registry ---
# Telemetry level: 0 = Security (Enterprise only), 1 = Basic
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord -Force
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Force | Out-Null

# --- Disable Cortana ---
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0 -Type DWord -Force

# --- Disable web search in Start Menu ---
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "DisableWebSearch" -Value 1 -Type DWord -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "ConnectedSearchUseWeb" -Value 0 -Type DWord -Force

# --- Install Looking Glass host (from virtio/tools drive if present) ---
$lgHostInstaller = "F:\looking-glass-host-setup.exe"
if (Test-Path $lgHostInstaller) {
    Start-Process -FilePath $lgHostInstaller -ArgumentList "/S" -Wait
}

# --- Install IddSampleDriver (virtual display driver, from tools drive if present) ---
$iddDriver = "F:\IddSampleDriver"
if (Test-Path "$iddDriver\IddSampleDriver.inf") {
    pnputil /add-driver "$iddDriver\IddSampleDriver.inf" /install
}

Write-Host "Debloat complete."
