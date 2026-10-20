#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos
dnf5 install -y tmux

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

#### Example for enabling a System Unit File

systemctl enable podman.socket

### ABR: install KDE's first-boot setup wizard
dnf5 install -y --setopt=install_weak_deps=False plasma-setup libnotify
systemctl disable plasma-setup.service

### ABR: make the setup wizard use Bazzite's theme instead of Fedora's
KDE_PROFILE=/usr/share/kde-settings/kde-profile/default/xdg/kdeglobals
if [ -f "$KDE_PROFILE" ]; then
  sed -i 's/^LookAndFeelPackage=.*/LookAndFeelPackage=com.valve.vapor.desktop/' "$KDE_PROFILE"
fi

cat > /usr/bin/abr-arm <<'EOF'
#!/usr/bin/bash
set -euo pipefail
TARGET="${1:?usage: sudo abr-arm <username-to-delete>}"
id "$TARGET" >/dev/null
systemctl enable plasma-setup.service
rm -f /etc/plasma-setup-done
rm -f /var/lib/abr/rollover-done
echo "Armed. Logging out and deleting $TARGET, then powering off..."
systemd-run --unit=abr-arm-finish bash -c "loginctl terminate-user $TARGET; sleep 3; userdel -rf $TARGET; id $TARGET || poweroff"
EOF
chmod +x /usr/bin/abr-arm

### ABR: roll over to official Bazzite as soon as the owner finishes setup

cat > /usr/libexec/abr-rollover <<'EOF'
#!/usr/bin/bash
set -euo pipefail

# 1. Remove the Fedora theme plasma-setup assigns, so Bazzite's default applies
for home in /var/home/*/; do
  f="${home}.config/kdeglobals"
  if [ -f "$f" ]; then
    sed -i '/^LookAndFeelPackage=org\.fedoraproject\./d' "$f"
  fi
  d="${home}.config/kdedefaults"
  if grep -qs fedoraproject "$d/package"; then
    rm -rf "$d"
  fi
done

# 2. Wait for internet, then stage official Bazzite
until curl -s -o /dev/null --max-time 10 https://ghcr.io; do sleep 30; done
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/ublue-os/bazzite-nvidia:stable
mkdir -p /var/lib/abr
touch /var/lib/abr/rollover-done

# 3. Wait for the owner to be logged in, then ask them to restart
until ls -d /run/user/1[0-9][0-9][0-9] >/dev/null 2>&1; do sleep 10; done
uid_dir=$(ls -d /run/user/1[0-9][0-9][0-9] | head -n1)
user=$(id -nu "${uid_dir##*/}")
choice=$(runuser -u "$user" -- env DBUS_SESSION_BUS_ADDRESS="unix:path=$uid_dir/bus" \
  notify-send --wait -u critical -a "Computer setup" -A restart="Restart now" \
  "Almost done!" "Restart your computer to finish setting up." || true)
if [ "$choice" = "restart" ]; then systemctl reboot; fi
EOF
chmod +x /usr/libexec/abr-rollover

cat > /usr/lib/systemd/system/abr-rollover.service <<'EOF'
[Unit]
Description=ABR: switch to official Bazzite after owner setup
ConditionPathExists=/etc/plasma-setup-done
ConditionPathExists=!/var/lib/abr/rollover-done

[Service]
Type=simple
ExecStart=/usr/libexec/abr-rollover
Restart=on-failure
RestartSec=5min

[Install]
WantedBy=multi-user.target
EOF

cat > /usr/lib/systemd/system/abr-rollover.path <<'EOF'
[Unit]
Description=ABR: start the rollover as soon as owner setup finishes

[Path]
PathChanged=/etc/plasma-setup-done

[Install]
WantedBy=multi-user.target
EOF

systemctl enable abr-rollover.service abr-rollover.path
