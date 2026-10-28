"""Atomic file writes shared by Gutter's generators. Standard library only."""
import os
import tempfile
from pathlib import Path


def write_atomic(path, text, prefix, mode=0o644):
    """Writes text to path via a temp file in the same directory, flushed to disk, and os.replace, then flushes the
    directory so the rename survives a crash; the temp file is removed on failure. The file ends up with `mode`. A
    symlink at path is kept: the file it points to is replaced."""
    path = Path(os.path.realpath(path))
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=prefix, suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    try:                    # best effort: the new file is in place, and not every filesystem can sync a directory
        dir_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    except OSError:
        pass
