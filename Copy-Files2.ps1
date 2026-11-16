<#
.SYNOPSIS
    Recursively copies a directory tree with low memory use and per-file
    conflict prompts.

.PARAMETER Source
    Directory to copy.

.PARAMETER Destination
    Destination directory (created if it does not exist).

.PARAMETER SkipIdentical
    Silently skip conflicts where size and last-write time already match.

.PARAMETER CopyAcl
    Copy NTFS security (DACL, owner, group) from each source file/folder
    to its copy.  Falls back to DACL only if the owner/group cannot be set
    (run elevated for full fidelity).

.PARAMETER VerifyHash
    After each copy, hash the source and the copy and compare them.

.PARAMETER HashAlgorithm
    MD5, SHA1, SHA256 (default), SHA384 or SHA512.

.PARAMETER LogPath
    CSV log file to write.  Default: CopyLog_<timestamp>.csv in the current
    directory.

.PARAMETER NoLog
    Do not write a CSV log.

.EXAMPLE
    .\Copy-Files2.ps1 D:\Photos E:\Backup\Photos -CopyAcl -VerifyHash -LogPath `
    E:\Logs\photos.csv

    Copies all files from the D:\Photos folder to the E:\Backup\Photos folder,
    along with each files ACL.  Will verify the hash of each copied file and
    then write a Csv file to the folder specified in the '-LogPath' argument.
#>
[CmdletBinding()]
param
(
    [Parameter(Mandatory, Position = 0)]
    [string]$Source,

    [Parameter(Mandatory, Position = 1)]
    [string]$Destination,

    [switch]$SkipIdentical,
    [switch]$CopyAcl,

    [Alias("Verify")]
    [switch]$VerifyHash,

    [ValidateSet("MD5", "SHA1", "SHA256", "SHA384", "SHA512")]
    [string]$HashAlgorithm = "SHA256",

    [string]$LogPath,
    [switch]$NoLog
)

$ErrorActionPreference = "Stop"
$Sep = [IO.Path]::DirectorySeparatorChar

function Resolve-FullPath
{
    param
    (
        [string]$Path
    )

    $Full = [IO.Path]::GetFullPath($PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path))

    if ($Full -ne [IO.Path]::GetPathRoot($Full))
    {
        $Full = $Full.TrimEnd("\", "/")
    }

    $Full
}

$Src = Resolve-FullPath $Source
$Dst = Resolve-FullPath $Destination

if (-not [IO.Directory]::Exists($Src))
{
    throw "Source directory not found: $Src"
}

if ($Src -ieq $Dst)
{
    throw "Source and destination are the same directory."
}

if ($Dst.StartsWith($Src.TrimEnd($Sep) + $Sep, [StringComparison]::OrdinalIgnoreCase))
{
    throw "Destination cannot be inside the source directory."
}

# ---------- CSV log ----------
$Script:Log = $Null
$LogFull = $Null

if (-not $NoLog)
{
    if (-not $LogPath)
    {
        $LogPath = [string]::Format("{0:yyyy.MM.dd_HH.mm.ss}_copy_log.csv", (Get-Date))
    }

    $LogFull = Resolve-FullPath $LogPath

    if ($LogFull.StartsWith($Src.TrimEnd($Sep) + $Sep, [StringComparison]::OrdinalIgnoreCase))
    {
        Write-Warning "The log file cannot be inside the source directory: $LogFull"
        exit 1
    }

    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($LogFull))
}

[void][IO.Directory]::CreateDirectory($Dst)

$Script:CsvSpecial = [char[]]@(',', '"', "`r", "`n")

function ConvertTo-CsvField
{
    param
    (
        [string]$Value
    )

    if ($Null -eq $Value)
    {
        return ""
    }

    $S = [string]$Value

    if ($S.IndexOfAny($Script:CsvSpecial) -ge 0)
    {
        return '"' + $S.Replace('"', '""') + '"'
    }
    $S
}

function Write-LogRow
{
    param
    (
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

    if (-not $Script:Log)
    {
        return
    }

    $Algo = if ($VerifyHash)
    {
        $HashAlgorithm
    }
    else
    {
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

    for ($I = 0; $I -lt $Vals.Count; $I++)
    {
        $Parts[$I] = ConvertTo-CsvField $Vals[$I]
    }
    $Script:Log.WriteLine([string]::Join(",", $Parts))
}

if ($LogFull)
{
    # UTF-8 with BOM so Excel reads non-ASCII file names correctly.
    # Other programs can still read the file while it is being written.
    $Script:Log = [IO.StreamWriter]::new(
        $LogFull,
        $False,
        [Text.UTF8Encoding]::new($True)
    )
    $Script:Log.WriteLine('TimestampUtc,Type,Status,SourcePath,DestinationPath,SizeBytes,SourceModifiedUtc,HashAlgorithm,SourceHash,DestinationHash,HashResult,AclResult,Note')
}

# ---------- Hashing: one reusable 1 MB buffer and one reusable hasher ----------
if ($VerifyHash)
{
    $Script:Hasher = [Security.Cryptography.IncrementalHash]::CreateHash(
        [Security.Cryptography.HashAlgorithmName]::new($HashAlgorithm))
    $Script:Buffer = [byte[]]::new(1MB)
}

function Get-StreamHash
{
    param
    (
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
    try
    {
        while (($N = $Fs.Read($Script:Buffer, 0, $Script:Buffer.Length)) -gt 0)
        {
            $Script:Hasher.AppendData($Script:Buffer, 0, $N)
        }
        [BitConverter]::ToString($Script:Hasher.GetHashAndReset()).Replace("-", "")
    }
    finally
    {
        $Fs.Dispose()
    }
}

# ---------- NTFS security copy ----------
# PowerShell 5.1 (.NET Framework) exposes GetAccessControl on FileInfo/DirectoryInfo;
# PowerShell 7 (.NET Core) exposes it through FileSystemAclExtensions instead.
$Script:UseExt = $PSVersionTable.PSVersion.Major -ge 6

# Returns $True if owner+group+DACL were copied, $False if only the DACL was.
function Copy-Security
{
    param
    (
        [string]$From,
        [string]$To,
        [bool]$IsDir
    )

    if ($IsDir)
    {
        $F = [IO.DirectoryInfo]::new($From)
        $T = [IO.DirectoryInfo]::new($To)
    }
    else
    {
        $F = [IO.FileInfo]::new($From)
        $T = [IO.FileInfo]::new($To)
    }

    $Full = [Security.AccessControl.AccessControlSections]"Access,Owner,Group"
    $Dacl = [Security.AccessControl.AccessControlSections]::Access
    $LastError = $Null

    foreach ($Sections in @($Full, $Dacl))
    {
        try
        {
            $Sec = if ($Script:UseExt)
            {
                [IO.FileSystemAclExtensions]::GetAccessControl($F, $Sections)
            }
            else
            {
                $F.GetAccessControl($Sections)
            }

            # Mark the sections as modified so they are actually written to the target
            $Sec.SetAccessRuleProtection($Sec.AreAccessRulesProtected, $True)
            if ($Sections -eq $Full)
            {
                $Sec.SetOwner($Sec.GetOwner([Security.Principal.SecurityIdentifier]))
                $Sec.SetGroup($Sec.GetGroup([Security.Principal.SecurityIdentifier]))
            }

            if ($Script:UseExt)
            {
                [IO.FileSystemAclExtensions]::SetAccessControl($T, $Sec)
            }
            else
            {
                $T.SetAccessControl($Sec)
            }
            return ($Sections -eq $Full)
        }
        catch
        {
            $LastError = $_
        }
    }
    throw $LastError
}


# Returns "name (1).ext", "name (2).ext", ... for the first unused name
function Get-UniquePath
{
    param
    (
        [string]$Path
    )

    $Folder = [IO.Path]::GetDirectoryName($Path)
    $Base   = [IO.Path]::GetFileNameWithoutExtension($Path)
    $Ext    = [IO.Path]::GetExtension($Path)
    $I = 1
    do
    {
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
$Policy = "Prompt"
[int]$Copied = 0
[int]$Skipped = 0
[int]$Renamed = 0
[int]$Failed = 0
[int]$Verified = 0
[int]$Mismatch = 0
[int]$AclOk = 0
[int]$AclPartial = 0
[int]$AclFailed = 0
[long]$Bytes = 0
$Clock = [Diagnostics.Stopwatch]::StartNew()
$LastUpdate = 0

# Directories only; far fewer than files
$AclDirs = [Collections.Generic.List[string]]::new()

$Stack = [Collections.Generic.Stack[string]]::new()
$Stack.Push($Src)

try
{
    while ($Stack.Count -gt 0)
    {
        $Dir = $Stack.Pop()
        $Rel = $Dir.Substring($Src.Length).TrimStart($Sep)
        $TargetDir = if ($Rel)
        {
            [IO.Path]::Combine($Dst, $Rel)
        }
        else
        {
            $Dst
        }

        try
        {
            [void][IO.Directory]::CreateDirectory($TargetDir)
            # Applied at the end so a restrictive ACL can't block the copy
            if ($CopyAcl)
            {
                $AclDirs.Add($Dir)
            }

            # DirectoryInfo.EnumerateFiles streams FileInfo objects
            # (size/date come with the listing)
            foreach ($F in [IO.DirectoryInfo]::new($Dir).EnumerateFiles())
            {
                $File   = $F.FullName
                $Target = [IO.Path]::Combine($TargetDir, $F.Name)
                $Status = ""
                $AclResult = ""
                $HashSrc = ""
                $HashDst = ""
                $HashResult = ""
                $Note = ""

                try
                {
                    $DoCopy    = $True
                    $Overwrite = $False
                    $Status    = "Copied"
                    $D = [IO.FileInfo]::new($Target)

                    if ($D.Exists)
                    {
                        if ($SkipIdentical -and $F.Length -eq $D.Length `
                            -and $F.LastWriteTimeUtc -eq $D.LastWriteTimeUtc)
                        {
                            $Skipped++
                            $DoCopy = $False
                            $Status = "SkippedIdentical"
                        }
                        else
                        {
                            $Action = $Policy
                            if ($Policy -eq "Prompt")
                            {
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

                                switch ($Host.UI.PromptForChoice("File already exists", $Msg, $Choices, 1))
                                {
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

                            switch ($Action)
                            {
                                "Destination"
                                {
                                    $Skipped++
                                    $DoCopy = $False
                                    $Status = "SkippedKeptDestination"
                                }
                                "Both"
                                {
                                    $Target = Get-UniquePath $Target
                                    $Renamed++
                                    $Status = "CopiedRenamed"
                                }
                                "Source"
                                {
                                    $Overwrite = $True
                                    $Status    = "Overwritten"
                                    # Clears read-only/hidden/system so the overwrite can succeed
                                    [IO.File]::SetAttributes($Target, [IO.FileAttributes]::Normal)
                                }
                            }
                        }
                    }

                    if ($DoCopy)
                    {
                        [IO.File]::Copy($File, $Target, $Overwrite)
                        $Copied++
                        $Bytes += $F.Length

                        if ($CopyAcl)
                        {
                            try
                            {
                                if (Copy-Security -From $File -To $Target -IsDir $False)
                                {
                                    $AclOk++
                                    $AclResult = "Full"
                                }
                                else
                                {
                                    $AclPartial++
                                    $AclResult = "DaclOnly"
                                }
                            }
                            catch
                            {
                                $AclFailed++
                                $AclResult = "Failed"
                                $Note += "ACL: $( $_.Exception.Message ) "
                                Write-Warning "ACL copy failed: $Target => $( $_.Exception.Message )"
                            }
                        }

                        if ($VerifyHash)
                        {
                            try
                            {
                                $HashSrc = Get-StreamHash $File
                                $HashDst = Get-StreamHash $Target
                                if ($HashSrc -ceq $HashDst)
                                {
                                    $Verified++
                                    $HashResult = "Match"
                                }
                                else
                                {
                                    $Mismatch++
                                    $HashResult = "MISMATCH"
                                    Write-Warning "HASH MISMATCH: $File`n  source $HashAlgorithm : $HashSrc`n  copy   $HashAlgorithm : $HashDst"
                                }
                            }
                            catch
                            {
                                $Failed++
                                $HashResult = "Error"
                                $Note += "Hash: $( $_.Exception.Message ) "
                                Write-Warning "Hash failed: $File => $( $_.Exception.Message )"
                            }
                        }
                    }
                }
                catch
                {
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
                if ($Clock.ElapsedMilliseconds - $LastUpdate -ge 500)
                {
                    $LastUpdate = $Clock.ElapsedMilliseconds
                    if ($Script:Log)
                    {
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

            foreach ($Sub in [IO.Directory]::EnumerateDirectories($Dir))
            {
                # Skip junctions/symlinks to avoid loops and unintended copies
                if (([IO.File]::GetAttributes($Sub) -band [IO.FileAttributes]::ReparsePoint) -ne 0)
                {
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
        catch
        {
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
    if ($CopyAcl)
    {
        Write-Progress -Activity "Applying directory ACLs" -Status "$( $AclDirs.Count ) directories"
        for ($I = $AclDirs.Count - 1; $I -ge 0; $I--)
        {
            $Sd  = $AclDirs[$I]
            $Rel = $Sd.Substring($Src.Length).TrimStart($Sep)
            $Td  = if ($Rel)
            {
                [IO.Path]::Combine($Dst, $Rel)
            }
            else
            {
                $Dst
            }
            $AclResult = ""
            $Note = ""
            try
            {
                if (Copy-Security -From $Sd -To $Td -IsDir $True)
                {
                    $AclOk++
                    $AclResult = "Full"
                }
                else
                {
                    $AclPartial++
                    $AclResult = "DaclOnly"
                }
            }
            catch
            {
                $AclFailed++
                $AclResult = "Failed"
                $Note = $_.Exception.Message
                Write-Warning "ACL copy failed: $Td => $Note"
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
finally
{
    if ($Script:Log)
    {
        # Flushes and closes, even on Ctrl+C or a fatal error
        $Script:Log.Dispose()
    }
}

Write-Progress -Activity "Copying" -Completed
Write-Progress -Activity "Applying directory ACLs" -Completed
$Clock.Stop()

[string]::Format(
    "{0:N0} copied ({1:N1} MB), {2:N0} skipped, {3:N0} kept-both, {4:N0} failed in {5:hh\:mm\:ss}",
    $Copied,
    ($Bytes / 1MB),
    $Skipped,
    $Renamed,
    $Failed,
    $Clock.Elapsed
)

if ($VerifyHash)
{
    [string]::Format(
        "{0} verification: {1:N0} matched, {2:N0} MISMATCHED",
        $HashAlgorithm,
        $Verified,
        $Mismatch
    )
}

if ($CopyAcl)
{
    [string]::Format(
        "ACLs: {0:N0} full, {1:N0} DACL-only (owner/group not settable), {2:N0} failed",
        $AclOk,
        $AclPartial,
        $AclFailed
    )
}

if ($LogFull)
{
    "Log: $LogFull"
}

if ($Failed -or $Mismatch -or $AclFailed)
{
    exit 1
}
