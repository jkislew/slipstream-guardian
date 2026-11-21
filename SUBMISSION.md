# DoraHacks submission checklist — Reactive Omni Buildathon

Deadline: **5 Dec 2026, 20:00 UTC = 6 Dec 2026, 03:00 WIB**.
Page: https://dorahacks.io/hackathon/reactive-omni-buildathon/detail
Submission is account-bound: register + submit while signed in to the user's
DoraHacks account (Google sign-in). Everything below is pre-filled; fields
marked _TBD_ come from the live run (see RESULTS.md).

## Before submitting

- [x] Step-0 funding done (DEPLOY.md) — Sepolia ETH → lREACT + Base Sepolia ETH
- [x] Deploy steps 1–4 done; addresses + 3 loop tx hashes recorded in RESULTS.md
- [x] `node scripts/measure-loop.mjs ...` output recorded in RESULTS.md
- [ ] GitHub repo created as **public**: `jkislew/slipstream-guardian`
      (push the contents of this folder; it is a ready git repo)
- [ ] Demo video uploaded (YouTube, unlisted is fine) — final cut must show
      the LIVE loop; script in demo/SCRIPT.md
- [ ] Register for the hackathon on DoraHacks and pick the track below

## Fields

**Project name:** Slipstream Guardian

**Track:** Every Second Counts

**Tagline (one line):**
A stop-loss that fires itself — a Reactive contract on Lasna watches a Base
Sepolia position and executes its protection on-chain in seconds, no keeper
bot, no human awake.

**Description (paste):**

Slipstream Guardian is a self-firing stop-loss / take-profit for DEX
positions. A user opens a position in the GuardianVault on Base Sepolia and
attaches a stop-loss (-10%) and take-profit (+25%). A reactive contract on
Reactive Lasna learns the position from the vault's PositionOpened event,
tracks it in its own storage, and evaluates every PriceUpdated event against
the position's thresholds using precision-safe cross-multiplied math.

When a threshold breaks, the reactive contract requests a callback through
the Reactive system contract. The Base Sepolia callback proxy delivers
protectPosition() to the vault, which authenticates the call twice (proxy
sender + network-injected reactive address), sells the position through the
AMM, and credits the user's proceeds — withdrawable immediately.

Both contracts pay their own way in the Reactive economy: the reactive
contract is funded in lREACT, the vault in Base Sepolia ETH, and both expose
coverDebt(). A triggered position is marked inactive before the callback is
requested, so a burst of price updates can never double-fire an exit.

The repo includes a latency harness (scripts/measure-loop.mjs) that
reconstructs the three block timestamps — origin event, reactive
transaction, callback — and reports the full-loop latency the track asks
for: 1 second in our live run. Nine Foundry tests simulate the entire
loop locally, including both authentication failure modes.

**Repository link:** https://github.com/jkislew/slipstream-guardian

**Deployed contract addresses (paste):**
- StopLossReactive (Reactive Lasna, 5318007): 0x7b2b558279df2b297e999e1282e65d46f88d8ace
- GuardianVault (Base Sepolia, 84532): 0x8759E1c157A981f302D92602ADC557dd5661Cb28
- PriceFeed (Base Sepolia): 0xc0Ef91F8DcF4a38BfE652e06151044eC306b30E6
- MockAMM (Base Sepolia): 0xFF6E288C1F7e6Ed1350F689Db0A46CF12E2B5862
- USDX / VOLT (Base Sepolia): 0x7B2b558279dF2B297E999E1282E65D46f88D8aCe / 0x155B9c7D4fEb716E36090B075EA0E7456f48cDBb

**Transaction hashes showing the full loop (paste):**
- Origin event — PriceFeed.setPrice to $89 (Base Sepolia): 0x5a35401d0409c59865bbb94f0811a64c06ec78c48df7be653ee3821dda333f5e
  (https://sepolia.basescan.org/tx/0x5a35401d0409c59865bbb94f0811a64c06ec78c48df7be653ee3821dda333f5e)
- Reactive transaction — StopLossReactive.react (Lasna): 0xe417a9bf4df6651cbe08baf8cacb76810d0bb6a2ed5216704b88cb7ba947d50d
  (https://lasna.reactscan.net/tx/0xe417a9bf4df6651cbe08baf8cacb76810d0bb6a2ed5216704b88cb7ba947d50d)
- Callback — GuardianVault.protectPosition via proxy (Base Sepolia): 0x154b18ee151765268687e06c733c204620f6f62edabfa00f417d4ff2c2ad7562
  (https://sepolia.basescan.org/tx/0x154b18ee151765268687e06c733c204620f6f62edabfa00f417d4ff2c2ad7562)
- Full-loop latency: 1 second (origin → protection executed)

**Demo video (< 3 min):** _TBD YouTube link_

**Contact / team:** Solo build by jkislew (Jimmy Kislew). Discord: jimmykislew.

## After submitting

- [ ] Open the submission page again and confirm the entry shows as submitted
- [ ] Save the submission URL here: _TBD_
- [ ] Keep the repo public and the contracts funded until judging ends
