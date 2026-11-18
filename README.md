# FileCopier (v0.2)

Tools for copying a directory tree on Windows and keeping a record of what happened: per-file logs, optional hash verification and, in the newer scripts, NTFS permissions.

The repository holds two generations of the same idea.

| File                                  | What it is                                                                                                                     |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| [`Copy-Files2.ps1`](Copy-Files2.ps1) | Standalone PowerShell script.  Native copy, per-file conflict prompts, optional ACL copy, optional hash verification, Csv log. |
| [`copy_files.py`](copy_files.py)     | Python port of `Copy-Files2.ps1` with the same features. Standard library only.                                              |
| [`Copy-Files.psm1`](Copy-Files.psm1) | Older PowerShell module of robocopy wrappers, with a logging variant and two SHA-1 verification variants (one with a GUI).     |

## Which One Should I Use?

- **Per-file conflict prompts, ACLs, a per-file hash log, low memory use:**  `Copy-Files2.ps1` or `copy_files.py`.
  - Choose the PowerShell script if you want nothing to install.
  - Choose the Python version if you prefer Python, or want hashing of the source and the copy to run in parallel and long-path support without a registry setting.
- **Robocopy speed (multithreaded) and a robocopy log:**  `Copy-Files` / `Copy-FilesWithLog` from the module.  Read the [`/MIR` warning](#warning-robocopy-mir) first.
- **A point-and-click window:**  `Copy-FilesWithLogAndHash` from the module.

## Requirements

- Windows.  The ACL features are Windows-only.
- `Copy-Files2.ps1` and `Copy-Files.psm1`:  Windows PowerShell 5.1 or PowerShell 7+.  The module's GUI functions need a desktop session.
- `copy_files.py`:  Python 3.8 or newer.  No third-party packages.  (On non-Windows systems it falls back to `shutil.copy2` and refuses `--copy-acl`.)
- Run elevated (Administrator) when copying ACLs if you want the original owner and group carried over.

If PowerShell blocks the script, run `Unblock-File .\Copy-Files2.ps1` or start it with `powershell -ExecutionPolicy Bypass -File .\Copy-Files2.ps1 ...`.

---

## Copy-Files2.ps1

```powershell
.\Copy-Files2.ps1 [-SourceType|-type <"dir"|"file">] [-Source|-src] <Source>
                  [-Destination|-dest] <Destination>
                  [-SkipIdentical] [-CopyAcl] [-VerifyHash|-verify]
                  [-HashAlgorithm|-hash <MD5|SHA1|SHA256|SHA512>]
                  [-LogPath|-logp <string>] [-LogFile|-logf <string>] [-NoLog]
```

```powershell
# Copy with ACLs, verify every file by hash, write the log to a chosen file
.\Copy-Files2.ps1 -type dir -Source D:\Photos -Destination E:\Backup\Photos -CopyAcl -VerifyHash -LogPath E:\Logs -LogFile photos
```

```powershell
# Re-run a copy and silently skip files that are already identical
.\Copy-Files2.ps1 -type dir -Source D:\Data -Destination E:\Backup\Data -SkipIdentical
```

If the path contains spaces, wrap the full path with either single or double quotes (e.g. *"D:\Photo Vault"* **or** *'E:\Backup\Vacation Photos'*)

| Parameter                     | Description                                                                                       |
| ----------------------------- | ------------------------------------------------------------------------------------------------- |
| `-Type`                     | Type of object being copied (either `File` or `Dir`)                                          |
| `-Source`\|`-src`         | Directory to copy (required).                                                                     |
| `-Destination`\|`-dest`   | Destination directory, created if it does not exist (required).                                   |
| `-SkipIdentical`            | On a conflict, skip silently when size and last-write time already match.                         |
| `-CopyAcl`                  | Copy NTFS security (DACL, owner, group) to each copied file and folder.                           |
| `-VerifyHash`\|`-verify`  | After each copy, hash the source and the copy and compare them.                                   |
| `-HashAlgorithm`\|`-hash` | `MD5`, `SHA1`, `SHA256` (default), or `SHA512`.                                           |
| `-LogPath`\|`-logp`       | Directory where the Csv log file will be saved.                                                   |
| `-LogFile`\|`-logf`       | Name of the Csv log file (without file extension). A timestamp will be appended to the beginning. |
| `-NoLog`                    | Do not write a Csv log.                                                                           |

## copy_files.py

```python
python copy_files.py [-s|--source] <source> [-d|--dest] <destination> [--skip-identical] [--copy-acl]
                     [-v|--verify-hash] [-a|--hash-algorithm {md5,sha1,sha256,sha512}]
                     [--csv <log folder>] [--csvf <log name>] [--no-log]
```

```python
python copy_files.py -source D:\Photos -dest E:\Backup\Photos --copy-acl --verify-hash --csv E:\Logs --csvf photos
```

- Copies all files from `D:\Photos` to `E:\Backup\Photos`, copies the ACL data, verifies the hash value (using the default value SHA256) of each copied file and writes the Csv log to `E:\Logs\<YYYY.MM.DD_HH.MM.SS>_photos.csv`.

```python
python copy_files.py -source D:\Photos -dest E:\Backup\Photos --copy-acl --verify-hash SHA1 --csv E:\Logs --csvf "copy log"
```

- Copies all files from `D:\Photos` to `E:\Backup\Photos`, copies the ACL data, verifies the hash value (using the SHA1 algorithm) of each copied file and writes the Csv log to `E:\Logs\<YYYY.MM.DD_HH.MM.SS>_copy log.csv`.

```python
python copy_files.py -s D:\Data -d E:\Backup\Data --skip-identical --no-log
```

- Copies all files from `D:\Data` to `E:\Backup\Data`.  Any identical files are skipped and no Csv log will be written.

If the any of the paths or the file name contains spaces, wrap the full path with either single or double quotes (e.g. *"D:\Photo Vault"* **or** *'E:\Backup\Vacation Photos'*)

| Argument                     | Description                                                                      |
| ---------------------------- | -------------------------------------------------------------------------------- |
| `-s`, `--source`         | Directory to copy.                                                               |
| `-d`, `--destination`    | Destination directory, created if it does not exist.                             |
| `--skip-identical`         | On a conflict, skip silently when size and last-write time already match.        |
| `--copy-acl`               | Copy NTFS security (DACL, owner, group). Windows only.                           |
| `-v`, `--verify-hash`    | After each copy, hash the source and the copy and compare them.                  |
| `-a`, `--hash-algorithm` | `md5`, `sha1`, `sha256` (default), or `sha512`.                          |
| `--csv`                    | Folder to save the Csv log in.                                                   |
| `--csvf`                   | Name for the Csv log. The file is saved as `<YYYY.MM.DD_HH.MM.SS>_<name>.csv`. |
| `--no-log`                 | Do not write a Csv log. Without it, `--csv` and `--csvf` are both needed.    |

**Differences from the PowerShell script:**  The source and the copy are hashed on two threads at once, every path is passed to Windows with the `\\?\` prefix so paths over 260 characters work, and `SeRestorePrivilege` / `SeTakeOwnershipPrivilege` are enabled when `--copy-acl` is used and the process is elevated.  Exit code `130` means the run was interrupted with [Ctrl + C].

---

## How The Scripts Behave

These points apply to both `Copy-Files2.ps1` and `copy_files.py`.

**Copying.**  Files are copied one at a time with the native Windows copy API, which preserves timestamps, attributes and alternate data streams.  Directories are enumerated lazily and iteratively, so memory use stays flat for very large trees and files.

**Conflicts.**  If a file already exists at the destination you are asked what to do, with the size and modified time of both files shown:

| Choice                     | Result                                                            |
| -------------------------- | ----------------------------------------------------------------- |
| Source                     | Overwrite the destination file.                                   |
| Destination (default)      | Keep the existing file and skip.                                  |
| Both                       | Copy the source as `name (1).ext`, `name (2).ext`, and so on.     |
| Source for all             | Overwrite on this and every later conflict.                       |
| Destination for all (Keep) | Skip this and every later conflict.                               |

**ACLs.**  The DACL, owner and group are copied.  SACLs (audit rules) are not.  If the owner or group cannot be set, the DACL is still copied and the file is reported as `DaclOnly`.  Directory ACLs are applied at the end, deepest first, so a restrictive folder ACL cannot block the copy itself.  Explicit entries are copied exactly.  Inherited entries are re-derived by Windows from the destination's parent folder.  If you need a byte-exact security descriptor, `robocopy /SEC` is the better tool.

**Hash verification.**  The source file and the copy are each streamed through a reusable 1 MB buffer and compared.  A mismatch is reported as a warning, logged, and makes the run exit with a failure code.  The copy is read back soon after it is written, so Windows may serve part of it from cache.  That catches copy errors but is not proof of what is on disk.  For that, hash again later with a cold cache.

**Csv log.**  One row per file, written as the copy runs and flushed twice a second, so an interrupted run leaves a usable log.  The file is UTF-8 with a BOM so Excel reads non-ASCII names correctly, and it cannot be placed inside the source folder.

| Column                                                 | Contents                                                                                                                                                    |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `TimestampUtc`                                       | When the row was written.                                                                                                                                   |
| `Type`                                               | `File` or `Directory`.                                                                                                                                  |
| `Status`                                             | `Copied`, `CopiedRenamed`, `Overwritten`, `SkippedIdentical`, `SkippedKeptDestination`, `Failed`, `DirectoryAcl`, or `SkippedReparsePoint`. |
| `SourcePath`, `DestinationPath`                    | Full paths.  For "Both", the destination is the new `name (1).ext`.                                                                                     |
| `SizeBytes`, `SourceModifiedUtc`                   | Size and last-write time of the source file.                                                                                                                |
| `HashAlgorithm`, `SourceHash`, `DestinationHash` | Filled in when hash verification is on.                                                                                                                     |
| `HashResult`                                         | `Match`, `MISMATCH`, or `Error`.                                                                                                                      |
| `AclResult`                                          | `Full`, `DaclOnly`, or `Failed`.                                                                                                                      |
| `Note`                                               | Error text for failures.                                                                                                                                    |

**Exit code.**  `0` on success. `1` if any file failed, any hash mismatched or any ACL copy failed.

**Limits.**

- Junctions and symbolic-linked folders are skipped and logged as `SkippedReparsePoint`.
- The destination cannot be inside the source.
- Files locked by another process fail and are logged.
- The directory ACL pass can be slow on very large or deep trees, because Windows propagates inheritable changes to child objects.
- `Copy-Files2.ps1` needs Windows long-path support enabled for paths over 260 characters (or PowerShell 7+).

---

## Copy-Files.psm1

The older module.  It wraps `robocopy` and loads with a short banner listing its functions.

First, import the `Copy-Files` PowerShell module:

```powershell
Import-Module .\Copy-Files.psm1
```

---

## Warning: robocopy `/MIR`

`Copy-Files`, `Copy-FilesWithLog`, and `Copy-FilesWithLogAndHash` run robocopy in mirror mode.

**Files that exist in the destination but not in the source are deleted.**

Use an empty or dedicated destination, never a folder that holds other data.

| Function                                                  | What it does                                                                                                                                                                                                                                                                                                                                                                      |
| --------------------------------------------------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Copy-Files <Source> <Destination>`                     | Runs `robocopy` with `/MIR /MT /TEE /DCOPY:DAT /V /TS /FP`:  multithreaded, echoed to the console, verbose, with timestamps and full paths.   Data, attributes and timestamps are copied; ACLs are not.                                                                                                                                                                     |
| `Copy-FilesWithLog <Source> <Destination> <CaseNumber>` | Same copy, plus a log.  The destination is created if missing.  The log is written to a `__COPY-LOGS` folder next to the destination as `<yyyy-MM-dd_HHmmss>_<CaseNumber>_filecopy.log` (UTC) and is appended to if it already exists.                                                                                                                                     |
| `Copy-FilesWithLogAndHash`                              | Opens a Windows Forms dialog (no parameters).  Pick or type the source and destination, then click **Copy and Verify**.  It runs the robocopy mirror, writes `<timestamp>_filecopy.log` and a `<timestamp>_HashCheckLog.csv` to `HashCheckLogs` on the Desktop, compares SHA-1 hashes of the source files and the copies, and offers to show the results in a grid. |
| `Copy-FilesAndVerify <Source> <Destination>`            | Copies each item with `Copy-Item`, computes SHA-1 for the source and the copy, and shows `Source-File`, `Destination-File`, `Source-Hash`, `Destination-Hash` and `Hash-Verified` in a grid window.                                                                                                                                                                   |
| `Get-FolderHash <Directory>`                            | Returns one SHA-1 value over the contents and names of every file in a folder.  It loads all file contents into memory, so use it on small folders only.                                                                                                                                                                                                                         |

The module's hashing is SHA-1 only.  For stronger algorithms, a per-file log and lower memory use, use `Copy-Files2.ps1` or `copy_files.py`.

---

Author: @mikespon
