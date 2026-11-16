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
    CSV log file to write. Default: CopyLog_<timestamp>.csv in the current
    directory.

.PARAMETER NoLog
    Do not write a CSV log.

.EXAMPLE
    .\Copy-Tree.ps1 D:\Photos E:\Backup\Photos -CopyAcl -VerifyHash -LogPath `
    E:\Logs\photos.csv

    Copies all files from the D:\Photos folder to the E:\Backup\Photos folder,
    along with each files ACL.  Will verify the hash of each copied file and
    then write a Csv file to the folder specified in the '-LogPath' argument.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][string]$Source,
    [Parameter(Mandatory, Position = 1)][string]$Destination,
    [switch]$SkipIdentical,
    [switch]$CopyAcl,
    [switch]$VerifyHash,
    [ValidateSet('MD5', 'SHA1', 'SHA256', 'SHA384', 'SHA512')][string]$HashAlgorithm = 'SHA256',
    [string]$LogPath,
    [switch]$NoLog
)

$ErrorActionPreference = 'Stop'
$sep = [IO.Path]::DirectorySeparatorChar

function Resolve-FullPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path))
    if ($full -ne [IO.Path]::GetPathRoot($full)) { $full = $full.TrimEnd('\', '/') }
    $full
}

$src = Resolve-FullPath $Source
$dst = Resolve-FullPath $Destination

if (-not [IO.Directory]::Exists($src)) { throw "Source directory not found: $src" }
if ($src -ieq $dst) { throw "Source and destination are the same directory." }
if ($dst.StartsWith($src.TrimEnd($sep) + $sep, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Destination cannot be inside the source directory."
}

# ---------- CSV log ----------
$script:log = $null
$logFull = $null
if (-not $NoLog) {
    if (-not $LogPath) { $LogPath = "CopyLog_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date) }
    $logFull = Resolve-FullPath $LogPath
    if ($logFull.StartsWith($src.TrimEnd($sep) + $sep, [StringComparison]::OrdinalIgnoreCase)) {
        throw "The log file cannot be inside the source directory: $logFull"
    }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($logFull))
}

[void][IO.Directory]::CreateDirectory($dst)

$script:csvSpecial = [char[]]@(',', '"', "`r", "`n")

function ConvertTo-CsvField($Value) {
    if ($null -eq $Value) { return '' }
    $s = [string]$Value
    if ($s.IndexOfAny($script:csvSpecial) -ge 0) { return '"' + $s.Replace('"', '""') + '"' }
    $s
}

function Write-LogRow($Type, $Status, $SrcPath, $DstPath, $Size, $Modified, $HashSrc, $HashDst, $HashResult, $AclResult, $Note) {
    if (-not $script:log) { return }
    $algo = if ($VerifyHash) { $HashAlgorithm } else { '' }
    $vals = @([DateTime]::UtcNow.ToString('o'), $Type, $Status, $SrcPath, $DstPath, $Size, $Modified,
              $algo, $HashSrc, $HashDst, $HashResult, $AclResult, $Note)
    $parts = [string[]]::new($vals.Count)
    for ($i = 0; $i -lt $vals.Count; $i++) { $parts[$i] = ConvertTo-CsvField $vals[$i] }
    $script:log.WriteLine([string]::Join(',', $parts))
}

if ($logFull) {
    # UTF-8 with BOM so Excel reads non-ASCII file names correctly. Other programs can still read the file while it is being written.
    $script:log = [IO.StreamWriter]::new($logFull, $false, [Text.UTF8Encoding]::new($true))
    $script:log.WriteLine('TimestampUtc,Type,Status,SourcePath,DestinationPath,SizeBytes,SourceModifiedUtc,HashAlgorithm,SourceHash,DestinationHash,HashResult,AclResult,Note')
}

# ---------- Hashing: one reusable 1 MB buffer and one reusable hasher ----------
if ($VerifyHash) {
    $script:hasher = [Security.Cryptography.IncrementalHash]::CreateHash(
        [Security.Cryptography.HashAlgorithmName]::new($HashAlgorithm))
    $script:buffer = [byte[]]::new(1MB)
}

function Get-StreamHash([string]$Path) {
    # bufferSize 1 disables FileStream's own buffering; we read in 1 MB chunks ourselves
    $fs = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read,
                               [IO.FileShare]::ReadWrite, 1, [IO.FileOptions]::SequentialScan)
    try {
        while (($n = $fs.Read($script:buffer, 0, $script:buffer.Length)) -gt 0) {
            $script:hasher.AppendData($script:buffer, 0, $n)
        }
        [BitConverter]::ToString($script:hasher.GetHashAndReset()).Replace('-', '')
    }
    finally { $fs.Dispose() }
}

# ---------- NTFS security copy ----------
# PowerShell 5.1 (.NET Framework) exposes GetAccessControl on FileInfo/DirectoryInfo;
# PowerShell 7 (.NET Core) exposes it through FileSystemAclExtensions instead.
$script:UseExt = $PSVersionTable.PSVersion.Major -ge 6

# Returns $true if owner+group+DACL were copied, $false if only the DACL was.
function Copy-Security([string]$From, [string]$To, [bool]$IsDir) {
    if ($IsDir) { $f = [IO.DirectoryInfo]::new($From); $t = [IO.DirectoryInfo]::new($To) }
    else        { $f = [IO.FileInfo]::new($From);      $t = [IO.FileInfo]::new($To) }

    $full = [Security.AccessControl.AccessControlSections]'Access,Owner,Group'
    $dacl = [Security.AccessControl.AccessControlSections]::Access
    $lastError = $null

    foreach ($sections in @($full, $dacl)) {
        try {
            $sec = if ($script:UseExt) { [IO.FileSystemAclExtensions]::GetAccessControl($f, $sections) }
                   else                { $f.GetAccessControl($sections) }

            # Mark the sections as modified so they are actually written to the target
            $sec.SetAccessRuleProtection($sec.AreAccessRulesProtected, $true)
            if ($sections -eq $full) {
                $sec.SetOwner($sec.GetOwner([Security.Principal.SecurityIdentifier]))
                $sec.SetGroup($sec.GetGroup([Security.Principal.SecurityIdentifier]))
            }

            if ($script:UseExt) { [IO.FileSystemAclExtensions]::SetAccessControl($t, $sec) }
            else                { $t.SetAccessControl($sec) }
            return ($sections -eq $full)
        }
        catch { $lastError = $_ }
    }
    throw $lastError
}

# Returns "name (1).ext", "name (2).ext", ... for the first unused name
function Get-UniquePath([string]$Path) {
    $folder = [IO.Path]::GetDirectoryName($Path)
    $base   = [IO.Path]::GetFileNameWithoutExtension($Path)
    $ext    = [IO.Path]::GetExtension($Path)
    $i = 1
    do {
        $candidate = [IO.Path]::Combine($folder, "$base ($i)$ext")
        $i++
    } while ([IO.File]::Exists($candidate) -or [IO.Directory]::Exists($candidate))
    $candidate
}

$choices = @(
    [Management.Automation.Host.ChoiceDescription]::new('&Source',  'Overwrite the destination file with the source file')
    [Management.Automation.Host.ChoiceDescription]::new('&Destination', 'Keep the existing destination file (skip)')
    [Management.Automation.Host.ChoiceDescription]::new('&Both',    'Keep both; copy source under a new name')
    [Management.Automation.Host.ChoiceDescription]::new('Source for &All', 'Overwrite for this and all later conflicts')
    [Management.Automation.Host.ChoiceDescription]::new('Destination for all (&Keep)', 'Skip this and all later conflicts')
)

$policy = 'Prompt'     # Prompt | Source | Destination
$copied = 0; $skipped = 0; $renamed = 0; $failed = 0
$verified = 0; $mismatch = 0; $aclOk = 0; $aclPartial = 0; $aclFailed = 0
[long]$bytes = 0
$clock = [Diagnostics.Stopwatch]::StartNew()
$lastUpdate = 0

$aclDirs = [Collections.Generic.List[string]]::new()   # directories only; far fewer than files

$stack = [Collections.Generic.Stack[string]]::new()
$stack.Push($src)

try {
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        $rel = $dir.Substring($src.Length).TrimStart($sep)
        $targetDir = if ($rel) { [IO.Path]::Combine($dst, $rel) } else { $dst }

        try {
            [void][IO.Directory]::CreateDirectory($targetDir)
            if ($CopyAcl) { $aclDirs.Add($dir) }   # applied at the end so a restrictive ACL can't block the copy

            # DirectoryInfo.EnumerateFiles streams FileInfo objects (size/date come with the listing)
            foreach ($f in [IO.DirectoryInfo]::new($dir).EnumerateFiles()) {
                $file   = $f.FullName
                $target = [IO.Path]::Combine($targetDir, $f.Name)
                $status = ''; $aclResult = ''; $hashSrc = ''; $hashDst = ''; $hashResult = ''; $note = ''

                try {
                    $doCopy    = $true
                    $overwrite = $false
                    $status    = 'Copied'
                    $d = [IO.FileInfo]::new($target)

                    if ($d.Exists) {
                        if ($SkipIdentical -and $f.Length -eq $d.Length -and $f.LastWriteTimeUtc -eq $d.LastWriteTimeUtc) {
                            $skipped++; $doCopy = $false; $status = 'SkippedIdentical'
                        }
                        else {
                            $action = $policy
                            if ($policy -eq 'Prompt') {
                                $nl  = [Environment]::NewLine
                                $msg = "Conflict: $target" + $nl +
                                       ('  Source:      {0,15:N0} bytes   modified {1}' -f $f.Length, $f.LastWriteTime) + $nl +
                                       ('  Destination: {0,15:N0} bytes   modified {1}' -f $d.Length, $d.LastWriteTime)
                                Write-Progress -Activity 'Copying' -Completed
                                switch ($Host.UI.PromptForChoice('File already exists', $msg, $choices, 1)) {
                                    0 { $action = 'Source' }
                                    1 { $action = 'Destination' }
                                    2 { $action = 'Both' }
                                    3 { $action = 'Source';      $policy = 'Source' }
                                    4 { $action = 'Destination'; $policy = 'Destination' }
                                }
                            }

                            switch ($action) {
                                'Destination' { $skipped++; $doCopy = $false; $status = 'SkippedKeptDestination' }
                                'Both'        { $target = Get-UniquePath $target; $renamed++; $status = 'CopiedRenamed' }
                                'Source'      {
                                    $overwrite = $true
                                    $status    = 'Overwritten'
                                    # clears read-only/hidden/system so the overwrite can succeed
                                    [IO.File]::SetAttributes($target, [IO.FileAttributes]::Normal)
                                }
                            }
                        }
                    }

                    if ($doCopy) {
                        [IO.File]::Copy($file, $target, $overwrite)
                        $copied++
                        $bytes += $f.Length

                        if ($CopyAcl) {
                            try {
                                if (Copy-Security $file $target $false) { $aclOk++; $aclResult = 'Full' }
                                else                                    { $aclPartial++; $aclResult = 'DaclOnly' }
                            }
                            catch {
                                $aclFailed++; $aclResult = 'Failed'
                                $note += "ACL: $($_.Exception.Message) "
                                Write-Warning "ACL copy failed: $target -> $($_.Exception.Message)"
                            }
                        }

                        if ($VerifyHash) {
                            try {
                                $hashSrc = Get-StreamHash $file
                                $hashDst = Get-StreamHash $target
                                if ($hashSrc -ceq $hashDst) { $verified++; $hashResult = 'Match' }
                                else {
                                    $mismatch++; $hashResult = 'MISMATCH'
                                    Write-Warning "HASH MISMATCH: $file`n  source $HashAlgorithm : $hashSrc`n  copy   $HashAlgorithm : $hashDst"
                                }
                            }
                            catch {
                                $failed++; $hashResult = 'Error'
                                $note += "Hash: $($_.Exception.Message) "
                                Write-Warning "Hash failed: $file -> $($_.Exception.Message)"
                            }
                        }
                    }
                }
                catch {
                    $failed++
                    $status = 'Failed'
                    $note  += $_.Exception.Message
                    Write-Warning "Failed: $file -> $($_.Exception.Message)"
                }

                Write-LogRow 'File' $status $file $target $f.Length $f.LastWriteTimeUtc.ToString('o') `
                             $hashSrc $hashDst $hashResult $aclResult $note.Trim()

                # Throttled progress and log flush (per-file calls would be slow)
                if ($clock.ElapsedMilliseconds - $lastUpdate -ge 500) {
                    $lastUpdate = $clock.ElapsedMilliseconds
                    if ($script:log) { $script:log.Flush() }
                    Write-Progress -Activity 'Copying' -Status ("{0:N0} files, {1:N1} MB  |  {2}" -f $copied, ($bytes / 1MB), $dir)
                }
            }

            foreach ($sub in [IO.Directory]::EnumerateDirectories($dir)) {
                # Skip junctions/symlinks to avoid loops and unintended copies
                if (([IO.File]::GetAttributes($sub) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    Write-Warning "Skipping reparse point: $sub"
                    Write-LogRow 'Directory' 'SkippedReparsePoint' $sub '' '' '' '' '' '' '' ''
                    continue
                }
                $stack.Push($sub)
            }
        }
        catch {
            $failed++
            Write-Warning "Failed on directory: $dir -> $($_.Exception.Message)"
            Write-LogRow 'Directory' 'Failed' $dir $targetDir '' '' '' '' '' '' $_.Exception.Message
        }
    }

    # Apply directory ACLs last, deepest first
    if ($CopyAcl) {
        Write-Progress -Activity 'Applying directory ACLs' -Status "$($aclDirs.Count) directories"
        for ($i = $aclDirs.Count - 1; $i -ge 0; $i--) {
            $sd  = $aclDirs[$i]
            $rel = $sd.Substring($src.Length).TrimStart($sep)
            $td  = if ($rel) { [IO.Path]::Combine($dst, $rel) } else { $dst }
            $aclResult = ''; $note = ''
            try {
                if (Copy-Security $sd $td $true) { $aclOk++; $aclResult = 'Full' } else { $aclPartial++; $aclResult = 'DaclOnly' }
            }
            catch {
                $aclFailed++; $aclResult = 'Failed'; $note = $_.Exception.Message
                Write-Warning "ACL copy failed: $td -> $note"
            }
            Write-LogRow 'Directory' 'DirectoryAcl' $sd $td '' '' '' '' '' $aclResult $note
        }
    }
}
finally {
    if ($script:log) { $script:log.Dispose() }   # flushes and closes, even on Ctrl+C or a fatal error
}

Write-Progress -Activity 'Copying' -Completed
Write-Progress -Activity 'Applying directory ACLs' -Completed
$clock.Stop()

"{0:N0} copied ({1:N1} MB), {2:N0} skipped, {3:N0} kept-both, {4:N0} failed in {5:hh\:mm\:ss}" -f `
    $copied, ($bytes / 1MB), $skipped, $renamed, $failed, $clock.Elapsed
if ($VerifyHash) { "{0} verification: {1:N0} matched, {2:N0} MISMATCHED" -f $HashAlgorithm, $verified, $mismatch }
if ($CopyAcl)    { "ACLs: {0:N0} full, {1:N0} DACL-only (owner/group not settable), {2:N0} failed" -f $aclOk, $aclPartial, $aclFailed }
if ($logFull)    { "Log: $logFull" }

if ($failed -or $mismatch -or $aclFailed) { exit 1 }