<#
.SYNOPSIS
    Recursively copies a directory tree with low memory use and per-file
    conflict prompts.

.PARAMETER SourceType
    Alias: '-type'

    File or Dir (default Dir).  File: Source is one file; Destination is
    either an existing folder (original name kept) or the full target file
    path (allows renaming).

.PARAMETER Source
    Alias: '-src'

    Directory to copy.

    If the path contains spaces, wrap the full path with either single
    or double quotes (e.g. "D:\Photo Vault")

.PARAMETER Destination
    Alias: '-dest'

    Destination directory (created if it does not exist).

    If the path contains spaces, wrap the full path with either single
    or double quotes (e.g. "E:\Photo Vault Backup")

.PARAMETER SkipIdentical
    Silently skip conflicts where size and last-write time already match.

.PARAMETER CopyAcl
    Copy NTFS security (DACL, owner, group) from each source file/folder
    to its copy.  Falls back to DACL only if the owner/group cannot be set
    (run elevated for full fidelity).

.PARAMETER VerifyHash
    Alias: '-verify'

    After each copy, hash the source and the copy and compare them.

.PARAMETER HashAlgorithm
    Alias: '-hash'

    MD5, SHA1, SHA256 (default), SHA384 or SHA512.

.PARAMETER LogPath
    Alias: '-logp'

    Path where the Csv log file will be written.

    Default: If no argument is provided, the log file will saved in
    the directory from which the .ps1 script is run.

.PARAMETER LogFile
    Alias: '-logf'

    Name of the Csv log file.

    Default: '<yyyy.MM.dd_HH.mm.ss>_file_copy_log.csv' if no value is
    provided.

    The script automatically appends the '<yyyy.MM.dd_HH.mm.ss>'
    timestamp to the beginning of the log file name and the '.csv'
    extension to the end of the filename.

    If the file name contains spaces, wrap the string with either single
    or double quotes (e.g. "photos backup")

.PARAMETER NoLog
    Do not write a Csv log.

.INPUTS
    None.

.OUTPUTS
    None.

.EXAMPLE
.\Copy-Files2.ps1 `
[-Source|-src] D:\Photos `
[-Destination|-dest] E:\Backup\Photos `
-CopyAcl `
[-VerifyHash|-verify] `
[-LogPath|-logp] E:\Logs `
[-LogFile|-logf] photos

    Copies all files from the 'D:\Photos' folder to the 'E:\Backup\Photos'
    folder, along with the ACL of each file.  Will verify the hash of
    each copied file and then write the Csv log file to
    'E:\Logs\<yyyy.MM.dd_HH.mm.ss>_photos.csv'.

