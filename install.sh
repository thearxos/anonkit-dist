#!/usr/bin/env bash
# ArxOS AnonKit (anond) standalone installer.
# Installs the anond anonymity daemon binary, its polkit rule, the AnonKit icon,
# and the runtime dependencies for the fail-closed Tor + i2p kill-switch.
set -e
D=$(cd "$(dirname "$0")" && pwd); S=""; [ "$(id -u)" -ne 0 ] && S=sudo

# the anond daemon (public binary; source is private under Stingray Labs)
$S install -Dm755 "$D/anond" /usr/local/bin/anond

# polkit: let the active wheel session drive anond via pkexec (a GUI/Control Center
# has no controlling tty, so the text-agent fallback would break)
[ -f "$D/data/49-arxos-anonkit.rules" ] && \
  $S install -Dm644 "$D/data/49-arxos-anonkit.rules" /etc/polkit-1/rules.d/49-arxos-anonkit.rules
$S systemctl reload polkit 2>/dev/null || true

# the AnonKit icon (used by the ArxOS Control Center Privacy panel and the dock)
[ -f "$D/assets/anonkit.png" ] && \
  $S install -Dm644 "$D/assets/anonkit.png" /usr/share/icons/ArxOS/arxos-anonkit.png

# runtime deps: Tor + i2pd + a real netfilter backend for the fail-closed kill-switch
$S pacman -S --noconfirm --needed tor i2pd nftables iptables-nft >/dev/null 2>&1 || true

echo "anond installed."
echo "  anond up          bring anonymity up (fail-closed Tor + kill-switch)"
echo "  anond up --mac    also randomize the MAC address"
echo "  anond up --i2p    add the i2p overlay"
echo "  anond status | verify | new-identity | down"
echo "On ArxOS this is driven from the Control Center -> Privacy panel."
