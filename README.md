# Slipstream Guardian — a stop-loss that fires itself

**Track: Every Second Counts (Reactive Omni Buildathon)**

A DEX position does not watch itself. When the price gaps down at 3 a.m., a
stop-loss kept by a bot depends on that bot being alive, funded, and fast —
and a stop-loss kept by a human depends on the human being awake. Slipstream
Guardian removes both from the loop: the stop-loss *is a contract*, enforced
by Reactive Network the moment the price event exists.

A user opens a position on **Base Sepolia** and attaches a stop-loss and a
take-profit. A reactive contract on **Reactive Lasna** tracks the position
and watches the price feed. The instant the price crosses either line, the
reactive contract orders a callback, and the vault on Base Sepolia sells the
position and credits the proceeds. No keeper, no server, no polling — the
full loop is three on-chain transactions, and this repo measures exactly how
long it takes.

## The loop

```
Base Sepolia                 Reactive Lasna                Base Sepolia
─────────────                ──────────────                ────────────
PriceFeed.setPrice() ──► StopLossReactive.react() ──► GuardianVault
  emits PriceUpdated       checks every tracked          .protectPosition()
                           position's stop/target        sells via AMM,
                                                         credits the user
```

1. **Origin event.** `PriceFeed` emits `PriceUpdated`. (In production this is
   a DEX pool's `Sync` or an oracle update; the wiring is identical.)
2. **Reactive decision.** `StopLossReactive` learned the position from the
   vault's `PositionOpened` event — entry price, stop, target — and keeps it
   in its own storage. On each price update it cross-multiplies
   (`price * 10_000` vs `entry * (10_000 ± bps)`) so threshold math never
   loses precision, marks a triggered position inactive *before* firing (a
   burst of updates can never double-fire), and requests a callback through
   the system contract (`requestCallbackV_1_0`).
3. **Callback execution.** The Base Sepolia callback proxy delivers
   `protectPosition()` to `GuardianVault`. The call is authenticated twice —
   it must arrive through the proxy, and the network-injected first argument
   must be our reactive contract — then the vault sells through the AMM and
   credits the user's USDX, withdrawable immediately.

## Why this is real work, not a bolt-on

The reactive contract is the only component that knows the thresholds, the
only component watching the price, and the only thing that can trigger an
exit. Remove it and the vault is a passive box: positions can be closed
manually, but nothing protects them. The judging criterion "does the
reactive contract do real work" is the architecture here, not a feature.

## Latency

`scripts/measure-loop.mjs` reconstructs the three block timestamps from the
chains and prints the full-loop latency the track brief asks for:

```
node scripts/measure-loop.mjs --origin <setPriceTx> \
    --vault <GuardianVault> --reactive <StopLossReactive>
```

Measured results from the live run are recorded in [RESULTS.md](RESULTS.md).

## Contracts

| Contract | Chain | Role |
|---|---|---|
| `PriceFeed` | Base Sepolia (84532) | Price oracle; emits the origin event |
| `MockAMM` | Base Sepolia | Constant-price exchange standing in for a DEX pool |
| `MockToken` (×2) | Base Sepolia | USDX (stable) and VOLT (volatile) test assets, with a public faucet |
| `GuardianVault` | Base Sepolia | Holds positions; receives authenticated callbacks; pays for them in ETH |
| `StopLossReactive` | Reactive Lasna (5318007) | Tracks positions, watches prices, fires protection callbacks; pays in lREACT |

Deployment follows the order the Reactive docs prescribe — reactive first,
callback contract second (it immutably authorizes the reactive address),
then an owner call wires the vault into the reactive contract. Full runbook:
[DEPLOY.md](DEPLOY.md).

## Tests

`forge test` — 9 tests, including a full local simulation of the loop: the
test etches a recording system contract onto the real system address
(`0x8888…8888`), delivers fabricated log records as the system contract, and
delivers the callback as the real Base Sepolia proxy
(`0x476F…3585`). Stop-loss, take-profit, manual close, duplicate-fire
protection, and both authentication failures are covered. The same
deployment scripts were also dry-run end-to-end on a local node.

## Repository layout

```
src/        the five contracts
script/     deployment + demo scripts (Foundry)
test/       unit + full-loop simulation tests
scripts/    measure-loop.mjs — full-loop latency measurement
demo/       demo video script, storyboard, and build script
DEPLOY.md   deployment runbook (including testnet funding)
RESULTS.md  live deployment addresses, tx hashes, measured latency
```

## Notes on scope

The price feed and AMM are deliberate stand-ins: deterministic liquidity and
a controllable price make the demo reproducible by any judge in minutes.
Everything being judged — subscription, reactive state tracking, threshold
logic, authenticated cross-chain callback, self-paying contracts — is the
production pattern from the Reactive Omni docs, unchanged.

Built during the Reactive Omni Buildathon (Nov 5 – Dec 5, 2026).
License: MIT.
