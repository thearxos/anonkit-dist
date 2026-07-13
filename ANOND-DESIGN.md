# anond — the ARXOS anonymity daemon (Rust rewrite of anonkit)

Goal: **complete, trustworthy anonymity** — Tor + i2p + leak-proof DNS brought up as one
fail-closed system, memory-safe, self-verifying. Not a proxy wrapper. The current Python
`anonkit.py` (Tor transparent proxy + nft kill-switch + `--safe` test) is the proven behaviour
model; `anond` reimplements it in Rust and adds the i2p and DNS layers as first-class citizens.

## Why Rust (not C)
A leak is a memory bug's worst-case here. Rust removes the entire class of UAF/overflow/data-race
bugs that would be silent deanonymization in C, while giving us tokio for process supervision,
`rustables` for typed nftables, and static musl binaries. C buys nothing and costs safety.

## Non-negotiable invariants (the "mil-grade" part)
1. **Fail-closed by construction.** The kill-switch is installed BEFORE any service starts and is
   the last thing removed. If Tor or i2pd dies, or bootstrap stalls, traffic is BLOCKED, never
   leaked. There is no code path from "a layer is unhealthy" to "packets egress in the clear".
2. **Default-drop egress.** OUTPUT policy drop; only loopback + the tor uid + the i2pd uid + the
   transparent redirects are permitted. Everything else (incl. IPv6 entirely) is dropped.
3. **DNS cannot leak.** All clearnet name resolution goes to Tor's DNSPort; `/etc/resolv.conf` is
   pinned to 127.0.0.1 and made immutable (`chattr +i`) for the session; `.i2p` names are answered
   by the i2p layer, never by a clearnet resolver; UDP/TCP 53 to anything but 127.0.0.1 is dropped.
4. **Verify, don't assert.** The daemon proves each invariant at runtime (below) and refuses to
   report ACTIVE until every probe passes. `anond verify` re-runs them on demand and continuously.
5. **Least trust.** No telemetry, minimal deps, no phone-home; every external process is supervised
   and sandboxed; secrets never touch disk unencrypted; swap off during a session.

## State machine (single source of truth)
```
Down ──lock──▶ Locked ──bootstrap──▶ Bootstrapping ──all-probes-pass──▶ Active
  ▲                                        │                              │
  └──────────────── unlock ◀── Draining ◀──┴───── any layer unhealthy ────┘
                                  (egress stays BLOCKED the entire time)
```
Locked = kill-switch up, everything dropped except tor/i2pd bootstrap. We never leave Locked
toward Active until verify passes; we fall back to Locked (blocked) the instant a probe fails.

## Layers
- **Tor** (`tor` module): supervise `tor` with a generated torrc — TransPort 9040 + DNSPort 53 +
  SocksPort 9050, strong stream isolation, IPv6 off, bridges (obfs4/snowflake/meek), guard pinning.
  Transparent redirect of all clearnet TCP + DNS via nftables NAT. Handles clearnet and `.onion`.
- **i2p** (`i2p` module): supervise `i2pd` — HTTP proxy 4444, SOCKS 4447, SAM 7656 off unless asked,
  console on loopback only. `.i2p` traffic is routed to i2pd; i2pd's addressbook resolves eepsites.
  i2p is an overlay reached via its proxy (it has no TransPort), so `.i2p` routing is done at the
  DNS/proxy layer (see below), not IP NAT — this is the honest, reliable way to bundle it.
- **DNS** (`dns` module): a tiny loopback resolver policy — clearnet A/AAAA → Tor DNSPort; `*.i2p`
  → hand to i2pd (or NXDOMAIN to force proxy use); everything pinned, resolv.conf immutable.
- **kill-switch** (`killswitch` module): typed nftables via `rustables` (fallback: `nft -f`).
  inet table, output default drop, nat redirects, ipv6 drop, uid exemptions for tor + i2pd.
- **harden** (`harden` module): MAC spoof, transient hostname, UTC, swapoff, sysctl (port from
  anonkit.py, which already does this correctly and reversibly).
- **verify** (`verify` module): the runtime proofs, each a hard gate:
  - clearnet egress exits as a Tor node (`check.torproject.org/api/ip` over the transparent path).
  - SOCKS path is Tor. DNS resolves only via 127.0.0.1 (resolv immutable + probe).
  - IPv6 has no route and is dropped. Kill-switch holds (simulate tor down → egress blocked).
  - `.onion` reachable via Tor; `.i2p` reachable via i2pd (probe a known eepsite / i2pd console).
  - no WebRTC/STUN/NTP clearnet path. Reports a single honest ACTIVE/DEGRADED verdict.

## Crate layout
```
anond/
  Cargo.toml            # tokio, rustables, serde, anyhow, reqwest(socks), nix
  src/
    main.rs             # CLI: up | down | status | verify | new-identity | i2p | tor
    state.rs            # the fail-closed state machine + session state on disk (0600)
    killswitch.rs       # nftables build/teardown (fail-closed ordering guaranteed here)
    tor.rs              # torrc gen + supervise + bootstrap wait
    i2p.rs              # i2pd config + supervise + proxy/addressbook readiness
    dns.rs              # resolv pin/immutable + .i2p policy
    routing.rs          # transparent NAT wiring for Tor; proxy handoff for i2p
    harden.rs           # mac/hostname/tz/swap/sysctl (reversible, ported from anonkit.py)
    verify.rs           # the runtime leak proofs
    proc.rs             # supervised child + health, no-leak-on-death guarantee
```
CLI stays compatible with today's muscle memory: `anond up [--bridge …] [--i2p]`, `anond down`,
`anond status`, `anond verify`, `anond new-identity`. Ships a thin `anonkit` compat shim.

## arxguard (parallel Rust hot-path work)
arxguard is the zero-trust pre-exec command guard (today a bash DEBUG-trap that scans each command).
The scan is a hot path run on every command → move it to Rust: a tiny `arxguard-scan` binary the
shell hook pipes the command line to, returning allow/block fast, with a richer, versioned ruleset
(argument-aware, not just substring), an audit log, and near-zero latency. Keep the shell hook thin.

## Build/verify plan (each step gated by a real test on the VM)
1. Scaffold crate; `up`/`down` drive only the kill-switch + Tor (parity with anonkit.py) → verify no
   clearnet/DNS/IPv6 leak on the VM (start+stop in one ssh session with a watchdog, per anonkit rule).
2. Add i2pd supervision + `.i2p` proxy/DNS handoff → verify an eepsite loads and clearnet still can't leak.
3. Add continuous verify + kill-switch fault injection (kill tor → confirm egress blocks).
4. Port harden; add bridges/guard-pinning; static musl build; ship via install.sh (source→-dist mirror).
5. arxguard-scan Rust core + hook swap, with the ruleset regression tested.
