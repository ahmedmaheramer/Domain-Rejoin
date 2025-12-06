# ===================================================================
# Script Name: Domain Join
# Created By:  Ahmed Maher Amer
# Contact:     ahmedmaheramer@outlook.com
# 
# DESCRIPTION:
# This script can be used to:
# 1. Join Computer To The Domain (On-Site & WAH).
# 2. Change Domain To Concentrix.com.
# 3. Fix Trust Relationship (if reset computer password didn't work).
# ===================================================================

param(
    [Parameter(Mandatory=$true, HelpMessage="The Active Directory Domain (e.g., concentrix.com)")]
    [string]$DomainName,

    [Parameter(Mandatory=$true, HelpMessage="Account with permissions to join computers to the domain")]
    [string]$JoinUser,

    [Parameter(Mandatory=$true, HelpMessage="Password for the join account")]
    [string]$JoinPass,

    [Parameter(Mandatory=$true, HelpMessage="Target OU path (Canonical or Distinguished Name)")]
    [string]$TargetOU,

    [Parameter(Mandatory=$true, HelpMessage="Azure AD Tenant ID for Registry Tagging")]
    [string]$TenantId,

    [Parameter(Mandatory=$true, HelpMessage="Azure AD Tenant Name for Registry Tagging")]
    [string]$TenantName,

    [Parameter(Mandatory=$false, HelpMessage="Optional: Specific Domain Controller to pin connectivity to")]
    [string]$PreferredDC
)

# --- HEADER FRAME ---
Clear-Host
Write-Host "===================================================================" -ForegroundColor Green
Write-Host " Created By: Ahmed Maher Amer" -ForegroundColor White
Write-Host " Contact:    ahmedmaheramer@outlook.com" -ForegroundColor White
Write-Host "===================================================================" -ForegroundColor Green
Write-Host ""

# --- Configuration & Setup ---
$LogFile = "C:\IT Tasks\Domain_Join_Log.txt"

# Ensure Log Directory Exists
if (!(Test-Path "C:\IT Tasks")) { New-Item -Path "C:\IT Tasks" -ItemType Directory -Force | Out-Null }

Function Write-Log {
    Param([string]$Message, [string]$Type = "INFO")
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "[$TimeStamp] [$Type] $Message"
    Write-Host $Line -ForegroundColor ($Type -eq "ERROR" ? "Red" : ($Type -eq "SUCCESS" ? "Green" : "Cyan"))
    Add-Content -Path $LogFile -Value $Line -Force
}

# --- Step 1: OU Parsing Function (Canonical to DN) ---
Function Get-DistinguishedName {
    param(
        [string]$InputPath,
        [string]$Domain
    )
    
    # 1. Check if it is already a Distinguished Name (contains DC= or OU=)
    if ($InputPath -match "^(OU=|CN=|DC=)") { 
        return $InputPath 
    }

    # 2. Handle Canonical Path (e.g. domain.com/Region/Country/...)
    # Dynamically remove the domain name provided in parameters from the start of the path
    $EscapedDomain = [Regex]::Escape($Domain)
    $CleanPath = $InputPath -replace "^$EscapedDomain[/\\]?", ""
    $CleanPath = $CleanPath.Trim("/", "\", " ")

    # Split into parts
    $Parts = $CleanPath -split "[/\\]"
    
    # Reverse the array (Leaf OU comes first in DN)
    [array]::Reverse($Parts)

    # Build the DN parts
    $DNParts = @()
    foreach ($part in $Parts) {
        # Skip empty parts caused by double slashes
        if (-not [string]::IsNullOrWhiteSpace($part)) {
            $DNParts += "OU=$part"
        }
    }

    # Construct the DC suffix from the Domain Name (e.g. example.com -> DC=example,DC=com)
    $DCSuffix = "DC=" + ($Domain -replace "\.", ",DC=")
    
    # Join parts and append suffix
    $FinalDN = ($DNParts -join ",") + "," + $DCSuffix
    return $FinalDN
}

# Parse the OU immediately
$CalculatedOU = Get-DistinguishedName -InputPath $TargetOU -Domain $DomainName
Write-Log "Configuration Loaded:"
Write-Log "   Domain:      $DomainName"
Write-Log "   Target OU:   $CalculatedOU"

# --- Step 2: Ensure Clean State (Workgroup Mode) ---
Write-Log "Step 2: Checking Domain Status..."
if ((Get-CimInstance -ClassName Win32_ComputerSystem).PartOfDomain) {
    Write-Log "Device is currently domain joined. Removing from domain..." "WARN"
    # Attempt to leave Azure AD if present
    if (Get-Command "dsregcmd" -ErrorAction SilentlyContinue) {
        dsregcmd /leave | Out-Null
    }
    Remove-Computer -WorkgroupName "WORKGROUP" -Force -ErrorAction SilentlyContinue
    Write-Log "Device forced into Workgroup mode." "SUCCESS"
} else {
    Write-Log "Device is already in Workgroup." "SUCCESS"
}

# --- Step 3: Network Check & DC Discovery ---
Write-Log "Step 3: Network Check & DC Discovery..."
$NLTestOut = nltest /dsgetdc:$DomainName 2>&1 | Out-String

if ($NLTestOut -match "DC: \\\\([^\s]+)") {
    $PinnedDC = $matches[1]
    Write-Log "Network Healthy. Auto-discovered DC: $PinnedDC" "SUCCESS"
} elseif (-not [string]::IsNullOrWhiteSpace($PreferredDC)) {
    $PinnedDC = $PreferredDC
    Write-Log "Discovery failed. Forcing connection to User-Specified DC: $PinnedDC" "WARN"
} else {
    Write-Log "CRITICAL: Domain Controller discovery failed and no Preferred DC was specified." "ERROR"
    Write-Log "Please check VPN/Network connectivity." "ERROR"
    exit 1
}

# --- Step 4: Join Domain ---
Write-Log "Step 4: Joining Domain..."
$SecJoinPass = ConvertTo-SecureString -String $JoinPass -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PsCredential($JoinUser, $SecJoinPass)

try {
    Add-Computer -DomainName $DomainName -Credential $Credential -OUPath $CalculatedOU -Server $PinnedDC -Force -ErrorAction Stop
    Write-Log "JOIN SUCCESSFUL! Device has joined $DomainName." "SUCCESS"
} catch {
    Write-Log "JOIN FAILED. Error: $_" "ERROR"
    exit 1
}

# --- Step 5: Registry Configuration (Azure AD / Intune Prep) ---
Write-Log "Step 5: Applying Tenant Registry Settings..."
$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CDJ\AAD"
if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }

try {
    Set-ItemProperty -Path $RegPath -Name "TenantId" -Value $TenantId -Force -ErrorAction Stop
    Set-ItemProperty -Path $RegPath -Name "TenantName" -Value $TenantName -Force -ErrorAction Stop
    Write-Log "Registry tags applied successfully." "SUCCESS"
} catch {
    Write-Log "Failed to apply registry settings: $_" "ERROR"
}

Write-Log "Script Complete. A RESTART IS REQUIRED." "SUCCESS"