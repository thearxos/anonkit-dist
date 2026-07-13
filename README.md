<div align="center">

# ArxOS AnonKit

**Real world OPSEC for ArxOS.** One window and one command to route the whole
system through Tor, spoof your MAC, hide Tor from your ISP, and prove that you are
actually covered.

`v0.0.1` · Tor transparent proxy · MAC spoofing · obfs4 + Snowflake bridges · VPN to Tor · leak test

</div>

---

## What it does

AnonKit turns full system anonymization into a small set of reliable, verifiable
actions. It is not a magic "make me invisible" button. It gives you strong,
honest defaults and a test that tells you the truth about your current state.

- **Transparent Tor proxy.** Routes every TCP connection through Tor at the
  firewall level, so applications that were never built for Tor still go through
  it. DNS is forced to Tor's resolver, IPv6 is disabled, and the local subnet is
  exempted so your LAN and SSH keep working.
- **Leak proof by construction.** A fail closed firewall (`OUTPUT` defaults to
  `DROP`), Tor stream isolation per destination and application, an IPv6 block at
  both the firewall and kernel level, and a DNS path that only ever reaches
  `127.0.0.1`.
- **MAC spoofing.** Randomize your hardware address, optionally masquerading as a
  chosen vendor, before you join an untrusted network.
- **System hardening on start, restored on stop.** Kernel sysctl hardening
  (TCP timestamps off, ICMP redirects off, reverse path filtering, full ASLR),
  swap disabled to avoid leaking secrets to disk, hostname randomized to defeat
  mDNS and DHCP fingerprinting, and timezone pinned to UTC. Everything is saved
  and restored cleanly when you stop.
- **Hide Tor from your ISP.** Two ways: a **Snowflake** or **obfs4** bridge, or a
  **VPN to Tor** chain. Both mean your ISP never sees that you use Tor.
- **A real safety test.** `anonkit --safe` checks Tor routing, the transparent
  proxy for real IP leaks, DNS and IPv6 leaks, the kill switch, and your MAC and
  ISP visibility, then gives you a plain SAFE or AT RISK verdict.

## Install

Ships with ArxOS. To install standalone on Arch:

```bash
sudo ./install.sh
```

This installs the `anonkit` command,
the `anonkit-gui` graphical front end, the `arxos-vpntor` VPN to Tor engine, and a
scoped polkit rule so the GUI can elevate cleanly.

## Command line

```bash
sudo anonkit -s                 # start the transparent Tor proxy
sudo anonkit -s -m -v apple     # start and spoof the MAC as an Apple vendor
sudo anonkit --snowflake        # start over a Snowflake bridge (hide Tor from the ISP)
sudo anonkit -s -b 'obfs4 ...'  # start over a specific obfs4 bridge
sudo anonkit -c                 # status: Tor state, exit IP, hardening
sudo anonkit -r                 # new identity (new Tor circuit)
sudo anonkit --safe             # full leak and VPN to Tor safety test
sudo anonkit -k                 # stop and restore clearnet
```

## Graphical front end

`anonkit-gui` (launched from the dock as **ArxOS AnonKit**) is a native GTK front end
in the ArxOS look. It exposes Start Tor, VPN to Tor, Snowflake, New Identity,
Safety Test, MAC spoof with a vendor picker, obfs4 Bridge, and Stop, with a live
status line showing Tor state, exit IP, and whether a VPN is up. Privileged
actions elevate through polkit, no terminal required.

## VPN to Tor

The correct order to hide Tor from your ISP is **VPN first, then Tor**: your ISP
only ever sees encrypted VPN traffic and never learns that you use Tor. AnonKit
does this for you with `arxos-vpntor`.

```bash
sudo arxos-vpntor                    # auto: fastest VPN Gate server, then Tor
sudo arxos-vpntor --country US       # prefer a country
sudo arxos-vpntor --own FILE.ovpn    # your own trusted VPN, then Tor
sudo arxos-vpntor --stop             # tear down (Tor first, then VPN)
```

**Sources.**

- **VPN Gate** (default, automatic). A public academic VPN relay pool with an API
  that returns ready to use OpenVPN configurations. No account, no rotating
  password. AnonKit picks the fastest server, connects, then starts Tor.
- **VPNBook** (fastest, one time manual). VPNBook runs dedicated servers that are
  faster than the volunteer pool, but they gate the configuration and password
  behind a CAPTCHA, so it cannot be pulled automatically. The GUI opens their page
  for you; download a config and copy the password, then hand the file to AnonKit.
- **Your own VPN** (recommended for serious work). Point `--own` at any `.ovpn`.

> A free public VPN means you trust the relay operator instead of your ISP. For
> real OPSEC use your own trusted VPN or a bridge.

## Bridges

For the specific goal of hiding Tor from your ISP without a VPN, a Tor bridge is
the purpose built tool.

- **Snowflake** (`anonkit --snowflake`). Free, no account. Tunnels Tor over
  WebRTC so it looks like a video call. AnonKit installs the client on demand.
- **obfs4** (`anonkit -s -b 'obfs4 ...'`). Paste a bridge line to disguise Tor
  from deep packet inspection.

## Security notes

- No tool makes you anonymous on its own. Browser level fingerprinting (WebRTC,
  canvas) is not visible to a system proxy, so use a hardened browser for
  anonymous web sessions.
- The transparent proxy exempts the local subnet so your LAN keeps working, but a
  fresh inbound connection is dropped while it is active. This is by design.

## Files

| Path | Purpose |
|---|---|
| `anonkit.py` | The engine (transparent proxy, hardening, MAC, bridges) |
| `anonkit-gui` | GTK graphical front end |
| `arxos-vpntor` | VPN to Tor chain (VPN Gate / VPNBook / your own) |
| `data/49-arxos-anonkit.rules` | polkit rule so the GUI can elevate without a tty |
| `install.sh` | Installer |

---

<div align="center">
Part of <b>ArxOS</b> · offensive and defensive security, finished.
</div>
