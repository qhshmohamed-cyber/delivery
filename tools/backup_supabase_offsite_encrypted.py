#!/usr/bin/env python3
"""Optional encrypted OFF-SITE pg_dump from a trusted machine.
Needs: pg_dump, pg_restore, age installed. Requires private environment settings:
PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD, AGE_RECIPIENT, BACKUP_DIR.
No network credentials are stored in GitHub or in command-line arguments.
This does NOT run automatically and does NOT prove disaster recovery.
"""
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path


def main():
    keys = ("PGHOST", "PGPORT", "PGUSER", "PGDATABASE", "PGPASSWORD", "AGE_RECIPIENT", "BACKUP_DIR")
    missing = [key for key in keys if not os.environ.get(key)]
    if missing:
        raise SystemExit("Missing private environment variables: " + ", ".join(missing))
    for command in ("pg_dump", "pg_restore", "age"):
        if not shutil.which(command):
            raise SystemExit("Required local tool not installed: " + command)
    destination = Path(os.environ["BACKUP_DIR"]).expanduser().resolve()
    if not destination.is_dir() or destination == Path("/") or destination == Path.cwd():
        raise SystemExit("BACKUP_DIR must be an existing private offsite directory")
    recipient = os.environ["AGE_RECIPIENT"]
    if not recipient.startswith("age1") or len(recipient) < 30:
        raise SystemExit("Set AGE_RECIPIENT to a valid age public recipient key")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out = destination / ("yourstaff-supabase-" + stamp + ".dump.age")
    if out.exists():
        raise SystemExit("Refusing to overwrite an existing encrypted backup")
    old_umask = os.umask(0o077)
    try:
        with tempfile.TemporaryDirectory(prefix="ys-private-backup-") as temp:
            dump = Path(temp) / "database.dump"
            subprocess.run(["pg_dump", "--format=custom", "--no-owner", "--no-acl", "--file", str(dump)], check=True)
            listing = subprocess.run(["pg_restore", "--list", str(dump)], capture_output=True, check=True)
            if not listing.stdout or dump.stat().st_size < 1024:
                raise RuntimeError("Database archive preflight check failed")
            subprocess.run(["age", "-r", recipient, "-o", str(out), str(dump)], check=True)
        if not out.is_file() or out.stat().st_size < 1024:
            raise RuntimeError("Encrypted backup is unexpectedly empty")
        digest = hashlib.sha256(out.read_bytes()).hexdigest()
        checksum = out.with_suffix(out.suffix + ".sha256")
        checksum.write_text(digest + "  " + out.name + "\n", encoding="utf-8")
        os.chmod(out, 0o600)
        os.chmod(checksum, 0o600)
        print("Encrypted backup file:", out.name)
        print("SHA-256 manifest:", checksum.name)
        print("NEXT: Test age decryption and pg_restore on an isolated PostgreSQL instance.")
        print("This is NOT a confirmed restore and never uploads customer data to GitHub.")
    finally:
        os.umask(old_umask)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError:
        print("A backup command failed; check local configuration without posting credentials.", file=sys.stderr)
        sys.exit(1)
