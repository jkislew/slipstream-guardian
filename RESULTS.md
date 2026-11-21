# Results — Slipstream Guardian

## Live deployment (Lasna + Base Sepolia)

> Status: **LIVE — full loop executed on-chain on 2026-11-21.** Funding
> came from the pk910 PoW faucet (0.05 Sepolia ETH, captcha solved by the
> user in the browser). Because that was less than the runbook's assumed
> budget, the amounts were adapted: 0.02 ETH was exchanged at the Lasna
> faucet (→ 2.1 lREACT), 0.02 ETH was bridged to Base Sepolia via the
> canonical L1 bridge `0xfd0Bf71F60660E2f608ed56e1659C450eB113120`,
> ~0.01 ETH stayed on Sepolia as gas reserve; the reactive contract was
> funded with 1.5 lREACT (runbook default 5) and the vault with 0.01 ETH
> (runbook default 0.2). Both proved far more than the loop costs:
> the reactive contract still holds ~1.447 lREACT and the vault ~0.009999
> ETH after the run.

| Item | Value |
|---|---|
| Deployer | `0x3616BD2Fa8fa1e4116bD274d1d3Cfc2c8CCf341f` (throwaway testnet wallet) |
| USDX (Base Sepolia) | `0x7B2b558279dF2B297E999E1282E65D46f88D8aCe` |
| VOLT (Base Sepolia) | `0x155B9c7D4fEb716E36090B075EA0E7456f48cDBb` |
| PriceFeed (Base Sepolia) | `0xc0Ef91F8DcF4a38BfE652e06151044eC306b30E6` |
| MockAMM (Base Sepolia) | `0xFF6E288C1F7e6Ed1350F689Db0A46CF12E2B5862` |
| GuardianVault (Base Sepolia) | `0x8759E1c157A981f302D92602ADC557dd5661Cb28` |
| StopLossReactive (Lasna) | `0x7b2b558279df2b297e999e1282e65d46f88d8ace` (Sourcify **exact_match**, chain 5318007) |
| Origin tx — `setPrice($89)` (Base Sepolia) | `0x5a35401d0409c59865bbb94f0811a64c06ec78c48df7be653ee3821dda333f5e` |
| Reactive tx — `react()` (Lasna) | `0xe417a9bf4df6651cbe08baf8cacb76810d0bb6a2ed5216704b88cb7ba947d50d` |
| Callback tx — `protectPosition()` (Base Sepolia) | `0x154b18ee151765268687e06c733c204620f6f62edabfa00f417d4ff2c2ad7562` |
| Full-loop latency (origin → protection) | **1 second** (block timestamps: origin 1795219117 → react 1795219116 → callback 1795219118; the −1 s react leg is cross-chain block-clock granularity — delivery was effectively immediate, callback +2 s after react) |
| Proceeds credited | **890 USDX** — credited to the user's `claimable` by the callback and withdrawn (tx `0xe2c282809cd05286cea83c2ca4c1a52230091dfad82ddefc8af421c4b8a708bb`); user USDX balance 9,000 → 9,890 ✓ |

Funding trail (Sepolia): faucet exchange tx
`0xcb7d908968fb5dd573f5d0c1429d85b11a634b71a2d33cc656e1254a48f3e184`
(0.02 ETH → 2.1 lREACT); bridge deposit tx
`0x4d39fd6b44d6948ef26963a4cc284ff31e2b687ad71f75daadae911156f860f1`
(0.02 ETH → Base Sepolia).

Latency harness note: `scripts/measure-loop.mjs` was fixed during this
run — on the live network a `react()` delivery is a transaction TO the
system contract (`0x8888…8888`) that invokes the reactive contract
internally, so the original block scan for `tx.to == reactive` could
never find it. The harness now locates the delivery via the first log
emitted by the reactive contract at/after the origin timestamp. Its
output for this run:

```
Origin   : 0x5a35401d0409c59865bbb94f0811a64c06ec78c48df7be653ee3821dda333f5e (Base Sepolia block 61486244, t=1795219117)
React    : 0xe417a9bf4df6651cbe08baf8cacb76810d0bb6a2ed5216704b88cb7ba947d50d (Lasna block 8850237, t=1795219116)  +-1s
Callback : 0x154b18ee151765268687e06c733c204620f6f62edabfa00f417d4ff2c2ad7562 (Base Sepolia block 61486250, t=1795219118)  +2s after react
FULL LOOP (origin event -> protection executed): 1 seconds
```

## Local end-to-end evidence (already achieved)

The identical contracts and the identical deployment scripts were run
end-to-end on a local node (Anvil), with the two network deliveries
impersonated by the real actor addresses (system contract `0x8888…8888`,
Base Sepolia callback proxy `0x476F…3585`):

| Step | Tx (local chain) | Result |
|---|---|---|
| Open position (1,000 USDX → 10 VOLT @ $100, stop −10%, target +25%) | — | position open, entry 100e8 |
| `react()` delivery of `PositionOpened` | `0x31de063627756ce6f2d213211acc40f162c57c1928bb748ddca065b1d7ae2c6a` | position tracked |
| `react()` delivery of `PriceUpdated($89)` | `0xf459dd6163d88f34c8bf1e78bd0f256e8fc9d947111f159a32ab2a4b13b9bd0d` | `triggers = 1`, callback requested |
| Callback `protectPosition()` via proxy | `0x18ade21fae4ba5e5ae86cbdbef656a7f564df2590f78fe225b9cd985ca8f4034` | 890 USDX credited |
| `withdraw()` | `0x74d00916230a5287872b9d46f13b63824c0a0f23d95925ae38c7f544fdb49902` | user balance 9,890 USDX (10,000 − 1,000 + 890) ✓ |

Unit tests: **9/9 passing** (`forge test`), covering stop-loss, take-profit,
manual close + untracking, duplicate-fire protection, in-band no-op, and
both callback authentication failures.
