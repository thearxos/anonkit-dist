<div align="center">

# ArxOS AnonKit

**Real world OPSEC for ArxOS.** Route the whole system through Tor, spoof your
machine identity, isolate individual apps, and prove that you are actually covered.

`v0.0.1` · fail-closed Tor transparent proxy · DNS pinned to Tor · IPv6 blocked · i2p overlay · per-app isolation · runtime leak proof

</div>

---

## What it is

AnonKit is the ArxOS anonymity stack, written in Rust for speed, safety, and low
level control. It has two parts:

- **`anond`** is the anonymity daemon. It brings the whole host up as one anonymous
  session and refuses to report Active until every leak probe passes.
- **`arxonion`** isolates a single app inside a Tor-only network namespace, so you
  can run one program fully torified while the rest of the box stays as it is.

Both are driven from the Control Center's **Privacy** panel, or from the command
line. The source lives in the Control Center (arxctl); the compiled binaries ship
bundled with it and here, as a standalone install.

## What `anond` does

- **Fail-closed kill-switch.** An nftables ruleset with a default-drop egress
  policy is armed BEFORE Tor starts and removed LAST on stop, so an unhealthy
  layer can never open a clear path. On arm it flushes the connection-tracking
  table, so a connection that was open before the session cannot keep flowing in
  the clear. Only loopback, Tor's own uid, and the local subnet are ever let out.
- **Transparent Tor proxy.** Every TCP connection is redirected through Tor at the
  firewall level, so applications that were never built for Tor still go through
  it, with stream isolation per destination and per port. DNS is forced to Tor's
  resolver and the resolver file is pinned immutable. IPv6 is dropped at the
  firewall and the kernel.
- **Reversible machine-identity spoofing.** The hostname and `/etc/machine-id` are
  replaced with generic, session-only values by bind-mount (not a disk write), so
  they survive a mid-session re-read by NetworkManager or systemd and revert
  cleanly on stop or reboot. MAC randomization is opt-in with `--mac`. Swap is
  disabled so session secrets never page to disk, and anti-fingerprinting sysctls
  are applied and restored.
- **i2p overlay.** Opt-in with `--i2p`. i2pd is brought up alongside Tor as an
  additive layer: it egresses under its own uid, which the kill-switch exempts
  exactly like Tor, and it never takes the Tor session down if it is slow or fails.
- **Runtime leak proof.** Before declaring Active, `anond verify` checks the Tor
  exit, DNS pinning, IPv6 block, and kill-switch, and stays Locked (fully blocked)
  if any probe fails. Bootstrap progress is broadcast live so the UI never looks
  dead while Tor builds circuits.

## Command line

```bash
sudo anond up                   # go anonymous: kill-switch, Tor, DNS pin, harden, verify
sudo anond up --i2p             # also bring up the i2p overlay
sudo anond up --mac             # also randomize the MAC
sudo anond status               # state, Tor exit IP, kill-switch, DNS, i2p
sudo anond verify               # re-run the full leak proof
sudo anond new-identity         # new Tor circuit (NEWNYM)
sudo anond down                 # stop and restore the system cleanly (RAM caches flushed)
```

## Per-app isolation (`arxonion`)

```bash
sudo arxonion run firefox       # run one app inside a Tor-only network namespace
sudo arxonion shell             # an isolated shell; everything in it exits via Tor
sudo arxonion up                # persistent isolation (used by the Privacy toggle)
sudo arxonion down              # tear it down
sudo arxonion status            # namespace + routing state
```

## Install

Ships with ArxOS. To install standalone on Arch:

```bash
sudo ./install.sh
```

This installs whatever prebuilt binaries are present (`anond`, `arxonion`), a
scoped polkit rule so the Control Center can elevate `arxonion` cleanly, and the
netfilter and Tor dependencies the kill-switch needs.

## Security notes

- No tool makes you anonymous on its own. Browser-level fingerprinting (WebRTC,
  canvas) is not visible to a system proxy, so use a hardened browser for
  anonymous web sessions.
- The transparent proxy exempts the local subnet so your LAN and SSH keep working,
  but a fresh inbound connection is dropped while a session is active. This is by
  design.
- To hide from your ISP that you use Tor at all, put a VPN with its own kill-switch
  in front (VPN first, then Tor). Native VPN chaining in `anond` is a planned
  feature; until then, use your VPN provider's own client.

## Files

| Path | Purpose |
|---|---|
| `anond` | The anonymity daemon (prebuilt binary; source in arxctl) |
| `arxonion` | Per-app Tor-only isolation (prebuilt binary; source in arxctl) |
| `ANOND-DESIGN.md` | Design and threat model for the daemon |
| `data/49-arxos-anonkit.rules` | polkit rule so the Control Center can elevate `arxonion` without a tty |
| `install.sh` | Installer |

---

<div align="center">
Part of <b>ArxOS</b> · offensive and defensive security, finished.
</div>

---

<div align="center">
<sub><b>anonkit</b> is part of the <b>ArxOS</b> project, built by <b>Stingray Labs</b>.</sub>
</div>
