#!/usr/bin/env bash
#
# Set the RHEL/GNOME GDM login-screen background to an image.
# Usage:
#   set-gdm-login-background.sh [IMAGE] [BG_COLOR]      # apply
#   set-gdm-login-background.sh --check [IMAGE]         # exit 0 if already applied
#
# Defaults: IMAGE=/usr/share/backgrounds/gdm-background.png  BG_COLOR=#000000

# Resources Used:
# https://www.linuxuprising.com/2021/05/how-to-change-gdm3-login-screen-greeter.html
# https://bbs.archlinux.org/viewtopic.php?id=197036
# https://binblog.de/2024/05/03/gnome-gdm-customization/

set -euo pipefail

#GRES is the compiled Shell theme bundle, which we patch by extracting, modifying the css, and recompiling.
GRES=/usr/share/gnome-shell/gnome-shell-theme.gresource
DEFAULT_IMG=/usr/share/backgrounds/gdm-background.png
DEFAULT_COLOR='#000000'

die() { echo "ERROR: $*" >&2; exit 2; }

check_mode=0
if [[ "${1:-}" == "--check" ]]; then
  check_mode=1
  shift
fi

# Default image and background colour can be overridden by command-line args.
IMG=${1:-$DEFAULT_IMG}
BG_COLOR=${2:-$DEFAULT_COLOR}

# glib2 provides the runtime `gresource` (always present); the compiler lives in
# we have to make sure that's on the endpoint.
command -v gresource >/dev/null              || die "gresource not found (install glib2)"
command -v glib-compile-resources >/dev/null || die "glib-compile-resources not found (install glib2-devel)"
[[ -f "$GRES" ]] || die "gresource $GRES not found"
[[ -f "$IMG"  ]] || die "image $IMG not found"

IMG_SHA=$(sha256sum "$IMG" | awk '{print $1}')

# Echo the sha recorded inside the installed gresource (marker we embed:
# /* gdm-bg sha=<IMG_SHA> */), or nothing if our marker is absent.
installed_sha() {
  local res css
  while read -r res; do
    case "${res##*/}" in
      gnome-shell*.css)
        css=$(gresource extract "$GRES" "$res" 2>/dev/null || true)
        if [[ "$css" == *"gdm-bg sha="* ]]; then
          sed -n 's:.*gdm-bg sha=\([0-9a-f]*\).*:\1:p' <<<"$css" | head -n1
          return 0
        fi
        ;;
    esac
  done < <(gresource list "$GRES" 2>/dev/null)
}

current_sha=$(installed_sha)
# --check: success (0) means "already applied, nothing to do".
if [[ "$check_mode" == 1 ]]; then
  [[ "$current_sha" == "$IMG_SHA" ]] && { echo "UNCHANGED"; exit 0; }
  echo "NEEDS-APPLY"; exit 1
fi

# apply
if [[ "$current_sha" == "$IMG_SHA" ]]; then
  echo "UNCHANGED"
  exit 0
fi

# Establish the unpatched base. If the installed gresource carries no
# marker it IS pristine (fresh install, or just replaced by a package update) ->
# refresh our saved copy so we patch the current upstream theme, not a stale one.
# Empty current sha means stock is insalled, inverse non-empty means we patched it, so only refresh if empty.
ORIG="${GRES}.orig"
if [[ -z "$current_sha" ]]; then
  cp -a "$GRES" "$ORIG"
fi
[[ -f "$ORIG" ]] || die "no pristine base at $ORIG (was the script ever run on an unpatched system?)"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
root="$work/root"
mkdir -p "$root"

# Extract every resource, preserving its full path under prefix "/".
while read -r res; do
  rel=${res#/}
  dest="$root/$rel"
  mkdir -p "$(dirname "$dest")"
  gresource extract "$ORIG" "$res" > "$dest"
done < <(gresource list "$ORIG")

# Patch ALL shell stylesheets (main + dark/light/high-contrast variants), since
# we don't control which variant the greeter resolves to at login.
mapfile -t css_files < <(find "$root" -type f -name 'gnome-shell*.css')
[[ ${#css_files[@]} -gt 0 ]] || die "no gnome-shell*.css inside gresource"

# Append our override (last rule of equal specificity wins) to each stylesheet.
for css in "${css_files[@]}"; do
  cat >> "$css" <<EOF

/* gdm-bg sha=${IMG_SHA} */
#lockDialogGroup {
  background: ${BG_COLOR} url(file://${IMG});
  background-size: cover;
  background-repeat: no-repeat;
  background-position: center;
}
EOF
done

# Rebuild the manifest and compile.
manifest="$work/gdm.gresource.xml"
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<gresources><gresource prefix="/">'
  ( cd "$root" && find . -type f | sed 's:^\./::' | sort \
      | while read -r f; do echo "  <file>$f</file>"; done )
  echo '</gresource></gresources>'
} > "$manifest"

glib-compile-resources "$manifest" --target="$work/out.gresource" --sourcedir="$root"

install -m644 "$work/out.gresource" "$GRES"
echo "CHANGED"
