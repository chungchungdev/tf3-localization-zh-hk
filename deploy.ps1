<#
.SYNOPSIS
    Build and deploy Traditional Chinese localization files for the Steam mod.

.DESCRIPTION
    Steps:
    1. Locate GNU gettext tools for Windows (msgattrib.exe and msgfmt.exe).
    2. Remove fuzzy flags from .po files.
    3. Compile .po files into .mo files.
    4. Copy compiled .mo files to src\strings\zh_HK\LC_MESSAGES.
    5. Locate Steam.
    6. Find valid Steam user IDs and select one if needed.
    7. Optionally back up the existing deployed mod directory as a ZIP.
    8. Clean the deployed mod directory.
    9. Copy the complete src directory into the Steam staging-area mod directory.

.PARAMETER Backup
    Whether to back up the existing mod deployment directory before cleaning it.
    Default: $true.

.PARAMETER GettextToolsFolder
    Optional explicit path to gettext's bin directory, containing:
    - msgattrib.exe
    - msgfmt.exe

.EXAMPLE
    .\deploy.ps1

    Deploy and create a timestamped ZIP backup first.

.EXAMPLE
    .\deploy.ps1 -Backup:$false

    Deploy without creating a backup.

.EXAMPLE
    .\deploy.ps1 -GettextToolsFolder "C:\tools\gettext-iconv\bin"

    Use an explicit gettext installation directory.
#>

[CmdletBinding()]
param(
    [bool]$Backup = $true,

    [ValidateScript({
        if ($_ -and -not (Test-Path -LiteralPath $_ -PathType Container)) {
            throw "GettextToolsFolder does not exist or is not a folder: $_"
        }
        $true
    })]
    [string]$GettextToolsFolder
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Script:StepNumber = 0
$Script:TotalSteps = 10

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $color = switch ($Level) {
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR"   { "Red" }
        default   { "Cyan" }
    }

    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Start-Step {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    $Script:StepNumber++
    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor DarkGray
    Write-Log "Step $Script:StepNumber/$Script:TotalSteps - $Message"
    Write-Host ("=" * 78) -ForegroundColor DarkGray
}

function Find-GettextToolsFolder {
    param(
        [string]$ExplicitFolder
    )

    if ($ExplicitFolder) {
        $candidate = (Resolve-Path -LiteralPath $ExplicitFolder).Path

        if (
            (Test-Path -LiteralPath (Join-Path $candidate "msgattrib.exe") -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $candidate "msgfmt.exe") -PathType Leaf)
        ) {
            return $candidate
        }

        throw "The supplied GettextToolsFolder does not contain both msgattrib.exe and msgfmt.exe: $candidate"
    }

    $msgattribCommand = Get-Command "msgattrib.exe" -ErrorAction SilentlyContinue
    $msgfmtCommand = Get-Command "msgfmt.exe" -ErrorAction SilentlyContinue

    if ($msgattribCommand -and $msgfmtCommand) {
        $msgattribFolder = Split-Path -Parent $msgattribCommand.Source
        $msgfmtFolder = Split-Path -Parent $msgfmtCommand.Source

        if ($msgattribFolder -eq $msgfmtFolder) {
            return $msgattribFolder
        }
    }

    $commonFolders = @(
        (Join-Path $env:ProgramFiles "gettext-iconv\bin"),
        (Join-Path ${env:ProgramFiles(x86)} "gettext-iconv\bin"),
        (Join-Path $env:LOCALAPPDATA "gettext-iconv\bin"),
        "C:\gettext-iconv\bin",
        "C:\tools\gettext-iconv\bin"
    ) | Where-Object { $_ }

    foreach ($folder in $commonFolders) {
        if (
            (Test-Path -LiteralPath (Join-Path $folder "msgattrib.exe") -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $folder "msgfmt.exe") -PathType Leaf)
        ) {
            return (Resolve-Path -LiteralPath $folder).Path
        }
    }

    throw @"
GNU gettext tools were not found.

Install gettext for Windows from:
https://mlocati.github.io/articles/gettext-iconv-windows.html

Ensure that the gettext bin folder contains both:
- msgattrib.exe
- msgfmt.exe

Then either:
1. Add the folder to PATH, or
2. Run this script with:
   .\deploy.ps1 -GettextToolsFolder "C:\path\to\gettext-iconv\bin"
"@
}

function Find-SteamPath {
    $registryLocations = @(
        "HKCU:\Software\Valve\Steam",
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam"
    )

    foreach ($registryLocation in $registryLocations) {
        if (Test-Path -LiteralPath $registryLocation) {
            $steamPath = (Get-ItemProperty -LiteralPath $registryLocation -ErrorAction SilentlyContinue).SteamPath

            if ($steamPath) {
                $steamPath = $steamPath -replace "/", "\"

                if (Test-Path -LiteralPath $steamPath -PathType Container) {
                    return (Resolve-Path -LiteralPath $steamPath).Path
                }
            }
        }
    }

    $commonSteamPaths = @(
        (Join-Path $env:ProgramFiles "Steam"),
        (Join-Path ${env:ProgramFiles(x86)} "Steam"),
        (Join-Path $env:LOCALAPPDATA "Steam")
    ) | Where-Object { $_ }

    foreach ($steamPath in $commonSteamPaths) {
        if (Test-Path -LiteralPath $steamPath -PathType Container) {
            return (Resolve-Path -LiteralPath $steamPath).Path
        }
    }

    throw "Steam installation was not found. Please start Steam once, then run this script again."
}

