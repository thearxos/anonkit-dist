#!/usr/bin/env bash
# ArxOS AnonKit installer.
#
# AnonKit is the Rust `anond` anonymity daemon (fail-closed Tor transparent proxy, DNS pinned to
# Tor, IPv6 blocked, reversible host hardening, opt-in i2p overlay) plus `arxonion` (per-app
# Tor-only network-namespace isolation). Both are built and owned by the Control Center (arxctl):
# the source lives in arxctl, and the compiled binaries ship bundled with arxctl AND here, in the
# public anonkit-dist mirror, as a standalone install. This installer sets up whatever prebuilt
# binaries are present next to it, the pkexec polkit rule, and the netfilter/tor dependencies the
# kill-switch needs. The legacy Python AnonKit (anonkit.py / anonkit-gui / anonkit-tui) and the
# arxos-vpntor VPN->Tor script were retired here (superseded by the Rust stack); this script no
# longer installs them.
set -e
D=$(cd "$(dirname "$0")" && pwd); S=""; [ "$(id -u)" -ne 0 ] && S=sudo

# prebuilt daemon/helper binaries. A bundled binary next to this script wins; otherwise fetch the
# daemon from the public release (the mirror ships source only, so the OTA checkout has no binary
# in-tree). arxonion, when not bundled, is provided by the Control Center (arxctl) install.
VER=0.0.1
DIST="${ANONKIT_GITHUB_REPO:-thearxos/anonkit-dist}"
BASE="https://github.com/${DIST}/releases/download/v${VER}"
dl() { if command -v curl >/dev/null 2>&1; then curl -fsSL "$1" -o "$2"; else wget -qO "$2" "$1"; fi; }
if [ -f "$D/anond" ]; then
    $S install -Dm755 "$D/anond" /usr/local/bin/anond
else
    TMP=$(mktemp -d)
    if dl "$BASE/anond" "$TMP/anond" && [ -s "$TMP/anond" ]; then
        chmod +x "$TMP/anond"; $S install -Dm755 "$TMP/anond" /usr/local/bin/anond
    fi
    rm -rf "$TMP"
fi
[ -f "$D/arxonion" ] && $S install -Dm755 "$D/arxonion" /usr/local/bin/arxonion

# polkit rule so the Control Center can elevate `arxonion` (per-app isolation) via pkexec without
# a controlling tty.
[ -f "$D/data/49-arxos-anonkit.rules" ] && \
  $S install -Dm644 "$D/data/49-arxos-anonkit.rules" /etc/polkit-1/rules.d/49-arxos-anonkit.rules
$S systemctl reload polkit 2>/dev/null || true

# fail closed across a crash, power loss or reboot: anond-boot re-arms the kill-switch before the
# network comes up, anond-resume brings Tor back once online. Both are skipped at boot unless a
# session was live. These unit files are byte-identical copies of arxctl's data/systemd ones
# (both bundles install anond); keep them in sync.
for u in anond-boot.service anond-resume.service; do
  [ -f "$D/data/systemd/$u" ] && $S install -Dm644 "$D/data/systemd/$u" "/usr/lib/systemd/system/$u"
done
$S systemctl daemon-reload 2>/dev/null || true
$S systemctl enable anond-boot.service anond-resume.service 2>/dev/null || true

# dependencies: the transparent-proxy kill-switch needs a real netfilter backend (nftables +
# iptables-nft) and conntrack-tools (it flushes conntrack on arm so no pre-existing clear flow
# survives); tor is the anonymity transport; i2pd backs the optional i2p overlay.
$S pacman -S --noconfirm --needed tor nftables iptables-nft conntrack-tools i2pd polkit >/dev/null 2>&1 || true

# netfilter: load the backend now and make it persistent across boots.
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
