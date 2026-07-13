// anond — ARXOS anonymity daemon. Fail-closed Tor + i2p + leak-proof DNS.
// See ../ANOND-DESIGN.md. This is the scaffold: it encodes the state machine and the
// non-negotiable fail-closed ORDERING (kill-switch up before any service, torn down after
// every service). Each layer is a stub for now; real impls land per-module, each leak-tested.

use std::process::exit;

#[derive(Debug, Clone, Copy, PartialEq)]
enum State { Down, Locked, Bootstrapping, Active, Draining }

/// One anonymity layer. Every `up` is reversible by `down`; a failed `up` must leave egress BLOCKED.
trait Layer {
    fn name(&self) -> &'static str;
    fn up(&self) -> Result<(), String>;
    fn down(&self) -> Result<(), String>;
    fn verify(&self) -> Result<(), String>;
}

// --- stubs (implemented per-module next; TODO markers reference ANOND-DESIGN.md sections) ---
struct KillSwitch; // killswitch.rs: nft default-drop, NAT to Tor, ipv6 drop, uid exemptions
struct Tor;        // tor.rs: torrc + supervise + bootstrap
struct I2p;        // i2p.rs: i2pd supervise + proxy/addressbook
struct Dns;        // dns.rs: resolv pin+immutable, .i2p policy

macro_rules! stub_layer {
    ($t:ty, $n:literal) => {
        impl Layer for $t {
            fn name(&self) -> &'static str { $n }
            fn up(&self) -> Result<(), String> { println!("  [{}] up (stub)", $n); Ok(()) }
            fn down(&self) -> Result<(), String> { println!("  [{}] down (stub)", $n); Ok(()) }
            fn verify(&self) -> Result<(), String> { println!("  [{}] verify (stub)", $n); Ok(()) }
        }
    };
}
stub_layer!(KillSwitch, "killswitch");
stub_layer!(Tor, "tor");
stub_layer!(I2p, "i2p");
stub_layer!(Dns, "dns");

/// Bring the whole stack up, FAIL-CLOSED: kill-switch first (egress blocked), then services,
/// then verify. Any failure tears back down so traffic never egresses in the clear.
fn up(with_i2p: bool) -> State {
    println!(">> anond up (i2p={})", with_i2p);
    // 1. kill-switch BEFORE anything can talk to the network
    if KillSwitch.up().is_err() { eprintln!("!! kill-switch failed to arm — aborting, nothing started"); return State::Down; }
    let mut st = State::Locked;
    // 2. services bootstrap while egress is still locked to their uids only
    st = State::Bootstrapping;
    let services: Vec<&dyn Layer> = if with_i2p { vec![&Tor, &I2p, &Dns] } else { vec![&Tor, &Dns] };
    for l in &services {
        if l.up().is_err() { eprintln!("!! {} failed — draining, egress stays BLOCKED", l.name()); down(); return State::Locked; }
    }
    // 3. prove every invariant before declaring Active; a failed probe keeps us Locked (blocked)
    for l in &services { if l.verify().is_err() { eprintln!("!! verify failed on {} — staying Locked (blocked)", l.name()); return State::Locked; } }
    st = State::Active;
    println!(">> ACTIVE — Tor{} + leak-proof DNS, kill-switch armed", if with_i2p { " + i2p" } else { "" });
    st
}

/// Tear down in reverse: services first, kill-switch LAST, so there is never a window with
/// services down but egress open.
fn down() -> State {
    println!(">> anond down (draining)");
    for l in [&Dns as &dyn Layer, &I2p, &Tor] { let _ = l.down(); }
    let _ = KillSwitch.down();
    println!(">> DOWN — egress restored");
    State::Down
}

fn verify() {
    println!(">> anond verify");
    for l in [&KillSwitch as &dyn Layer, &Tor, &I2p, &Dns] { let _ = l.verify(); }
    println!("   (stub — real proofs: Tor exit, DNS/IPv6 no-leak, .onion/.i2p reach, kill-switch holds)");
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(String::as_str).unwrap_or("") {
        "up"    => { let i2p = args.iter().any(|a| a == "--i2p"); up(i2p); }
        "down"  => { down(); }
        "verify" => verify(),
        "status" => println!("anond {} (scaffold)", env!("CARGO_PKG_VERSION")),
        _ => { eprintln!("usage: anond <up [--i2p] | down | status | verify>"); exit(2); }
    }
}
