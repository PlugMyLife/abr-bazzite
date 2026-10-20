# abr-bazzite

**Bazzite, but with an out-of-box setup wizard — for refurbished machines.**

This repo builds `abr-bazzite-nvidia-legacy-kde`, a lightly modified [Bazzite](https://bazzite.gg) image used to prepare refurbished computers for resale. It gives a new owner a proper "first boot" experience — they create their own account with KDE's setup wizard — and then hands the machine off to **official Bazzite**, leaving nothing of this image behind.

This image is a temporary stop, not a destination. A machine spends one session on it, then rolls over to the official channel and receives normal Bazzite updates from then on.

---

## Which machines this is for

| Image | Base | Use for |
|---|---|---|
| `abr-bazzite-nvidia-legacy-kde` | `ghcr.io/ublue-os/bazzite-nvidia:stable` | KDE machines with **legacy Nvidia GPUs** (Pascal, Maxwell, Volta — e.g. GTX 900/1000 series) |

Do **not** switch AMD, Intel, or newer-Nvidia (Turing and up) machines onto this image — it carries the legacy Nvidia driver stack. Other GPU families would need their own sibling image.

---

## How it works

The image adds three things to stock Bazzite:

1. **`plasma-setup`** — KDE's first-boot setup wizard (installed, but switched off until armed).
2. **`abr-arm`** — a command that prepares the machine for its new owner.
3. **The rollover** — a service that switches the machine back to official Bazzite as soon as the owner finishes setup.

### The new owner's experience

1. Power on → **Welcome to Plasma Desktop → Begin Setup**. They create their own account.
2. They log in. In the background, the machine immediately starts switching to official Bazzite.
3. A few minutes later, a notification appears: **"Almost done! Restart your computer to finish setting up."** with a **Restart now** button.
4. After restarting, they're on official Bazzite.

---

## Preparing a machine

1. **Install official Bazzite** (the matching variant) from the ISO. Create a temporary technician account, e.g. `tech`.
2. **Secure Boot** (only if the kernel is rejected): disable Secure Boot in firmware, run `ujust enroll-secure-boot-key`, re-enable Secure Boot, and enter the password `universalblue` at the MOK enrollment screen.
3. **Switch to this image:**
   ```
   sudo bootc switch ghcr.io/plugmylife/abr-bazzite-nvidia-legacy-kde:latest
   ```
   Reboot, then confirm with `sudo bootc status`.
4. **Test the hardware** while logged in as `tech`.
5. **Arm it:**
   ```
   sudo abr-arm tech
   ```
   This turns on the setup wizard, logs out and deletes the `tech` account, and powers the machine off.
6. *(Optional)* Power on to confirm the wizard appears, then shut down from the wizard without completing it. The machine is ready to box.

---

## What's in the image

Everything lives in [`build_files/build.sh`](build_files/build.sh).

### `abr-arm` (`/usr/bin/abr-arm`)

```
sudo abr-arm <username-to-delete>
```

- Refuses to run if the named account doesn't exist.
- Enables `plasma-setup.service` and clears `/etc/plasma-setup-done`. If either step fails, it stops before touching the account.
- Hands the account deletion to a background system job (`abr-arm-finish`), so the account can be removed even though it's the one running the command.
- Powers off **only** if the account is confirmed gone. If the machine stays on, check `journalctl -u abr-arm-finish`.

### The rollover

- **`abr-rollover.path`** watches for `/etc/plasma-setup-done`, which the wizard creates when it finishes, and starts the rollover immediately.
- **`abr-rollover.service`** also checks at every boot as a fallback. It only runs if setup is done **and** the rollover hasn't happened yet (`/var/lib/abr/rollover-done`). It runs in the background and never holds up the desktop.
- **`/usr/libexec/abr-rollover`** does the work:
  1. Removes the Fedora theme that `plasma-setup` assigns to new accounts, so Bazzite's default theme and wallpaper apply.
  2. Waits for internet, then rebases to `ostree-image-signed:docker://ghcr.io/ublue-os/bazzite-nvidia:stable` — the same signed source official Bazzite uses.
  3. Marks the rollover done, waits for the owner to be logged in, and shows the restart notification.

  If anything fails (e.g. flaky Wi-Fi), the service retries every 5 minutes.

Because the rollover lands on official Bazzite, all of the above disappears from the system along with this image. Only the owner's account and files carry over.

### Watching it work

```
journalctl -u abr-rollover -f    # rollover progress
rpm-ostree status                # shows official Bazzite staged for next boot
sudo bootc status                # confirms which image is booted
```

---

## Building

Images are built automatically by GitHub Actions on every push to `main`, and are signed with [cosign](https://github.com/sigstore/cosign). The public key is [`cosign.pub`](cosign.pub); the private key is stored as the `SIGNING_SECRET` repository secret.

Image settings (name, registry owner) live in `image-template.env`. The base image is set by the `FROM` line in `Containerfile`.

---

## Credits

Built from the Universal Blue [image-template](https://github.com/ublue-os/image-template), on top of [Bazzite](https://github.com/ublue-os/bazzite). Setup wizard by [KDE's plasma-setup](https://invent.kde.org/plasma/plasma-setup).
