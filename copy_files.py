#!/usr/bin/env python3

"""
copy_tree.py - Recursively copy a directory tree (Windows) with low memory use,
per-file conflict prompts, optional NTFS ACL copy, optional hash verification
and a CSV log.

Usage:
    python copy_tree.py SOURCE DESTINATION [options]

Examples:
    python copy_tree.py D:\Photos E:\Backup\Photos --copy-acl --verify-hash

    python copy_tree.py D:\Data E:\Backup\Data --verify-hash --hash-algorithm sha512 --log-path E:\Logs\data.csv
"""
from __future__ import annotations

import argparse
import csv
import ctypes
import hashlib
import os
import shutil
import stat
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

IS_WIN = os.name == "nt"
SEP = os.sep
CHUNK = 1 << 20  # 1 MB hashing buffer

FILE_ATTRIBUTE_DIRECTORY = 0x10
FILE_ATTRIBUTE_REPARSE_POINT = 0x400
FILE_ATTRIBUTE_NORMAL = 0x80
COPY_FILE_FAIL_IF_EXISTS = 0x1

COLUMNS = [
    "TimestampUtc",
    "Type",
    "Status",
    "SourcePath",
    "DestinationPath",
    "SizeBytes",
    "SourceModifiedUtc",
    "HashAlgorithm",
    "SourceHash",
    "DestinationHash",
    "HashResult",
    "AclResult",
    "Note",
]


def W(path: str) -> str:
    """Add the \\\\?\\ prefix so paths longer than 260 characters work on
    Windows operating systems.
    """
    if not IS_WIN or path.startswith("\\\\?\\"):
        return path
    if path.startswith("\\\\"):
        return "\\\\?\\UNC\\" + path[2:]
    return "\\\\?\\" + path


# ------------------------------
# Windows native APIs
# (ctypes, no third-party packages)
# ------------------------------
if IS_WIN:
    from ctypes import wintypes

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    advapi32 = ctypes.WinDLL("advapi32", use_last_error=True)

    kernel32.CopyFileExW.argtypes = [
        wintypes.LPCWSTR,
        wintypes.LPCWSTR,
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_void_p,
        wintypes.DWORD,
    ]
    kernel32.CopyFileExW.restype = wintypes.BOOL
    kernel32.SetFileAttributesW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD]
    kernel32.SetFileAttributesW.restype = wintypes.BOOL
    kernel32.GetCurrentProcess.restype = wintypes.HANDLE
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel32.LocalFree.argtypes = [ctypes.c_void_p]
    kernel32.LocalFree.restype = ctypes.c_void_p

    PVOID_P = ctypes.POINTER(ctypes.c_void_p)
    advapi32.GetNamedSecurityInfoW.argtypes = [
        wintypes.LPCWSTR,
        ctypes.c_int,
        wintypes.DWORD,
        PVOID_P,
        PVOID_P,
        PVOID_P,
        PVOID_P,
        PVOID_P,
    ]
    advapi32.GetNamedSecurityInfoW.restype = wintypes.DWORD
    advapi32.SetNamedSecurityInfoW.argtypes = [
        wintypes.LPCWSTR,
        ctypes.c_int,
        wintypes.DWORD,
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_void_p,
    ]
    advapi32.SetNamedSecurityInfoW.restype = wintypes.DWORD
    advapi32.GetSecurityDescriptorControl.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(wintypes.WORD),
        ctypes.POINTER(wintypes.DWORD),
    ]
    advapi32.GetSecurityDescriptorControl.restype = wintypes.BOOL

    class LUID(ctypes.Structure):
        _fields_ = [
            ("LowPart", wintypes.DWORD),
            ("HighPart", wintypes.LONG)
        ]

    class LUID_AND_ATTRIBUTES(ctypes.Structure):
        _fields_ = [
            ("Luid", LUID),
            ("Attributes", wintypes.DWORD)
        ]

    class TOKEN_PRIVILEGES(ctypes.Structure):
        _fields_ = [
            ("PrivilegeCount", wintypes.DWORD),
            ("Privileges", LUID_AND_ATTRIBUTES * 1),
        ]

    advapi32.OpenProcessToken.argtypes = [
        wintypes.HANDLE,
        wintypes.DWORD,
        ctypes.POINTER(wintypes.HANDLE),
    ]
    advapi32.OpenProcessToken.restype = wintypes.BOOL
    advapi32.LookupPrivilegeValueW.argtypes = [
        wintypes.LPCWSTR,
        wintypes.LPCWSTR,
        ctypes.POINTER(LUID),
    ]
    advapi32.LookupPrivilegeValueW.restype = wintypes.BOOL
    advapi32.AdjustTokenPrivileges.argtypes = [
        wintypes.HANDLE,
        wintypes.BOOL,
        ctypes.POINTER(TOKEN_PRIVILEGES),
        wintypes.DWORD,
        ctypes.c_void_p,
        ctypes.c_void_p
    ]
    advapi32.AdjustTokenPrivileges.restype = wintypes.BOOL

    SE_FILE_OBJECT = 1
    OWNER_SECURITY_INFORMATION = 0x1
    GROUP_SECURITY_INFORMATION = 0x2
    DACL_SECURITY_INFORMATION = 0x4
    PROTECTED_DACL_SECURITY_INFORMATION = 0x80000000
    UNPROTECTED_DACL_SECURITY_INFORMATION = 0x20000000
    SE_DACL_PROTECTED = 0x1000


