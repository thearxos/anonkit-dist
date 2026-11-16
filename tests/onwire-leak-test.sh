#!/usr/bin/env bash
# anond on-wire leak test: the proof anond's own `verify` cannot give itself.
#
# anond refuses to report Active until its own probes pass, but a daemon grading its own homework
# can still be wrong about the wire. This harness checks the same claims INDEPENDENTLY, from outside
# anond: real traffic, real DNS, real IPv6, and the kill-switch actually dropping a bypass attempt.
# It then tears the session down and proves the machine is a normal, working host again.
#
# DESTRUCTIVE: it rewrites nftables, /etc/resolv.conf, MAC addresses and routing. Run it ONLY in a
# throwaway VM. It refuses to run on a machine that is not a VM unless you pass --force-not-a-vm,
# and it refuses entirely without --yes.
#
# Usage:  sudo ./onwire-leak-test.sh --yes            # in a throwaway VM
#         sudo ANOND=/usr/local/bin/anond ./onwire-leak-test.sh --yes
set -u
ANOND="${ANOND:-anond}"
PASS=0; FAIL=0; YES=0; FORCE=0
for a in "$@"; do case "$a" in --yes) YES=1;; --force-not-a-vm) FORCE=1;; esac; done

ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; FAIL=$((FAIL+1)); }
info() { printf '  ..    %s\n' "$*"; }
hr()   { printf '\n== %s ==\n' "$*"; }

[ "$(id -u)" -eq 0 ] || { echo "run as root (it changes the firewall)"; exit 2; }
[ "$YES" = 1 ] || { echo "refusing without --yes (this rewrites the firewall, DNS and routing)"; exit 2; }
virt="$(systemd-detect-virt 2>/dev/null || echo unknown)"
if [ "$virt" = none ] && [ "$FORCE" != 1 ]; then
  echo "systemd-detect-virt says this is NOT a VM ('$virt'). Refusing: run it in a throwaway VM."
  echo "(override with --force-not-a-vm only if you truly mean to test the host.)"
  exit 2
fi
command -v "$ANOND" >/dev/null 2>&1 || { echo "anond not found (set ANOND=/path/to/anond)"; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "curl is required"; exit 2; }

# A clearnet IP + resolver we will try to reach DIRECTLY to prove the kill-switch blocks a bypass.
# 1.1.1.1 answers both TCP/443 and UDP/53; reaching either outside Tor is a leak.
BYPASS_IP=1.1.1.1

hr "baseline (before anond)"
REAL_IP="$(curl -s --max-time 15 https://check.torproject.org/api/ip 2>/dev/null | sed -n 's/.*"IP":"\([^"]*\)".*/\1/p')"
info "clearnet IP before anond: ${REAL_IP:-<none/offline>}"

hr "anond up"
if "$ANOND" up 2>&1 | sed 's/^/    /'; then ok "anond up returned success"; else bad "anond up failed"; fi

hr "1. Tor egress (independent of anond's verdict)"
API="$(curl -s --max-time 45 https://check.torproject.org/api/ip 2>/dev/null)"
IS_TOR="$(printf '%s' "$API" | sed -n 's/.*"IsTor":\(true\|false\).*/\1/p')"
EXIT_IP="$(printf '%s' "$API" | sed -n 's/.*"IP":"\([^"]*\)".*/\1/p')"
if [ "$IS_TOR" = true ]; then ok "check.torproject.org says IsTor=true (exit ${EXIT_IP:-?})"; else bad "IsTor=${IS_TOR:-<no answer>}: egress is NOT exiting via Tor"; fi
if [ -n "$REAL_IP" ] && [ -n "$EXIT_IP" ] && [ "$REAL_IP" = "$EXIT_IP" ]; then bad "exit IP equals the pre-session clearnet IP ($EXIT_IP): no Tor hop"; else [ -n "$EXIT_IP" ] && ok "exit IP changed from the baseline"; fi

hr "2. DNS does not leak"
if grep -qE '^nameserver\s+127\.' /etc/resolv.conf 2>/dev/null; then ok "/etc/resolv.conf is pinned to loopback"; else bad "/etc/resolv.conf is NOT pinned to loopback: $(grep -m1 nameserver /etc/resolv.conf 2>/dev/null)"; fi
# a direct UDP/53 query to a public resolver must be dropped by the kill-switch (nothing but Tor egresses)
if command -v dig >/dev/null 2>&1; then
  if timeout 8 dig +time=3 +tries=1 @"$BYPASS_IP" example.com >/dev/null 2>&1; then bad "a direct DNS query to $BYPASS_IP SUCCEEDED: DNS can leave outside Tor"; else ok "a direct DNS query to $BYPASS_IP was blocked"; fi
else info "dig not present; skipped the direct-UDP/53 probe"
fi

hr "3. IPv6 has no clear path"
if nft list table ip6 anond6 >/dev/null 2>&1; then ok "ip6 drop table 'anond6' is installed"; else bad "ip6 drop table 'anond6' is missing"; fi
if curl -6 -s --max-time 8 https://[2606:4700:4700::1111]/ >/dev/null 2>&1; then bad "an IPv6 request SUCCEEDED: IPv6 is not blocked"; else ok "IPv6 egress is blocked"; fi

hr "4. kill-switch enforcement (bypass attempt + tor-down)"
if nft list table ip anond >/dev/null 2>&1; then ok "ip kill-switch table 'anond' is installed"; else bad "ip kill-switch table 'anond' is missing"; fi
# With Tor stopped, NOTHING should reach clearnet. Stop tor and confirm the switch holds closed.
if systemctl stop tor 2>/dev/null; then
  sleep 2
  if curl -s --max-time 10 "https://$BYPASS_IP/" >/dev/null 2>&1; then bad "with Tor stopped, clearnet was still reachable: kill-switch is FAIL-OPEN"; else ok "with Tor stopped, clearnet is unreachable: fail-closed holds"; fi
  # and anond must now report NOT active (it reconciles live)
  st="$("$ANOND" status 2>/dev/null)"; printf '%s' "$st" | grep -qiE 'active' && bad "anond still reports active with Tor down: $st" || ok "anond no longer reports active with Tor down"
  systemctl start tor 2>/dev/null || true
else info "could not stop tor (not a unit?); skipped the tor-down bypass test"
fi

hr "anond down + restore"
if "$ANOND" down 2>&1 | sed 's/^/    /'; then ok "anond down returned success"; else bad "anond down failed"; fi
sleep 2
if nft list table ip anond >/dev/null 2>&1 || nft list table ip6 anond6 >/dev/null 2>&1; then bad "anond tables remain after down: cleanup incomplete"; else ok "firewall tables removed after down"; fi
if getent hosts example.com >/dev/null 2>&1; then ok "name resolution works again after down"; else bad "name resolution is broken after down: restore failed"; fi
if curl -s --max-time 15 https://check.torproject.org/api/ip >/dev/null 2>&1; then ok "clearnet reachable again after down"; else bad "clearnet unreachable after down: the machine was left offline"; fi

hr "result"
printf '  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || { echo "  LEAK TEST FAILED: anond's advertised protection is not fully on the wire."; exit 1; }
echo "  on-wire leak test clean."
exit 0
