# set-gdm-login-background

A shell script to set the GDM login-screen background on RHEL 10 / GNOME systems by patching `gnome-shell-theme.gresource` in place.

## Usage

```bash
# Apply a background image (run as root)
sudo set-gdm-login-background.sh /path/to/image.png

# Override the background fill colour (shown behind the image while it loads)
sudo set-gdm-login-background.sh /path/to/image.png '#1a1a2e'

# Check whether the current image is already applied (exit 0 = unchanged, exit 1 = needs apply)
sudo set-gdm-login-background.sh --check /path/to/image.png
```

**Defaults:** `IMAGE=/usr/share/backgrounds/gdm-background.png`, `BG_COLOR=#000000`

## Requirements

- `gresource` — shipped with `glib2` (usually already present)
- `glib-compile-resources` — from `glib2-devel`

```bash
sudo dnf install -y glib2-devel
```

## How it works

GDM's visual theme is compiled into a single GResource bundle (`/usr/share/gnome-shell/gnome-shell-theme.gresource`). The script:

1. Saves a pristine copy of the bundle the first time it runs (`.orig` alongside the original).
2. Extracts all resources from the pristine copy into a temp directory.
3. Appends a `#lockDialogGroup` CSS override — with an embedded SHA256 marker — to every `gnome-shell*.css` stylesheet inside the bundle.
4. Recompiles the bundle and installs it in place.

On subsequent runs the embedded SHA is compared against the current image's SHA, so the script is idempotent and safe to run from a configuration-management tool.

## Idempotency / configuration management

The `--check` flag makes the script suitable as a Puppet/Ansible/Salt "is this applied?" probe:

- Exit 0 + stdout `UNCHANGED` → already applied, nothing to do.
- Exit 1 + stdout `NEEDS-APPLY` → run without `--check` to apply.

## References

- <https://www.linuxuprising.com/2021/05/how-to-change-gdm3-login-screen-greeter.html>
- <https://bbs.archlinux.org/viewtopic.php?id=197036>
- <https://binblog.de/2024/05/03/gnome-gdm-customization/>