def enable_privileges(names) -> None:
    """Enable privileges (needed to set an arbitrary owner) when running
    elevated.  Failures are ignored."""
    if not IS_WIN:
        return
    token = wintypes.HANDLE()
    # TOKEN_ADJUST_PRIVILEGES (0x20) | TOKEN_QUERY (0x8)
    if not advapi32.OpenProcessToken(
        kernel32.GetCurrentProcess(),
        0x28,
        ctypes.byref(token)
    ):
        return
    try:
        for name in names:
            luid = LUID()
            if not advapi32.LookupPrivilegeValueW(
                None,
                name,
                ctypes.byref(luid)
            ):
                continue
            tp = TOKEN_PRIVILEGES()
            tp.PrivilegeCount = 1
            tp.Privileges[0].Luid = luid
            tp.Privileges[0].Attributes = 0x2  # SE_PRIVILEGE_ENABLED
            advapi32.AdjustTokenPrivileges(
                token, False,
                ctypes.byref(tp),
                0,
                None,
                None,
            )
    finally:
        kernel32.CloseHandle(token)


def copy_security(src: str, dst: str) -> bool:
    """Copy owner, group and DACL of target file.

    Returns:
        True if all three were copied,
        False if only the DACL could be (owner/group not settable).

    Raises:
        OSError on failure.
    """
    owner, group, dacl, sd = (ctypes.c_void_p() for _ in range(4))
    rc = advapi32.GetNamedSecurityInfoW(
        W(src),
        SE_FILE_OBJECT,
        OWNER_SECURITY_INFORMATION | GROUP_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION,
        ctypes.byref(owner),
        ctypes.byref(group),
        ctypes.byref(dacl),
        None,
        ctypes.byref(sd),
    )
    if rc:
        raise ctypes.WinError(rc)
    try:
        control, revision = wintypes.WORD(), wintypes.DWORD()
        protected = bool(
            advapi32.GetSecurityDescriptorControl(
                sd,
                ctypes.byref(control),
                ctypes.byref(revision)
            )
            and control.value & SE_DACL_PROTECTED
        )
        dacl_flags = DACL_SECURITY_INFORMATION | (
            PROTECTED_DACL_SECURITY_INFORMATION
            if protected else UNPROTECTED_DACL_SECURITY_INFORMATION
        )

        rc = advapi32.SetNamedSecurityInfoW(
            W(dst),
            SE_FILE_OBJECT,
            dacl_flags | OWNER_SECURITY_INFORMATION | GROUP_SECURITY_INFORMATION,
            owner,
            group,
            dacl,
            None,
        )
        if rc == 0:
            return True
        rc = advapi32.SetNamedSecurityInfoW(
            W(dst),
            SE_FILE_OBJECT,
            dacl_flags,
            None,
            None,
            dacl,
            None,
        )
        if rc == 0:
            return False
        raise ctypes.WinError(rc)
    finally:
        kernel32.LocalFree(sd)


def copy_file(src: str, dst: str, overwrite: bool) -> None:
    """Native CopyFileExW: streams in the kernel, keeps timestamps,
    attributes and alternate data streams.
    """
    if IS_WIN:
        flags = 0 if overwrite else COPY_FILE_FAIL_IF_EXISTS
        if not kernel32.CopyFileExW(W(src), W(dst), None, None, None, flags):
            raise ctypes.WinError(ctypes.get_last_error())
    # Fallback so the script can be tried on other platforms
    else:
        if not overwrite and os.path.exists(dst):
            raise FileExistsError(dst)
        shutil.copy2(src, dst)


