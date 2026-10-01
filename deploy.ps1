[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [bool]$Backup = $true
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    param (
        [string]$Message,
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $color = switch ($Level) {
        'INFO'    { 'Cyan' }
        'SUCCESS' { 'Green' }
        'WARN'    { 'Yellow' }
        'ERROR'   { 'Red' }
        Default   { 'White' }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

# --- Step 0: Set working directory context ---
$cwd = Get-Location
Write-Log "Current working directory: $cwd"

# --- Step 1 & 2: Find Poedit installation path ---
Write-Log 'Step 1 & 2: Searching for Poedit installation...'

$poeditExecutable = Get-Command 'poedit.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source

if (-not $poeditExecutable) {
    $searchPaths = @(
        "${env:ProgramFiles}\Poedit\GettextTools\bin\msgfmt.exe",
        "${env:ProgramFiles(x86)}\Poedit\GettextTools\bin\msgfmt.exe",
        "${env:LocalAppData}\Programs\Poedit\GettextTools\bin\msgfmt.exe"
    )
    foreach ($path in $searchPaths) {
        if (Test-Path -Path $path) {
            $poeditExecutable = $path
            break
        }
    }
}

if (-not $poeditExecutable) {
    Write-Log 'Poedit/GettextTools was not found on this computer. Please install Poedit or add it to your PATH.' 'ERROR'
    exit 1
}

$gettext_tools_folder = Split-Path -Parent $poeditExecutable
if ((Split-Path -Leaf $gettext_tools_folder) -ne 'bin') {
    $gettext_tools_folder = Join-Path -Path $gettext_tools_folder -ChildPath 'GettextTools\bin'
}

Write-Log "Found GettextTools folder: $gettext_tools_folder" 'SUCCESS'

$msgfmtExe = Join-Path -Path $gettext_tools_folder -ChildPath 'msgfmt.exe'
if (-not (Test-Path -Path $msgfmtExe)) {
    Write-Log "msgfmt.exe not found at path: $msgfmtExe" 'ERROR'
    exit 1
}

# --- Step 3: Compile .po file to .mo file in translation folder ---
Write-Log 'Step 3: Compiling .po files to .mo files...'

$poDir = Join-Path -Path $cwd -ChildPath 'translation\zh_HK\LC_MESSAGES'
if (-not (Test-Path -Path $poDir)) {
    Write-Log "Translation directory does not exist: $poDir" 'ERROR'
    exit 1
}

$poFiles = Get-ChildItem -Path $poDir -Filter '*.po'
if ($poFiles.Count -eq 0) {
    Write-Log "No .po files found in $poDir" 'WARN'
} else {
    foreach ($poFile in $poFiles) {
        $moFilePath = [System.IO.Path]::ChangeExtension($poFile.FullName, '.mo')
        Write-Log "Compiling '$($poFile.Name)' -> '$([System.IO.Path]::GetFileName($moFilePath))'..."
        
        & "$msgfmtExe" -o "$moFilePath" "$($poFile.FullName)"
        Write-Log "Successfully compiled $moFilePath" 'SUCCESS'
    }
}

# --- Step 4: Copy compiled files to src directory ---
Write-Log 'Step 4: Copying files to src\strings\zh_HK\LC_MESSAGES...'

$srcDir = Join-Path -Path $cwd -ChildPath 'src\strings\zh_HK\LC_MESSAGES'
if (-not (Test-Path -Path $srcDir)) {
    New-Item -ItemType Directory -Path $srcDir -Force | Out-Null
    Write-Log "Created destination directory: $srcDir"
}

$moFiles = Get-ChildItem -Path $poDir -Filter '*.mo'
foreach ($moFile in $moFiles) {
    $destPath = Join-Path -Path $srcDir -ChildPath $moFile.Name
    Copy-Item -Path $moFile.FullName -Destination $destPath -Force
    Write-Log "Copied '$($moFile.Name)' to '$srcDir' (overwritten if existed)." 'SUCCESS'
}

# --- Step 5: Find Steam installation path ---
Write-Log 'Step 5: Detecting Steam installation path...'

$steamPath = $null
$regKeys = @(
    'HKCU:\Software\Valve\Steam',
    'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
    'HKLM:\SOFTWARE\Valve\Steam'
)

foreach ($key in $regKeys) {
    if (Test-Path -Path $key) {
        $steamPath = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).SteamPath
        if ($steamPath) { break }
    }
}

if (-not $steamPath -or -not (Test-Path -Path $steamPath)) {
    Write-Log 'Could not automatically locate Steam installation directory.' 'ERROR'
    exit 1
}

Write-Log "Steam path detected: $steamPath" 'SUCCESS'

# --- Step 6: Identify Steam User ID ---
Write-Log 'Step 6: Identifying Steam user IDs...'

$userDataDir = Join-Path -Path $steamPath -ChildPath 'userdata'
if (-not (Test-Path -Path $userDataDir)) {
    Write-Log "Userdata folder not found in Steam directory: $userDataDir" 'ERROR'
    exit 1
}

$userIds = Get-ChildItem -Path $userDataDir -Directory | Where-Object { $_.Name -match '^\d+$' -and $_.Name -ne '0' } | Select-Object -ExpandProperty Name

if ($userIds.Count -eq 0) {
    Write-Log "No active Steam user IDs found in $userDataDir" 'ERROR'
    exit 1
}

$selectedUserId = $null

if ($userIds.Count -eq 1) {
    $selectedUserId = $userIds[0]
    Write-Log "Single Steam User ID detected: $selectedUserId (proceeding automatically)" 'SUCCESS'
} else {
    Write-Log 'Multiple Steam User IDs found. Please select one:' 'WARN'
    for ($i = 0; $i -lt $userIds.Count; $i++) {
        Write-Host " [$($i + 1)] $($userIds[$i])"
    }
    
    while ($null -eq $selectedUserId) {
        $selection = Read-Host "Enter index (1-$($userIds.Count))"
        if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $userIds.Count) {
            $selectedUserId = $userIds[[int]$selection - 1]
        } else {
            Write-Host 'Invalid selection. Please try again.' -ForegroundColor Red
        }
    }
    Write-Log "Selected Steam User ID: $selectedUserId" 'SUCCESS'
}

# --- Step 7: Define Mod Path ---
$modPath = Join-Path -Path $steamPath -ChildPath "userdata\$selectedUserId\3493540\local\staging_area\tf3-localization-zh-hk"
Write-Log "Step 7: Target mod path resolved to: $modPath"

# --- Step 8: Backup mod contents (if requested) ---
if ($Backup) {
    Write-Log 'Step 8: Backup requested. Checking existing contents...'
    
    if ((Test-Path -Path $modPath) -and (Get-ChildItem -Path $modPath).Count -gt 0) {
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $backupZipName = "tf3-localization-zh-hk_backup_$timestamp.zip"
        $backupZipPath = Join-Path -Path (Split-Path -Parent $modPath) -ChildPath $backupZipName
        
        Write-Log "Creating backup zip archive: $backupZipPath"
        Compress-Archive -Path "$modPath\*" -DestinationPath $backupZipPath -Force
        Write-Log "Backup successfully created at: $backupZipPath" 'SUCCESS'
    } else {
        Write-Log 'Mod directory is empty or does not exist yet. Skipping backup step.' 'WARN'
    }
} else {
    Write-Log 'Step 8: Backup skipped via script argument (-Backup $false).' 'WARN'
}

# --- Step 9: Clean the target mod path ---
Write-Log 'Step 9: Cleaning target mod directory...'

if (Test-Path -Path $modPath) {
    Remove-Item -Path "$modPath\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Cleaned all contents inside $modPath" 'SUCCESS'
} else {
    New-Item -ItemType Directory -Path $modPath -Force | Out-Null
    Write-Log "Created new mod path directory: $modPath" 'SUCCESS'
}

# --- Step 10: Copy all files from <cwd>\src to mod_path ---
Write-Log "Step 10: Deploying files from '$cwd\src' to '$modPath'..."

$sourceSrc = Join-Path -Path $cwd -ChildPath 'src'
if (-not (Test-Path -Path $sourceSrc)) {
    Write-Log "Source directory does not exist: $sourceSrc" 'ERROR'
    exit 1
}

Copy-Item -Path "$sourceSrc\*" -Destination $modPath -Recurse -Force
Write-Log 'Deployment complete! All files copied successfully.' 'SUCCESS'