function Get-SteamUserIds {
    param(
        [Parameter(Mandatory)]
        [string]$SteamPath
    )

    $userdataPath = Join-Path $SteamPath "userdata"

    if (-not (Test-Path -LiteralPath $userdataPath -PathType Container)) {
        throw "Steam userdata folder was not found: $userdataPath"
    }

    $steamUserIds = Get-ChildItem -LiteralPath $userdataPath -Directory -Force |
        Where-Object { $_.Name -match "^\d{8,}$" } |
        Sort-Object Name |
        ForEach-Object { $_.Name }

    if (-not $steamUserIds) {
        throw "No valid Steam user IDs were found in: $userdataPath"
    }

    return @($steamUserIds)
}

function Select-SteamUserId {
    param(
        [Parameter(Mandatory)]
        [string[]]$SteamUserIds
    )

    if ($SteamUserIds.Count -eq 1) {
        Write-Log "One Steam user ID found. Using it automatically: $($SteamUserIds[0])"
        return $SteamUserIds[0]
    }

    Write-Log "Multiple Steam user IDs were found. Please select the account to deploy to." "WARNING"

    for ($index = 0; $index -lt $SteamUserIds.Count; $index++) {
        Write-Host ("  [{0}] {1}" -f ($index + 1), $SteamUserIds[$index])
    }

    while ($true) {
        $selection = Read-Host "Enter a number from 1 to $($SteamUserIds.Count)"

        $selectionNumber = 0
        if ([int]::TryParse($selection, [ref]$selectionNumber)) {
            if ($selectionNumber -ge 1 -and $selectionNumber -le $SteamUserIds.Count) {
                return $SteamUserIds[$selectionNumber - 1]
            }
        }

        Write-Log "Invalid selection. Enter a number from 1 to $($SteamUserIds.Count)." "WARNING"
    }
}

function Clear-DirectoryContents {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        return
    }

    $items = @(Get-ChildItem -LiteralPath $Path -Force)

    if ($items.Count -gt 0) {
        $items | Remove-Item -Recurse -Force
    }
}

