#!/usr/bin/env bash
# ArxOS AnonKit installer
set -e
D=$(cd "$(dirname "$0")" && pwd); S=""; [ "$(id -u)" -ne 0 ] && S=sudo

$S install -Dm755 "$D/anonkit.py"     /usr/local/bin/anonkit
$S install -m755  "$D/anonkit-gui"    /usr/local/bin/anonkit-gui
[ -f "$D/anonkit-tui" ]  && $S install -m755 "$D/anonkit-tui"  /usr/local/bin/anonkit-tui
[ -f "$D/arxos-vpntor" ] && $S install -m755 "$D/arxos-vpntor" /usr/local/bin/arxos-vpntor

# polkit rule so the GUI can elevate the helpers without a controlling tty
[ -f "$D/data/49-arxos-anonkit.rules" ] && \
  $S install -Dm644 "$D/data/49-arxos-anonkit.rules" /etc/polkit-1/rules.d/49-arxos-anonkit.rules
$S systemctl reload polkit 2>/dev/null || true

# dependencies - the transparent proxy needs a real netfilter backend (nftables + iptables-nft)
$S pacman -S --noconfirm --needed tor iptables-nft nftables macchanger python-gobject gtk3 openvpn polkit >/dev/null 2>&1 || true

# netfilter: load the backend now and make it persistent across boots
$S install -Dm644 /dev/stdin /etc/modules-load.d/anonkit-netfilter.conf <<'MODS'
# ArxOS AnonKit: netfilter backend for the transparent proxy
nf_tables
nft_chain_nat
MODS
for m in nf_tables nft_chain_nat ip_tables iptable_nat; do $S modprobe "$m" 2>/dev/null || true; done

# stale-kernel guard: if the RUNNING kernel has no module tree (kernel updated but the box was
# never rebooted, so /lib/modules/$(uname -r) was pruned), netfilter cannot load until reboot.
KREL=$(uname -r)
if [ ! -d "/lib/modules/$KREL/kernel/net/netfilter" ]; then
  echo
  echo "!! WARNING: the running kernel ($KREL) has no installed module tree."
  echo "   The kernel was updated but not rebooted, so netfilter (and AnonKit's transparent"
  echo "   proxy) cannot work until you REBOOT into the current kernel."
  NEW=$(ls -1 /lib/modules 2>/dev/null | tail -1)
  [ -n "$NEW" ] && echo "   Kernel ready on disk: $NEW  ->  reboot to activate netfilter."
fi

echo "ArxOS AnonKit installed"
