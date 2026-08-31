<div align="center">

# ArxOS AnonKit

![version](https://img.shields.io/badge/anond-0.0.1-e8702a?style=flat-square)
![built with](https://img.shields.io/badge/Rust-native-e8702a?style=flat-square&logo=rust&logoColor=white)
![source](https://img.shields.io/badge/source-private-1a1b20?style=flat-square)
![Stingray Labs](https://img.shields.io/badge/Stingray%20Labs-owner-1a1b20?style=flat-square)

**Whole-system anonymity, fail-closed.** `anond` is the ArxOS anonymity daemon: a native Rust engine that routes the machine through Tor behind a kill switch that is armed before Tor and lifted last, pins DNS to Tor, drops IPv6, and can add an i2p overlay. It refuses to report active until every layer is proven.

</div>

---

## What it is

`anond` is the engine behind the ArxOS Control Center's **Privacy** panel, and a standalone binary you can install anywhere. It is distributed as a **public binary with private source**, so nothing security sensitive leaks.

- **Fail-closed kill switch:** an nftables default-drop egress table is armed **before** Tor starts and removed **last**, so traffic can never escape around Tor. The LAN stays reachable, so SSH survives.
- **DNS pinned to Tor:** resolv.conf is repointed at Tor and made immutable; IPv6 is dropped.
- **Tor, supervised:** transparent proxy, DNSPort, SocksPort, and a cookie-authenticated control port.
- **i2p overlay:** opt-in `--i2p` brings up an i2pd overlay alongside Tor, additive and non-fatal.
- **Proven live:** `anond verify` runs leak probes and holds back the active state until they pass.

## Install

```bash
git clone https://github.com/thearxos/anonkit-dist
cd anonkit-dist
bash install.sh
```

The installer places the `anond` binary, a polkit rule for passwordless launch on the active wheel session, the AnonKit icon, and the runtime dependencies (Tor, i2pd, nftables).

## Usage

```bash
anond up            # bring anonymity up (fail-closed Tor + kill switch)
anond up --mac      # also randomize the MAC address
anond up --i2p      # add the i2p overlay
anond status        # current state
anond verify        # live leak test; refuses "active" until probes pass
anond new-identity  # new Tor circuit
anond down          # tear everything down, restore the network
```

On ArxOS this ships preinstalled and is driven from the **Control Center → Privacy** panel.

---

<div align="center">

### Owned and built by Stingray Labs

**AnonKit** is part of the **ArxOS** project. ArxOS and its tooling are developed by **Stingray Labs**.

<sub>スティングレイ</sub>

</div>
