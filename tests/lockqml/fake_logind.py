#!/usr/bin/env python3
"""A stand-in for logind on a private session bus, for scripts/lock-qml.sh (tests/lockqml/idle.qml).

Owns org.freedesktop.login1 on the bus DBUS_SESSION_BUS_ADDRESS names and, for each line read from a FIFO, emits the
signal Gutter's idle service listens for, so that `gdbus monitor` prints exactly what it prints for the real logind:

  prepare true|false    org.freedesktop.login1.Manager.PrepareForSleep at /org/freedesktop/login1
  lock <path>           org.freedesktop.login1.Session.Lock at the session object path <path>
  unlock <path>         org.freedesktop.login1.Session.Unlock at <path>

Usage: fake_logind.py FIFO LOG. Everything it does is appended to LOG, "ready" once the name is owned.
"""
import os
import signal
import sys

from gi.repository import Gio, GLib

try:
    from gi.repository import GLibUnix
    unix_signal_add = GLibUnix.signal_add
except ImportError:
    unix_signal_add = GLib.unix_signal_add

MANAGER = "org.freedesktop.login1.Manager"
SESSION = "org.freedesktop.login1.Session"

fifo_path, log_path = sys.argv[1], sys.argv[2]
log_file = open(log_path, "a", buffering=1)
loop = GLib.MainLoop()
connection = None
pending = b""


def log(message):
    log_file.write(message + "\n")


def emit(path, interface, name, parameters):
    connection.emit_signal(None, path, interface, name, parameters)
    connection.flush_sync(None)
    log(f"emitted {path} {interface}.{name} {parameters.print_(False) if parameters else '()'}")


def command(line):
    words = line.split()
    if words[:1] == ["prepare"] and len(words) == 2 and words[1] in ("true", "false"):
        emit("/org/freedesktop/login1", MANAGER, "PrepareForSleep", GLib.Variant("(b)", (words[1] == "true",)))
    elif words[:1] in (["lock"], ["unlock"]) and len(words) == 2:
        emit(words[1], SESSION, "Lock" if words[0] == "lock" else "Unlock", None)
    else:
        log(f"unknown command: {line!r}")


def readable(fd, _condition):
    global pending
    pending += os.read(fd, 4096)
    while b"\n" in pending:
        line, pending = pending.split(b"\n", 1)
        if line.strip():
            command(line.decode())
    return True


def bus_acquired(conn, _name):
    global connection
    connection = conn


def name_acquired(_conn, _name):
    log("ready")


def name_lost(_conn, name):
    log(f"lost {name}")
    loop.quit()


# O_RDWR: the FIFO never reports end of file when a writer closes.
fifo = os.open(fifo_path, os.O_RDWR | os.O_NONBLOCK)
GLib.io_add_watch(fifo, GLib.PRIORITY_DEFAULT, GLib.IO_IN, readable)
unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, loop.quit)
Gio.bus_own_name(Gio.BusType.SESSION, "org.freedesktop.login1", Gio.BusNameOwnerFlags.NONE, bus_acquired, name_acquired, name_lost)
loop.run()
