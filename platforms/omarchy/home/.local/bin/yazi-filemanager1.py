#!/usr/bin/env -S uv run --offline --no-project --python /usr/bin/python3
"""Answer org.freedesktop.FileManager1 ("Show in folder") by opening Yazi.

Browsers and Electron apps call this D-Bus interface to reveal a file. D-Bus activates this script via ~/.local/share/dbus-1/services/org.freedesktop.FileManager1.service, which shadows Nautilus's system-wide service file. It stays resident afterwards, so launched terminals never share a cgroup that systemd tears down when the service exits.
"""

# %% Imports and interface
import subprocess
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # ty: ignore[unresolved-import]

BUS_NAME = "org.freedesktop.FileManager1"
OBJECT_PATH = "/org/freedesktop/FileManager1"
INTERFACE_XML = """
<node>
  <interface name="org.freedesktop.FileManager1">
    <method name="ShowFolders">
      <arg type="as" name="URIs" direction="in"/>
      <arg type="s" name="StartupId" direction="in"/>
    </method>
    <method name="ShowItems">
      <arg type="as" name="URIs" direction="in"/>
      <arg type="s" name="StartupId" direction="in"/>
    </method>
    <method name="ShowItemProperties">
      <arg type="as" name="URIs" direction="in"/>
      <arg type="s" name="StartupId" direction="in"/>
    </method>
  </interface>
</node>
"""


# %% Method handler
def local_paths(uris: list[str]) -> list[str]:
    """Convert file:// URIs to local paths, dropping anything non-local.

    Args:
        uris: URIs received from the caller.

    Returns:
        Local filesystem paths, in the order received.
    """
    paths = (Gio.File.new_for_uri(uri).get_path() for uri in uris)
    return [path for path in paths if path]


def on_method_call(
    _connection: Gio.DBusConnection,
    _sender: str,
    _object_path: str,
    _interface: str,
    _method: str,
    parameters: GLib.Variant,
    invocation: Gio.DBusMethodInvocation,
) -> None:
    """Open Yazi on the requested paths and reply immediately.

    Yazi opens a directory, or reveals a file in its parent; several paths become tabs. Properties have no Yazi equivalent, so ShowItemProperties also reveals.
    """
    uris, _startup_id = parameters.unpack()
    paths = local_paths(uris)
    if paths:
        subprocess.Popen(["omarchy-launch-tui", "yazi", *paths])
    invocation.return_value(None)


# %% Service
def main() -> int:
    loop = GLib.MainLoop()
    interface = Gio.DBusNodeInfo.new_for_xml(INTERFACE_XML).interfaces[0]

    def on_bus_acquired(connection: Gio.DBusConnection, _name: str) -> None:
        connection.register_object(
            OBJECT_PATH, interface, on_method_call, None, None
        )

    def on_name_lost(_connection: Gio.DBusConnection, name: str) -> None:
        print(
            f"Could not own {name}; another file manager has it.",
            file=sys.stderr,
        )
        loop.quit()

    Gio.bus_own_name(
        Gio.BusType.SESSION,
        BUS_NAME,
        Gio.BusNameOwnerFlags.NONE,
        on_bus_acquired,
        None,
        on_name_lost,
    )
    loop.run()
    return 1


if __name__ == "__main__":
    sys.exit(main())
