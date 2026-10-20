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
dnf5 install -y plasma-setup

### ABR: roll over to official Bazzite after the owner finishes setup

cat > /usr/libexec/abr-rollover <<'EOF'
#!/usr/bin/bash
set -euo pipefail
# Wait until the internet works
until curl -s -o /dev/null --max-time 10 https://ghcr.io; do sleep 30; done
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/ublue-os/bazzite-nvidia:stable
mkdir -p /var/lib/abr
touch /var/lib/abr/rollover-done
EOF
chmod +x /usr/libexec/abr-rollover

cat > /usr/lib/systemd/system/abr-rollover.service <<'EOF'
[Unit]
Description=ABR: switch to official Bazzite after owner setup
ConditionPathExists=/etc/plasma-setup-done
ConditionPathExists=!/var/lib/abr/rollover-done
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/libexec/abr-rollover
Restart=on-failure
RestartSec=5min

[Install]
WantedBy=multi-user.target
EOF

systemctl enable abr-rollover.service