.EXAMPLE
.\Copy-Files2.ps1 `
[-Source|-src] D:\Photos `
[-Destination|-dest] E:\Backup\Photos `
-NoLog

    Copies all files from the 'D:\Photos' folder to the 'E:\Backup\Photos'
    folder, the ACL data is skipped, the copied files are not hashed and no
    log file is written.

.NOTES
    Version 0.2

.LINK
    https://github.com/LongRangeBehaviorModificationSpecialist/FileCopier
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet("File","Dir")]
    [Alias("type")]
    [string]$SourceType = "Dir",

    [Parameter(Mandatory)]
    [Alias("src")]
    [string]$Source,

    [Parameter(Mandatory)]
    [Alias("dest")]
    [string]$Destination,

    [Alias("verify")]
    [switch]$VerifyHash,

    [ValidateSet("MD5", "SHA1", "SHA256", "SHA512")]
    [Alias("hash")]
    [string]$HashAlgorithm = "SHA256",

    [Alias("logp")]
    [string]$LogPath,

    [Alias("logf")]
    [string]$LogFile,

    [switch]$SkipIdentical,
    [switch]$CopyAcl,
    [switch]$NoLog
)

<#
Embedded base64 data for the picture to use with the toast notification
that is shown when the script has completed.
#>
$embeddedImage = @"
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
"@

$ErrorActionPreference = "Stop"
$Sep = [IO.Path]::DirectorySeparatorChar


function Resolve-FullPath {
    param(
        [string]$path
    )

    $fullPath = [IO.Path]::GetFullPath($PSCmdlet.GetUnresolvedProviderPathFromPSPath($path))

    if ($fullPath -ne [IO.Path]::GetPathRoot($fullPath)) {
        $fullPath = $fullPath.TrimEnd("\", "/")
    }

    $fullPath
}


$Src = Resolve-FullPath $Source
$Dst = Resolve-FullPath $Destination

# Traversal root: the directory that gets walked
$SrcRoot = $Src
# Traversal target root
$DstRoot = $Dst
# File mode: final destination file path
$DstFile = $null

<#
If '-dest' names an existing folder, the file lands inside it under its
original name; otherwise -dest is treated as the target file path, so
"-src C:\a\report.docx -dest D:\archive\2024-report.docx" renames on
copy.  The "destination inside source" check is dropped in file mode,
copying one file can't recurse infinitely.
#>
if ($SourceType -eq "File") {
    if (-not [IO.File]::Exists($Src)) {
        Write-Error "Source file not found => $Src"
    }

    $SrcRoot = [IO.Path]::GetDirectoryName($Src)

    if ([IO.Directory]::Exists($Dst)) {
        # Destination given as a folder: keep the source file's name
        $DstFile = [IO.Path]::Combine($Dst, [IO.Path]::GetFileName($Src))
    }
    else {
        $DstFile = $Dst
    }

    $DstRoot = [IO.Path]::GetDirectoryName($DstFile)

    if ($DstFile -ieq $Src) {
        Write-Error "Source and destination are the same file."
    }
}
else {
    if (-not [IO.Directory]::Exists($Src)) {
        Write-Error "Source directory not found => $Src"
    }

    if ($Src -ieq $Dst) {
        Write-Error "Source and destination are the same directory."
    }

    if ($Dst.StartsWith($Src.TrimEnd($Sep) + $Sep, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Error "Destination cannot be inside the source directory."
    }
}


# ----------
# Create the CSV log file
# ----------

$Script:Log = $null
$LogFull = $null

if (-not $NoLog) {
    # A custom file name is meaningless without a directory to put it in.
    if ($LogFile -and -not $LogPath) {
        Write-Error ("You specified -LogFile '$LogFile' but not -LogPath. " +
            "A custom file name requires an output directory.")
    }

    # Default file name when the user gave a directory but no name
    if (-not $LogFile) {
        $LogFile = "file_copy_log.csv"
    }

    <#
    Reject path fragments in $LogFile parameter; it must be a bare name
    so that Path::Combine below can never produce a mangled path.
    #>
    if ([IO.Path]::GetFileName($LogFile) -ne $LogFile) {
        Write-Error ("-LogFile must be a file name only, not a path.  Specify the " +
            "directory using the '-LogPath' parameter.")
    }

    if (-not $LogPath) {
        if ($PSScriptRoot) {
            <#
            $PSScriptRoot is populated when the code executes as a .ps1 file, but
            it's $null/empty if the same code ever gets dot-sourced into a bare
            console session or run via some hosts that don't set it.  Falling back
            to Get-Location there means the block never produces a pathless resolve,
            which Resolve-FullPath would choke on.
            #>
            $LogPath = $PSScriptRoot
        }
        else {
            $LogPath = (Get-Location).ProviderPath
        }
    }

    $LogDir = Resolve-FullPath $LogPath

    <#
    $LogPath is a directory by contract; if the user actually pointed at
    an existing FILE (old habit from the previous single-parameter scheme),
    fall back to treating its location as the directory rather than failing.
    #>
    if ([IO.File]::Exists($LogDir)) {
        Write-Warning "-LogPath was given a file path; logging to its parent directory."
        $LogDir = [IO.Path]::GetDirectoryName($LogDir)
    }

    # Timestamp is prepended to the NAME only, extension normalized to .csv
    $LogName = [IO.Path]::GetFileNameWithoutExtension($LogFile)
    $LogFull = [IO.Path]::Combine(
        $LogDir,
        [string]::Format(
            "{0:yyyy.MM.dd_HH.mm.ss}_{1}.csv",
            (Get-Date),
            $LogName
        )
    )

    <#
    The check's purpose is "don't write the log inside the tree being copied."
    In file mode '$Src' is a file path, so the old comparison could never match
    sensibly; '$SrcRoot' keeps the intent for both modes.
    #>
    if ($LogFull.StartsWith($SrcRoot.TrimEnd($Sep) + $Sep,
        [StringComparison]::OrdinalIgnoreCase)) {
        Write-Warning "The log file cannot be inside the source directory: $LogFull"
        exit 1
    }

    [void][IO.Directory]::CreateDirectory($LogDir)
}

[void][IO.Directory]::CreateDirectory($DstRoot)

$Script:CsvSpecial = [char[]]@(',', '"', "`r", "`n")


function ConvertTo-CsvField {
    param(
        [string]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    $S = [string]$Value

    if ($S.IndexOfAny($Script:CsvSpecial) -ge 0) {
        return '"' + $S.Replace('"', '""') + '"'
    }
    $S
}


function Write-LogRow {
    param(
        [string]$Type,
        [string]$Status,
        [string]$SrcPath,
        [string]$DstPath,
        [string]$Size,
        [string]$Modified,
        [string]$HashSrc,
        [string]$HashDst,
        [string]$HashResult,
        [string]$AclResult,
        [string]$Note
    )

    if (-not $Script:Log) {
        return
    }

    $Algo = if ($VerifyHash) {
        $HashAlgorithm
    }
    else {
        ""
    }

    $Vals = @(
        [DateTime]::UtcNow.ToString("o"),
        $Type,
        $Status,
        $SrcPath,
        $DstPath,
        $Size,
        $Modified,
        $Algo,
        $HashSrc,
        $HashDst,
        $HashResult,
        $AclResult,
        $Note
    )

    $Parts = [string[]]::new($Vals.Count)

    for ($I = 0; $I -lt $Vals.Count; $I++) {
        $Parts[$I] = ConvertTo-CsvField $Vals[$I]
    }
    $Script:Log.WriteLine([string]::Join(",", $Parts))
}

if ($LogFull) {
    # UTF-8 with BOM so Excel reads non-ASCII file names correctly.
    # Other programs can still read the file while it is being written.
    $Script:Log = [IO.StreamWriter]::new(
        $LogFull,
        $false,
        [Text.UTF8Encoding]::new($true)
    )
    $Script:Log.WriteLine('TimestampUtc,Type,Status,SourcePath,DestinationPath,SizeBytes,SourceModifiedUtc,HashAlgorithm,SourceHash,DestinationHash,HashResult,AclResult,Note')
}

# ---------- Hashing: one reusable 1 MB buffer and one reusable hasher ----------
if ($VerifyHash) {
    $Script:Hasher = [Security.Cryptography.IncrementalHash]::CreateHash(
        [Security.Cryptography.HashAlgorithmName]::new($HashAlgorithm))
    $Script:Buffer = [byte[]]::new(1MB)
}


function Get-StreamHash {
    param(
        [string]$Path
    )

    # bufferSize 1 disables FileStream's own buffering
    # We read in 1 MB chunks ourselves
    $Fs = [IO.FileStream]::new(
        $Path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::ReadWrite,
        1,
        [IO.FileOptions]::SequentialScan
    )
    try {
        while (($N = $Fs.Read($Script:Buffer, 0, $Script:Buffer.Length)) -gt 0) {
            $Script:Hasher.AppendData($Script:Buffer, 0, $N)
        }
        [BitConverter]::ToString($Script:Hasher.GetHashAndReset()).Replace("-", "")
    }
    finally {
        $Fs.Dispose()
    }
}


# ---------- NTFS security copy ----------
# PowerShell 5.1 (.NET Framework) exposes GetAccessControl on 
# FileInfo/DirectoryInfo;
# PowerShell 7 (.NET Core) exposes it through FileSystemAclExtensions instead.
$Script:UseExt = $PSVersionTable.PSVersion.Major -ge 6

# Returns $true if owner+group+DACL were copied, $false if only the DACL was.
function Copy-Security {
    param(
        [string]$From,
        [string]$To,
        [bool]$IsDir
    )

    if ($IsDir) {
        $F = [IO.DirectoryInfo]::new($From)
        $T = [IO.DirectoryInfo]::new($To)
    }
    else {
        $F = [IO.FileInfo]::new($From)
        $T = [IO.FileInfo]::new($To)
    }

    $Full = [Security.AccessControl.AccessControlSections]"Access,Owner,Group"
    $Dacl = [Security.AccessControl.AccessControlSections]::Access
    $LastError = $null

    foreach ($Sections in @($Full, $Dacl)) {
        try {
            $Sec = if ($Script:UseExt) {
                [IO.FileSystemAclExtensions]::GetAccessControl($F, $Sections)
            }
            else {
                $F.GetAccessControl($Sections)
            }

            # Mark the sections as modified so they are actually written 
            # to the target
            $Sec.SetAccessRuleProtection($Sec.AreAccessRulesProtected, $true)
            if ($Sections -eq $Full) {
                $Sec.SetOwner($Sec.GetOwner([Security.Principal.SecurityIdentifier]))
                $Sec.SetGroup($Sec.GetGroup([Security.Principal.SecurityIdentifier]))
            }

            if ($Script:UseExt) {
                [IO.FileSystemAclExtensions]::SetAccessControl($T, $Sec)
            }
            else {
                $T.SetAccessControl($Sec)
            }
            return ($Sections -eq $Full)
        }
        catch {
            $LastError = $_
        }
    }
    throw $LastError
}


# Returns "name (1).ext", "name (2).ext", ... for the first unused name
function Get-UniquePath {
    param(
        [string]$Path
    )

    $Folder = [IO.Path]::GetDirectoryName($Path)
    $Base   = [IO.Path]::GetFileNameWithoutExtension($Path)
    $Ext    = [IO.Path]::GetExtension($Path)
    $I      = 1
    do {
        $Candidate = [IO.Path]::Combine($Folder, "$Base ($I)$Ext")
        $I++
    } while ([IO.File]::Exists($Candidate) -or [IO.Directory]::Exists($Candidate))
    $Candidate
}

$Choices = @(
    [Management.Automation.Host.ChoiceDescription]::new(
        "&Source",
        "Overwrite the destination file with the source file"
    )
    [Management.Automation.Host.ChoiceDescription]::new(
        "&Destination",
        "Keep the existing destination file (skip)"
    )
    [Management.Automation.Host.ChoiceDescription]::new(
        "&Both",
        "Keep both; copy source under a new name"
    )
    [Management.Automation.Host.ChoiceDescription]::new(
        "Source for &All",
        "Overwrite for this and all later conflicts"
    )
    [Management.Automation.Host.ChoiceDescription]::new(
        "Destination for all (&Keep)",
        "Skip this and all later conflicts"
    )
)

# Prompt | Source | Destination
$Policy          = "Prompt"
[int]$Copied     = 0
[int]$Skipped    = 0
[int]$Renamed    = 0
[int]$Failed     = 0
[int]$Verified   = 0
[int]$Mismatch   = 0
[int]$AclOk      = 0
[int]$AclPartial = 0
[int]$AclFailed  = 0
[long]$Bytes     = 0
$Clock           = [Diagnostics.Stopwatch]::StartNew()
[int]$LastUpdate = 0

# Directories only; far fewer than files
$AclDirs = [Collections.Generic.List[string]]::new()

$Stack = [Collections.Generic.Stack[string]]::new()
$Stack.Push($SrcRoot)

try {
    while ($Stack.Count -gt 0) {
        $Dir = $Stack.Pop()
        $Rel = $Dir.Substring($SrcRoot.Length).TrimStart($Sep)
        $TargetDir = if ($Rel) {
            [IO.Path]::Combine($DstRoot, $Rel)
        }
        else {
            $DstRoot
        }

        try {
            [void][IO.Directory]::CreateDirectory($TargetDir)

            # Applied at the end so a restrictive ACL can't block the copy
            if ($CopyAcl -and $SourceType -eq "Dir") {
                $AclDirs.Add($Dir)
            }

            <#
            DirectoryInfo.EnumerateFiles streams FileInfo objects
            (size/date come with the listing)

            The [IO.FileInfo[]]@(...) cast matters — without forcing an
            array, a single-element pipeline result unrolled by foreach
            would still work here, but the explicit array guarantees the
            FileInfo object arrives intact with its length/timestamp
            metadata, which the conflict prompt and '-SkipIdentical' rely on.
            #>
            $Files = if ($SourceType -eq "File") {
                # Single-file mode: process only the chosen file
                [IO.FileInfo[]]@([IO.FileInfo]::new($Src))
            }
            else {
                [IO.DirectoryInfo]::new($Dir).EnumerateFiles()
            }

            foreach ($F in $Files) {
                $File   = $F.FullName
                $Target = [IO.Path]::Combine($TargetDir, $F.Name)
                if ($SourceType -eq "File") {
                    # Honor the destination file name chosen by the user
                    $Target = $DstFile
                }
                $Status     = ""
                $AclResult  = ""
                $HashSrc    = ""
                $HashDst    = ""
                $HashResult = ""
                $Note       = ""

                try {
                    $DoCopy    = $true
                    $Overwrite = $false
                    $Status    = "Copied"
                    $D = [IO.FileInfo]::new($Target)

                    if ($D.Exists) {
                        if ($SkipIdentical -and $F.Length -eq $D.Length `
                            -and $F.LastWriteTimeUtc -eq $D.LastWriteTimeUtc) {
                            $Skipped++
                            $DoCopy = $false
                            $Status = "SkippedIdentical"
                        }
                        else {
                            $Action = $Policy
                            if ($Policy -eq "Prompt") {
                                $Nl  = [Environment]::NewLine
                                $Msg = "Conflict: $Target" +
                                    $Nl +
                                    ([string]::Format(
                                        "  Source:      {0,15:N0} bytes   modified {1}",
                                        $F.Length,
                                        $F.LastWriteTime
                                    )) +
                                    $Nl +
                                    ([string]::Format(
                                        "  Destination: {0,15:N0} bytes   modified {1}",
                                        $D.Length,
                                        $D.LastWriteTime
                                    ))

                                Write-Progress -Activity "Copying" -Completed

                                switch ($Host.UI.PromptForChoice("File already exists", $Msg, $Choices, 1)) {
                                    0 { $Action = "Source" }
                                    1 { $Action = "Destination" }
                                    2 { $Action = "Both" }
                                    3 {
                                        $Action = "Source"
                                        $Policy = "Source"
                                    }
                                    4 {
                                        $Action = "Destination"
                                        $Policy = "Destination"
                                    }
                                }
                            }

                            switch ($Action) {
                                "Destination" {
                                    $DoCopy = $false
                                    $Status = "SkippedKeptDestination"
                                    $Skipped++
                                }
                                "Both" {
                                    $Target = Get-UniquePath $Target
                                    $Status = "CopiedRenamed"
                                    $Renamed++
                                }
                                "Source" {
                                    $Overwrite = $true
                                    $Status    = "Overwritten"
                                    # Clears read-only/hidden/system so the overwrite can succeed
                                    [IO.File]::SetAttributes($Target, [IO.FileAttributes]::Normal)
                                }
                            }
                        }
                    }

                    if ($DoCopy) {
                        [IO.File]::Copy($File, $Target, $Overwrite)
                        $Copied++
                        $Bytes += $F.Length

                        if ($CopyAcl) {
                            try {
                                if (
                                    Copy-Security `
                                        -From $File `
                                        -To $Target `
                                        -IsDir $false
                                ) {
                                    $AclOk++
                                    $AclResult = "Full"
                                }
                                else {
                                    $AclPartial++
                                    $AclResult = "DaclOnly"
                                }
                            }
                            catch {
                                $AclFailed++
                                $AclResult = "Failed"
                                $Note += "ACL: $( $_.Exception.Message ) "
                                Write-Warning "ACL copy failed: $Target => $( $_.Exception.Message )"
                            }
                        }

                        if ($VerifyHash) {
                            try {
                                $HashSrc = Get-StreamHash $File
                                $HashDst = Get-StreamHash $Target
                                if ($HashSrc -ceq $HashDst) {
                                    $Verified++
                                    $HashResult = "Match"
                                }
                                else {
                                    $warningText = @"
                                    HASH MISMATCH: $File

                                    Source $HashAlgorithm : $HashSrc
                                    Copy   $HashAlgorithm : $HashDst
"@
                                    $Mismatch++
                                    $HashResult = "MISMATCH"
                                    Write-Warning $warningText
                                }
                            }
                            catch {
                                $Failed++
                                $HashResult = "Error"
                                $Note += "Hash: $( $_.Exception.Message ) "
                                Write-Warning "Hash failed: $File => $( $_.Exception.Message )"
                            }
                        }
                    }
                }
                catch {
                    $Failed++
                    $Status = "Failed"
                    $Note += $_.Exception.Message
                    Write-Warning "Failed: $File => $( $_.Exception.Message )"
                }

                Write-LogRow `
                    -Type "File" `
                    -Status $Status `
                    -SrcPath $File `
                    -DstPath $Target `
                    -Size $F.Length `
                    -Modified $F.LastWriteTimeUtc.ToString("o") `
                    -HashSrc $HashSrc `
                    -HashDst $HashDst `
                    -HashResult $HashResult `
                    -AclResult $AclResult `
                    -Note $Note.Trim()

                # Throttled progress and log flush (per-file calls would be slow)
                if ($Clock.ElapsedMilliseconds - $LastUpdate -ge 500) {
                    $LastUpdate = $Clock.ElapsedMilliseconds
                    if ($Script:Log) {
                        $Script:Log.Flush()
                    }
                    Write-Progress -Activity "Copying" -Status ([string]::Format(
                        "{0:N0} files, {1:N1} MB  |  {2}",
                        $Copied,
                        ($Bytes / 1MB),
                        $Dir
                    ))
                }
            }

            <#
            Wrap the foreach loop with the 'if' guard.  Without it, file mode
            could recurse into every sibling subfolder of the source file's
            directory and copy the whole tree.
            #>
            if ($SourceType -eq "Dir") {
                foreach ($Sub in [IO.Directory]::EnumerateDirectories($Dir)) {
                    # Skip junctions/symlinks to avoid loops and unintended copies
                    if (([IO.File]::GetAttributes($Sub) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                        Write-Warning "Skipping reparse point: $Sub"
                        Write-LogRow `
                            -Type "Directory" `
                            -Status "SkippedReparsePoint" `
                            -SrcPath $Sub `
                            -DstPath "" `
                            -Size "" `
                            -Modified "" `
                            -HashSrc "" `
                            -HashDst "" `
                            -HashResult "" `
                            -AclResult "" `
                            -Note ""
                        continue
                    }
                    $Stack.Push($Sub)
                }
            }
        }
        catch {
            $Failed++
            Write-Warning "Failed on directory: $Dir => $( $_.Exception.Message )"
            Write-LogRow `
                -Type "Directory" `
                -Status "Failed" `
                -SrcPath $Dir `
                -DstPath $TargetDir `
                -Size "" `
                -Modified "" `
                -HashSrc "" `
                -HashDst "" `
                -HashResult "" `
                -AclResult "" `
                -Note $_.Exception.Message
        }
    }

    # Apply directory ACLs last, deepest first
    if ($CopyAcl) {
        Write-Progress -Activity "Applying directory ACLs" -Status "$( $AclDirs.Count ) directories"
        for ($I = $AclDirs.Count - 1; $I -ge 0; $I--) {
            $Sd  = $AclDirs[$I]
            $Rel = $Sd.Substring($SrcRoot.Length).TrimStart($Sep)
            $Td  = if ($Rel) {
                [IO.Path]::Combine($DstRoot, $Rel)
            }
            else {
                $DstRoot
            }
            $AclResult = ""
            $Note = ""
            try {
                if (Copy-Security -From $Sd -To $Td -IsDir $true) {
                    $AclResult = "Full"
                    $AclOk++
                }
                else {
                    $AclResult = "DaclOnly"
                    $AclPartial++
                }
            }
            catch {
                $AclResult = "Failed"
                $Note = $_.Exception.Message
                Write-Warning "ACL copy failed: $Td => $Note"
                $AclFailed++
            }

            Write-LogRow `
                -Type "Directory" `
                -Status "DirectoryAcl" `
                -SrcPath $Sd `
                -DstPath $Td `
                -Size "" `
                -Modified "" `
                -HashSrc "" `
                -HashDst "" `
                -HashResult "" `
                -AclResult $AclResult `
                -Note $Note
        }
    }
}
finally {
    if ($Script:Log) {
        # Flushes and closes, even on Ctrl+C or a fatal error
        $Script:Log.Dispose()
    }
}

Write-Progress -Activity "Copying" -Completed
Write-Progress -Activity "Applying directory ACLs" -Completed
$Clock.Stop()

$resultsText = @"
`n[-] RESULTS

    Files Copied   :  {0:N0} ({1:N2} MB)
    Files Skipped  :  {2:N0}
    Kept Both      :  {3:N0}
    Failed         :  {4:N0}
    Total Time     :  {5:hh\:mm\:ss}
"@

[string]::Format(
    $resultsText,
    $Copied,
    ($Bytes / 1MB),
    $Skipped,
    $Renamed,
    $Failed,
    $Clock.Elapsed
)

$hashVerifyText = @"
`n[-] HASH VERIFICATION

    Algorithm      :  {0}
    Matched        :  {1:N0}
    Mismatched     :  {2:N0}
"@

if ($VerifyHash) {
    [string]::Format(
        $hashVerifyText,
        $HashAlgorithm,
        $Verified,
        $Mismatch
    )
}

$aclText = @"
`n[-] ACLs COPIED

    Full           :  {0:N0}
    DACL-only      :  {1:N0} (owner/group not settable)
    Failed         :  {2:N0}
"@

if ($CopyAcl) {
    [string]::Format(
        $aclText,
        $AclOk,
        $AclPartial,
        $AclFailed
    )
}



if ($Failed -or $Mismatch -or $AclFailed) {
    exit 1
}

Add-Type -AssemblyName System.Runtime.windowsRuntime

[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime]
[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType=WindowsRuntime]

$NotifyType = "Windows.Defender.SecurityCenter"


if (Test-Path (Join-Path -Path $env:Temp -ChildPath "toast_img.jpg")) {
    $tempImg = Join-Path -Path $env:TEMP -ChildPath "toast_img.jpg"
}
else {
    $imgBytes = [System.Convert]::FromBase64String($embeddedImage)
    $tempImg = Join-Path -Path $env:TEMP -ChildPath "toast_img.jpg"
    [System.IO.File]::WriteAllBytes($tempImg, $imgBytes)
}

$toastSrc = "file:///" + ($tempImg -replace "\\", "/")


if ($LogFull) {
    $LogSafe = [System.Security.SecurityElement]::Escape($LogFull)
    $xml = @"
    <toast scenario="reminder">
        <visual>
            <binding template="ToastGeneric">
                <image src="$toastSrc" placement="hero" />
                <text>File copy complete!</text>
                <text>Log File  =>  $LogSafe</text>
            </binding>
        </visual>
        <actions>
            <action content="Dismiss"
                    activationType="system"
                    arguments="Dismiss" />
        </actions>
    </toast>
"@
}
else {
    $xml = @"
<toast scenario="reminder">
    <visual>
        <binding template="ToastGeneric">
            <image src="$toastSrc" placement="hero" />
            <text>File copy complete!</text>
        </binding>
    </visual>
    <actions>
        <action content="Dismiss"
                activationType="system"
                arguments="Dismiss" />
    </actions>
</toast>
"@
}


$doc = New-Object Windows.Data.Xml.Dom.XmlDocument
$doc.LoadXml($xml)

$toast    = [Windows.UI.Notifications.ToastNotification]::new($doc)
$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($NotifyType)
$notifier.show($toast)