try {
    Write-Host ""
    Write-Host "Steam localization deployment script" -ForegroundColor White
    Write-Host "Working directory: $(Get-Location)" -ForegroundColor DarkGray
    Write-Host "Backup enabled: $Backup" -ForegroundColor DarkGray

    $projectRoot = (Get-Location).Path

    $poFolder = Join-Path $projectRoot "translation\zh_HK\LC_MESSAGES"
    $sourceLocalizationFolder = Join-Path $projectRoot "src\strings\zh_HK\LC_MESSAGES"
    $sourceFolder = Join-Path $projectRoot "src"

    Start-Step "Checking GNU gettext for Windows"

    $gettext_tools_folder = Find-GettextToolsFolder -ExplicitFolder $GettextToolsFolder
    $msgattrib = Join-Path $gettext_tools_folder "msgattrib.exe"
    $msgfmt = Join-Path $gettext_tools_folder "msgfmt.exe"

    Write-Log "gettext_tools_folder: $gettext_tools_folder" "SUCCESS"
    Write-Log "Found msgattrib.exe: $msgattrib"
    Write-Log "Found msgfmt.exe: $msgfmt"

    Start-Step "Confirming translation input folder"

    if (-not (Test-Path -LiteralPath $poFolder -PathType Container)) {
        throw "Translation folder was not found: $poFolder"
    }

    $poFiles = @(Get-ChildItem -LiteralPath $poFolder -Filter "*.po" -File -Recurse)

    if ($poFiles.Count -eq 0) {
        throw "No .po files were found in: $poFolder"
    }

    Write-Log "Found $($poFiles.Count) PO file(s) in: $poFolder" "SUCCESS"

    Start-Step "Removing fuzzy flags from PO files"

    foreach ($poFile in $poFiles) {
        $temporaryPoFile = Join-Path $poFile.DirectoryName ("{0}.no-fuzzy.{1}.tmp" -f $poFile.BaseName, [guid]::NewGuid().ToString("N"))

        try {
            Write-Log "Removing fuzzy flags: $($poFile.FullName)"

            & $msgattrib --clear-fuzzy --output-file=$temporaryPoFile $poFile.FullName

            if ($LASTEXITCODE -ne 0) {
                throw "msgattrib.exe failed with exit code $LASTEXITCODE for: $($poFile.FullName)"
            }

            Move-Item -LiteralPath $temporaryPoFile -Destination $poFile.FullName -Force
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPoFile) {
                Remove-Item -LiteralPath $temporaryPoFile -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Write-Log "Removed fuzzy flags from all PO file(s)." "SUCCESS"

    Start-Step "Compiling PO files into MO files"

    foreach ($poFile in $poFiles) {
        $moFile = Join-Path $poFile.DirectoryName ($poFile.BaseName + ".mo")

        Write-Log "Compiling '$($poFile.Name)' -> '$([System.IO.Path]::GetFileName($moFile))'"

        & $msgfmt --output-file=$moFile $poFile.FullName

        if ($LASTEXITCODE -ne 0) {
            throw "msgfmt.exe failed with exit code $LASTEXITCODE for: $($poFile.FullName)"
        }

        if (-not (Test-Path -LiteralPath $moFile -PathType Leaf)) {
            throw "Compilation appeared to succeed, but no MO file was created: $moFile"
        }
    }

    Write-Log "Compiled $($poFiles.Count) MO file(s)." "SUCCESS"

    Start-Step "Copying compiled MO files into src"

    New-Item -ItemType Directory -Path $sourceLocalizationFolder -Force | Out-Null

    $moFiles = @(Get-ChildItem -LiteralPath $poFolder -Filter "*.mo" -File -Recurse)

    if ($moFiles.Count -eq 0) {
        throw "No compiled MO files were found after compilation."
    }

    foreach ($moFile in $moFiles) {
        $relativePath = $moFile.FullName.Substring($poFolder.Length).TrimStart("\")
        $destinationMoFile = Join-Path $sourceLocalizationFolder $relativePath
        $destinationDirectory = Split-Path -Parent $destinationMoFile

        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        Copy-Item -LiteralPath $moFile.FullName -Destination $destinationMoFile -Force

        Write-Log "Copied: $relativePath"
    }

    Write-Log "Copied compiled localization file(s) to: $sourceLocalizationFolder" "SUCCESS"

    Start-Step "Finding Steam installation path"

    $steamPath = Find-SteamPath
    Write-Log "Steam installation found: $steamPath" "SUCCESS"

    Start-Step "Finding Steam user IDs"

    $steamUserIds = Get-SteamUserIds -SteamPath $steamPath

    Write-Log "Valid Steam user ID(s): $($steamUserIds -join ', ')"
    $steamUserId = Select-SteamUserId -SteamUserIds $steamUserIds

    if ($steamUserId -notmatch "^\d{8,}$") {
        throw "Selected Steam user ID is invalid: $steamUserId"
    }

    Write-Log "Using Steam user ID: $steamUserId" "SUCCESS"

    Start-Step "Preparing Steam mod deployment path"

    $modPath = Join-Path $steamPath "userdata\$steamUserId\3493540\local\staging_area\tf3-localization-zh-hk"

    Write-Log "mod_path: $modPath"

    Start-Step "Backing up existing mod files"

    if ($Backup) {
        if (Test-Path -LiteralPath $modPath -PathType Container) {
            $existingItems = @(Get-ChildItem -LiteralPath $modPath -Force)

            if ($existingItems.Count -gt 0) {
                $backupRoot = Join-Path $projectRoot "backups"
                New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

                $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                $backupFile = Join-Path $backupRoot "tf3-localization-zh-hk-backup-$timestamp.zip"

                Write-Log "Creating ZIP backup: $backupFile"

                Compress-Archive -Path (Join-Path $modPath "*") -DestinationPath $backupFile -CompressionLevel Optimal -Force

                if (-not (Test-Path -LiteralPath $backupFile -PathType Leaf)) {
                    throw "Backup ZIP was not created: $backupFile"
                }

                Write-Log "Backup created successfully: $backupFile" "SUCCESS"
            }
            else {
                Write-Log "The mod directory is already empty. No backup is needed." "WARNING"
            }
        }
        else {
            Write-Log "The mod directory does not exist yet. No backup is needed." "WARNING"
        }
    }
    else {
        Write-Log "Backup was disabled with -Backup:`$false." "WARNING"
    }

    Start-Step "Cleaning and deploying mod files"

    if (-not (Test-Path -LiteralPath $sourceFolder -PathType Container)) {
        throw "Source folder was not found: $sourceFolder"
    }

    Write-Log "Cleaning deployment directory: $modPath"
    Clear-DirectoryContents -Path $modPath

    Write-Log "Copying all files from '$sourceFolder' to '$modPath'"

    $sourceItems = @(Get-ChildItem -LiteralPath $sourceFolder -Force)

    if ($sourceItems.Count -eq 0) {
        throw "Source folder is empty: $sourceFolder"
    }

    foreach ($sourceItem in $sourceItems) {
        Copy-Item -LiteralPath $sourceItem.FullName -Destination $modPath -Recurse -Force
    }

    Write-Log "Deployment completed successfully." "SUCCESS"
    Write-Log "Installed mod path: $modPath" "SUCCESS"

    exit 0
}
catch {
    Write-Host ""
    Write-Log $_.Exception.Message "ERROR"
    Write-Log "Deployment failed. Existing files may remain if failure occurred before the clean/deploy stage." "ERROR"
    exit 1
}