def clear_attributes(path: str) -> None:
    """Clear read-only/hidden/system so an overwrite can succeed.

    Args:
        path: Path of the subject file.

    Returns:
        None

    Raises:
        OSError
    """
    try:
        if IS_WIN:
            kernel32.SetFileAttributesW(W(path), FILE_ATTRIBUTE_NORMAL)
        else:
            os.chmod(path, 0o666)
    except OSError:
        pass


# ------------------------------
# Hashing: one reusable 1 MB
# buffer per thread, streamed reads
# ------------------------------

_tls = threading.local()


def file_hash(path: str, algo: str) -> str:
    """Hashes a file.

    Args:
        path (str): Path of the file being hashed
        algo (str): Hashing algorithm to use

    Returns:
        str: Hash of the target file
    """
    buf = getattr(_tls, "buf", None)
    if buf is None:
        buf = _tls.buf = bytearray(CHUNK)
    view = memoryview(buf)
    h = hashlib.new(algo)
    with open(
        W(path),
        "rb",
        buffering=0
    ) as f:
        while True:
            n = f.readinto(buf)
            if not n:
                break
            h.update(view[:n])
    return h.hexdigest().upper()


# ------------------------------
# Small helpers
# ------------------------------

def fmt_utc(ts: float) -> str:
    """Formats a provided timestamp into UTC time.

    Args:
        ts (float): Timestamp

    Returns:
        str: Timestamp formatted in UTC

    Raises:
        OverflowError, OSError, ValueError
    """
    try:
        return datetime.fromtimestamp(
            ts,
            timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
    except (OverflowError, OSError, ValueError):
        return ""


def fmt_local(ts: float) -> str:
    try:
        return datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S")
    except (OverflowError, OSError, ValueError):
        return "?"


def get_unique_path(path: str) -> str:
    """name (1).ext, name (2).ext, ... for the first unused name."""
    folder, fname = os.path.split(path)
    base, ext = os.path.splitext(fname)
    i = 1
    while True:
        cand = os.path.join(folder, f"{base} ({i}){ext}")
        if not os.path.lexists(W(cand)):
            return cand
        i += 1


def make_dir(path: str) -> None:
    try:
        os.mkdir(W(path))
    except FileExistsError:
        if not os.path.isdir(W(path)):
            raise


def try_stat(path: str):
    try:
        return os.stat(W(path))
    except (FileNotFoundError, NotADirectoryError):
        return None


class Progress:
    """Single-line status on stderr, only when attached to a terminal."""

    def __init__(self) -> None:
        self.enabled = sys.stderr.isatty()
        self.width = 0

    def update(self, text: str) -> None:
        if not self.enabled:
            return
        cols = shutil.get_terminal_size((100, 20)).columns - 1
        if len(text) > cols:
            text = text[:max(cols - 3, 0)] + "..."
        sys.stderr.write("\r" + text.ljust(self.width))
        sys.stderr.flush()
        self.width = len(text)

    def clear(self) -> None:
        if self.enabled and self.width:
            sys.stderr.write("\r" + " " * self.width + "\r")
            sys.stderr.flush()
            self.width = 0


class CsvLog:
    def __init__(self, path: str) -> None:
        # UTF-8 with BOM so Excel reads non-ASCII file names correctly
        self.f = open(path, "w", newline="", encoding="utf-8-sig")
        self.w = csv.writer(self.f)
        self.w.writerow(COLUMNS)

    def row(self, values) -> None:
        self.w.writerow(values)

    def flush(self) -> None:
        self.f.flush()

    def close(self) -> None:
        self.f.close()


# ------------------------------
# The copier
# ------------------------------

class Copier:
    def __init__(
            self,
            args,
            src: str,
            dst: str,
            log: CsvLog | None,
            progress: Progress
    ) -> None:
        self.src, self.dst = src, dst
        self.skip_identical = args.skip_identical
        self.copy_acl = args.copy_acl
        self.verify = args.verify_hash
        self.algo = args.hash_algorithm
        self.log = log
        self.progress = progress
        self.policy = "Prompt"          # Prompt | Source | Destination
        self.copied = self.skipped = self.renamed = self.failed = 0
        self.verified = self.mismatch = 0
        self.acl_ok = self.acl_partial = self.acl_failed = 0
        self.bytes = 0
        self.acl_dirs: list[str] = []   # directories only; far fewer than files
        self.last_tick = 0.0
        self.pool: ThreadPoolExecutor | None = None

    # ---- output ----
    def warn(self, msg: str) -> None:
        self.progress.clear()
        print("WARNING: " + msg, file=sys.stderr)

    def log_row(
            self,
            typ,
            status,
            src,
            dst,
            size="",
            modified="",
            hs="",
            hd="",
            hr="",
            acl="",
            note=""
    ) -> None:
        if self.log:
            algo = self.algo.upper() if self.verify else ""
            self.log.row(
                [
                    datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
                    typ,
                    status,
                    src,
                    dst,
                    size,
                    modified,
                    algo,
                    hs,
                    hd,
                    hr,
                    acl,
                    note.strip()
                    ]
                )

    def tick(self, current_dir: str) -> None:
        now = time.monotonic()
        if now - self.last_tick >= 0.5:
            self.last_tick = now
            if self.log:
                self.log.flush()
            self.progress.update(
                f"{self.copied:,} files, {self.bytes / 1048576:,.1f} MB  |  {current_dir}"
            )

    # ---- conflict prompt ----
    def ask_conflict(self, target: str, src_st, dst_st):
        """Returns (action, new_policy). action: Source | Destination | Both."""
        self.progress.clear()
        print(f"\nFile already exists: {target}")
        print(f"  Source:      {src_st.st_size:15,} bytes   modified {fmt_local(src_st.st_mtime)}")
        print(f"  Destination: {dst_st.st_size:15,} bytes   modified {fmt_local(dst_st.st_mtime)}")
        while True:
            try:
                ans = input("[S]ource  [D]estination (default)  [B]oth  Source for [A]ll  "
                            "Destination for all ([K]eep): ").strip().lower()
            except EOFError:
                return "Destination", None
            if ans in ("", "d"):
                return "Destination", None
            if ans == "s":
                return "Source", None
            if ans == "b":
                return "Both", None
            if ans == "a":
                return "Source", "Source"
            if ans == "k":
                return "Destination", "Destination"

    # ---- traversal ----
    def run(self) -> None:
        # Second hashing thread
        with ThreadPoolExecutor(max_workers=1) as pool:
            self.pool = pool
            stack = [self.src]
            while stack:
                d = stack.pop()
                rel = d[len(self.src):].lstrip(SEP)
                target_dir = os.path.join(self.dst, rel) if rel else self.dst
                try:
                    make_dir(target_dir)
                    if self.copy_acl:
                        # Applied at end so a restrictive ACL can't block copy
                        self.acl_dirs.append(d)
                    subdirs: list[str] = []
                    with os.scandir(W(d)) as it:
                        for entry in it:
                            self.handle_entry(entry, d, target_dir, subdirs)
                    stack.extend(subdirs)
                except Exception as e:
                    self.failed += 1
                    self.warn(f"Failed on directory: {d} => {e}")
                    self.log_row(
                        "Directory",
                        "Failed",
                        d,
                        target_dir,
                        note=str(e),
                    )
            if self.copy_acl:
                self.apply_dir_acls()

    def handle_entry(
            self,
            entry,
            d: str,
            target_dir: str,
            subdirs: list
    ) -> None:
        path = os.path.join(d, entry.name)
        target = os.path.join(target_dir, entry.name)
        try:
            st = entry.stat(follow_symlinks=False)
        except OSError as e:
            self.failed += 1
            self.warn(f"Failed: {path} => {e}")
            self.log_row(
                "File",
                "Failed",
                path,
                target,
                note=str(e),
            )
            return

        attrs = getattr(st, "st_file_attributes", None)
        if attrs is not None:
            is_dir = bool(attrs & FILE_ATTRIBUTE_DIRECTORY)
            reparse = bool(attrs & FILE_ATTRIBUTE_REPARSE_POINT)
        else:
            is_dir, reparse = stat.S_ISDIR(st.st_mode), stat.S_ISLNK(st.st_mode)

        if is_dir:
            # Junctions/symlinks: avoid loops and unintended copies
            if reparse:
                self.warn(f"Skipping reparse point: {path}")
                self.log_row("Directory", "SkippedReparsePoint", path, "")
            else:
                subdirs.append(path)
            return
        # File symlink: copy the content it points to,
        # so use the target's size/date
        if reparse:
            try:
                st = os.stat(W(path))
            except OSError:
                pass
        self.copy_one(path, target, st, d)

    # ---- one file ----
    def copy_one(self, path: str, target: str, st, current_dir: str) -> None:
        status = acl_result = hash_src = hash_dst = hash_result = note = ""
        try:
            do_copy, overwrite, status = True, False, "Copied"
            dst_st = try_stat(target)

            if dst_st is not None:
                if stat.S_ISDIR(dst_st.st_mode):
                    raise IsADirectoryError("a directory with the same name exists at the destination")
                if (self.skip_identical and st.st_size == dst_st.st_size
                        and st.st_mtime_ns == dst_st.st_mtime_ns):
                    self.skipped += 1
                    do_copy, status = False, "SkippedIdentical"
                else:
                    action = self.policy
                    if action == "Prompt":
                        action, new_policy = self.ask_conflict(target, st, dst_st)
                        if new_policy:
                            self.policy = new_policy

                    if action == "Destination":
                        self.skipped += 1
                        do_copy, status = False, "SkippedKeptDestination"
                    elif action == "Both":
                        target = get_unique_path(target)
                        self.renamed += 1
                        status = "CopiedRenamed"
                    elif action == "Source":
                        overwrite, status = True, "Overwritten"
                        clear_attributes(target)

            if do_copy:
                copy_file(path, target, overwrite)
                self.copied += 1
                self.bytes += st.st_size

                if self.copy_acl:
                    try:
                        if copy_security(path, target):
                            self.acl_ok += 1
                            acl_result = "Full"
                        else:
                            self.acl_partial += 1
                            acl_result = "DaclOnly"
                    except OSError as e:
                        self.acl_failed += 1
                        acl_result = "Failed"
                        note += f"ACL: {e} "
                        self.warn(f"ACL copy failed: {target} => {e}")

                if self.verify:
                    try:
                        # Copy hashed in the worker thread
                        fut = self.pool.submit(file_hash, target, self.algo)
                        err = None
                        try:
                            # Source hashed here, in parallel
                            hash_src = file_hash(path, self.algo)
                        except Exception as e:
                            err = e
                        try:
                            hash_dst = fut.result()
                        except Exception as e:
                            err = err or e
                        if err:
                            raise err
                        if hash_src == hash_dst:
                            self.verified += 1
                            hash_result = "Match"
                        else:
                            self.mismatch += 1
                            hash_result = "MISMATCH"
                            self.warn(
                                f"HASH MISMATCH: {path}\n  "
                                f"source {self.algo.upper()} : {hash_src}"
                                f"\n  copy   {self.algo.upper()} : {hash_dst}"
                            )
                    except Exception as e:
                        self.failed += 1
                        hash_result = "Error"
                        note += f"Hash: {e} "
                        self.warn(f"Hash failed: {path} => {e}")
        except Exception as e:
            self.failed += 1
            status = "Failed"
            note += str(e)
            self.warn(f"Failed: {path} => {e}")

        self.log_row(
            "File",
            status,
            path,
            target,
            st.st_size,
            fmt_utc(st.st_mtime),
            hash_src,
            hash_dst,
            hash_result,
            acl_result,
            note,
        )
        self.tick(current_dir)

    # ---- directory ACLs: last, deepest first ----
    def apply_dir_acls(self) -> None:
        total = len(self.acl_dirs)
        for n, sd in enumerate(reversed(self.acl_dirs), 1):
            rel = sd[len(self.src):].lstrip(SEP)
            td = os.path.join(self.dst, rel) if rel else self.dst
            acl_result = note = ""
            try:
                if copy_security(sd, td):
                    self.acl_ok += 1
                    acl_result = "Full"
                else:
                    self.acl_partial += 1
                    acl_result = "DaclOnly"
            except OSError as e:
                self.acl_failed += 1
                acl_result, note = "Failed", str(e)
                self.warn(f"ACL copy failed: {td} => {e}")
            self.log_row(
                "Directory",
                "DirectoryAcl",
                sd,
                td,
                acl=acl_result,
                note=note,
            )
            now = time.monotonic()
            if now - self.last_tick >= 0.5:
                self.last_tick = now
                self.progress.update(
                    f"Applying directory ACLs: {n:,} of {total:,}"
                )


# ------------------------------

def main() -> int:
    p = argparse.ArgumentParser(
        description="Recursively copy a directory tree with conflict prompts, "
        "optional NTFS ACL copy, hash verification and a CSV log."
    )
    p.add_argument(
        "source",
        help="directory to copy"
    )
    p.add_argument(
        "destination",
        help="destination directory (created if it does not exist)"
    )
    p.add_argument(
        "--skip-identical",
        action="store_true",
        help="silently skip conflicts where size and last-write time "
            "already match"
    )
    p.add_argument(
        "--copy-acl",
        action="store_true",
        help="copy NTFS security (DACL, owner, group); falls back to DACL "
            "only if owner/group cannot be set (run elevated for full fidelity)"
    )
    p.add_argument(
        "--verify-hash",
        action="store_true",
        help="hash the source and the copy after each copy and compare"
    )
    p.add_argument(
        "--hash-algorithm",
        type=str.lower,
        default="sha256",
        choices=("md5", "sha1", "sha256", "sha384", "sha512")
    )
    p.add_argument(
        "--log-path",
        help="CSV log file (default: CopyLog_<timestamp>.csv in the "
            "current directory)"
    )
    p.add_argument(
        "--no-log",
        action="store_true",
        help="do not write a CSV log"
    )
    args = p.parse_args()

    if args.copy_acl and not IS_WIN:
        p.error("--copy-acl is only supported on Windows")

    src = os.path.abspath(args.source)
    dst = os.path.abspath(args.destination)
    if src != os.path.splitdrive(src)[0] + SEP:
        src = src.rstrip("\\/")
    if dst != os.path.splitdrive(dst)[0] + SEP:
        dst = dst.rstrip("\\/")

    if not os.path.isdir(W(src)):
        p.error(f"source directory not found: {src}")
    nsrc, ndst = os.path.normcase(src), os.path.normcase(dst)
    if nsrc == ndst:
        p.error("source and destination are the same directory")
    if ndst.startswith(nsrc.rstrip(SEP) + SEP):
        p.error("destination cannot be inside the source directory")

    log_full = None
    if not args.no_log:
        log_path = args.log_path or f"CopyLog_{datetime.now():%Y%m%d_%H%M%S}.csv"
        log_full = os.path.abspath(log_path)
        if os.path.normcase(log_full).startswith(nsrc.rstrip(SEP) + SEP):
            p.error(
                f"the log file cannot be inside the source directory: "
                f"{log_full}"
            )
        os.makedirs(os.path.dirname(log_full), exist_ok=True)

    os.makedirs(W(dst), exist_ok=True)
    if args.copy_acl:
        enable_privileges(["SeRestorePrivilege", "SeTakeOwnershipPrivilege"])

    log = CsvLog(log_full) if log_full else None
    progress = Progress()
    copier = Copier(args, src, dst, log, progress)
    started = time.monotonic()
    interrupted = False
    try:
        copier.run()
    except KeyboardInterrupt:
        interrupted = True
    finally:
        if log:
            # Flushes and closes, even on Ctrl + C or a fatal error
            log.close()
        progress.clear()

    secs = int(time.monotonic() - started)
    h, rem = divmod(secs, 3600)
    m, s = divmod(rem, 60)
    c = copier
    if interrupted:
        print("Interrupted - totals below cover what was processed so far.")
    print(
        f"{c.copied:,} copied ({c.bytes / 1048576:,.1f} MB), "
        f"{c.skipped:,} skipped, {c.renamed:,} kept-both, "
        f"{c.failed:,} failed in {h:02}:{m:02}:{s:02}"
    )
    if args.verify_hash:
        print(
            f"{args.hash_algorithm.upper()} verification: "
            f"{c.verified:,} matched, {c.mismatch:,} MISMATCHED"
        )
    if args.copy_acl:
        print(
            f"ACLs: {c.acl_ok:,} full, {c.acl_partial:,} DACL-only "
            f"(owner/group not settable), {c.acl_failed:,} failed"
        )
    if log_full:
        print(f"Log: {log_full}")

    if interrupted:
        return 130
    return 1 if (c.failed or c.mismatch or c.acl_failed) else 0


if __name__ == "__main__":
    sys.exit(main())