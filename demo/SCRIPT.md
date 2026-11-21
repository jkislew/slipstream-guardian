# Demo video — Slipstream Guardian (target 2:30, hard cap 3:00)

Two ways to produce the final cut:

- **Preferred (after the live run):** screen-record the real loop —
  terminal running the demo commands + Lasna/Base explorers — and narrate
  with the script below. Shots marked 🎥 are the recording slots.
- **Draft (already buildable now):** `demo/build-video.sh` renders the slide
  deck with the narration as captions. It proves timing and structure; swap
  in the live footage for the final submission.

## Shot list + narration

**0:00 — Title slide**
On screen: "Slipstream Guardian — a stop-loss that fires itself.
Reactive Omni Buildathon · Every Second Counts"
Narration: "This is Slipstream Guardian: a stop-loss that fires itself, built
on Reactive Network."

**0:08 — The problem**
On screen: "A bot can die. A human sleeps. A stop-loss kept off-chain is a
promise, not a guarantee."
Narration: "Every DEX trader knows the setup: you place a stop-loss with a
bot, and you trust the bot to be alive, funded, and fast when the price
gaps. At 3 a.m., that is a promise, not a guarantee. We moved the stop-loss
into a contract."

**0:26 — Architecture**
On screen: diagram — Base Sepolia (PriceFeed, GuardianVault) ⇄ Reactive
Lasna (StopLossReactive). "Three contracts, two chains, one loop."
Narration: "Three contracts do the work. On Base Sepolia, a vault holds the
position and a feed reports the price. On Reactive Lasna, one reactive
contract watches everything and decides. When it decides, a callback
executes back on Base Sepolia."

**0:48 — Opening a position** 🎥
On screen: terminal — OpenPosition script output; explorer showing
PositionOpened.
Narration: "A user deposits a thousand test dollars and opens a position:
ten VOLT at a hundred dollars, a stop at minus ten percent, a target at plus
twenty-five. The vault emits PositionOpened — and that event is how the
reactive contract learns the position, its entry, and its lines. Nobody
registers anything by hand."

**1:12 — The crash** 🎥
On screen: terminal — MovePrice to $89; Lasna explorer — the react()
transaction; Base explorer — ProtectionExecuted.
Narration: "Now the market breaks. The price drops to eighty-nine — through
the stop. Watch the chain, not a dashboard: the price event lands, Lasna's
reactive contract evaluates it against the stored thresholds, fires exactly
once, and the callback sells the position on Base Sepolia. Eight hundred
ninety dollars are credited to the user, withdrawable immediately. No bot
was running. Nobody was awake."

**1:44 — Measured, not asserted**
On screen: measure-loop.mjs output with the three hashes and the total.
Narration: "The track asks for latency across the full loop, so we measure
it from the chains themselves: origin block, reactive block, callback
block. [READ THE MEASURED NUMBER FROM RESULTS.md.] Three transactions,
three timestamps, one number."

**2:02 — Under the hood**
On screen: code highlights — cross-multiplied threshold math; mark-inactive
before firing; double callback authentication; coverDebt().
Narration: "The details are production details: threshold math is
cross-multiplied so it never loses precision; a position is marked inactive
before the callback fires, so a burst of updates cannot double-sell it; the
callback is authenticated twice; and both contracts pay their own way in
the Reactive economy and can settle their own debt."

**2:24 — Close**
On screen: "Slipstream Guardian — the stop-loss is the contract.
github.com/jkislew/slipstream-guardian"
Narration: "Slipstream Guardian: the stop-loss is the contract. Code, tests,
and the full deployment runbook are in the repository. Thank you."

## Recording notes

- Record at 1080p; keep explorer pages pre-loaded in tabs (Base Sepolia tx,
  Lasna react tx, Base callback tx) so no shot waits on a page load.
- The price move and the loop take seconds on Lasna; if the callback is
  already mined when you cut to the explorer, that is the point — say so.
- Total narration ≈ 330 words ≈ 2:20 at a natural pace; slides pad to 2:30.
