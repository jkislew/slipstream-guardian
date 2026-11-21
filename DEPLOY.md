# Deployment runbook — Slipstream Guardian

Two chains: **Base Sepolia (84532)** hosts the market and the vault;
**Reactive Lasna (5318007)** hosts the reactive contract. One deployer
address is used on both. All commands run from the repo root with Foundry.

## Step 0 — Fund the deployer (testnet only)

The deployer needs three balances. Everything is testnet and free; the only
friction is that public faucets are captcha/account-gated web pages, so this
step is done in a browser once (about 3 minutes):

1. **Sepolia ETH** — claim from any Sepolia faucet (e.g. the PoW faucet at
   https://sepolia-faucet.pk910.de — it requires solving its captcha in the
   browser; programmatic session start returns `INVALID_CAPTCHA`).
   Send it to the deployer address.
2. **lREACT (Lasna)** — send `0.1` Sepolia ETH from the deployer to the
   Reactive faucet contract on Ethereum Sepolia:
   `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`
   Rate is 1 ETH → 100 lREACT, so 0.1 ETH yields 10 lREACT at the same
   address on Lasna. (Base Sepolia variant: `0x2afaFD298b23b62760711756088F75B7409f5967`.)
   This transfer can be done with `cast send` once step 1 has landed:
   ```
   cast send 0x9b9BB25f1A81078C544C829c5EB7822d747Cf434 --value 0.1ether \
     --rpc-url https://ethereum-sepolia-rpc.publicnode.com --private-key $PRIVATE_KEY
   ```
3. **Base Sepolia ETH** — bridge a little Sepolia ETH across with the
   official Base bridge (https://bridge.base.org/deposit, Sepolia →
   Base Sepolia), or claim from a Base Sepolia faucet. `0.05` ETH is far
   more than the demo needs (deployments + vault callback funding of
   0.2 ETH is budgeted generously; actual callback charges are tiny).

Verify before continuing:
```
cast balance $DEPLOYER --rpc-url https://lasna-rpc.rnk.dev/          # > 5 lREACT
cast balance $DEPLOYER --rpc-url https://base-sepolia-rpc.publicnode.com  # > 0.25 ETH
```

## Step 1 — Deploy the market (Base Sepolia)

```
export PRIVATE_KEY=0x...            # deployer key (testnet only)
forge script script/DeployOrigin.s.sol --rpc-url base_sepolia \
  --broadcast --private-key $PRIVATE_KEY
```
Record `USDX`, `VOLT`, `PriceFeed`, `MockAMM` from the output.

## Step 2 — Deploy the reactive contract (Lasna)

```
export FEED_ADDR=<PriceFeed from step 1>
forge script script/DeployReactive.s.sol --rpc-url lasna \
  --broadcast --private-key $PRIVATE_KEY
```
Deploys `StopLossReactive` with 5 lREACT of funding (override with
`FUND_LREACT`). Record its address as `REACTIVE_ADDR`.

## Step 3 — Deploy the vault (Base Sepolia)

```
export REACTIVE_ADDR=<from step 2> USDX_ADDR=... VOLT_ADDR=... \
       FEED_ADDR=... AMM_ADDR=...
forge script script/DeployVault.s.sol --rpc-url base_sepolia \
  --broadcast --private-key $PRIVATE_KEY
```
Deploys `GuardianVault` funded with 0.2 ETH for callback billing
(override with `FUND_CALLBACK_ETH`). Record as `VAULT_ADDR`.

## Step 4 — Wire the vault into the reactive contract (Lasna)

```
export REACTIVE_ADDR=... VAULT_ADDR=...
forge script script/SetVault.s.sol --rpc-url lasna \
  --broadcast --private-key $PRIVATE_KEY
```

## Step 5 — Run the demo loop

```
# open a position (demo user key; can be the deployer)
export USDX_ADDR=... VAULT_ADDR=...
forge script script/OpenPosition.s.sol --rpc-url base_sepolia \
  --broadcast --private-key $PRIVATE_KEY

# crash the price from $100 to $89 (entry $100, stop -10% -> fires)
export FEED_ADDR=... NEW_PRICE=8900000000
forge script script/MovePrice.s.sol --rpc-url base_sepolia \
  --broadcast --private-key $PRIVATE_KEY
# ^^^ save this tx hash; it is leg 1 of the loop.

# measure the full loop
node scripts/measure-loop.mjs --origin <setPriceTxHash> \
  --vault $VAULT_ADDR --reactive $REACTIVE_ADDR
```

Expected: within seconds the reactive contract fires, the callback lands on
Base Sepolia, `ProtectionExecuted` is emitted, and the user's `claimable`
shows 890 USDX (10 VOLT × $89). The user withdraws with
`cast send $VAULT_ADDR "withdraw()" --rpc-url base_sepolia --private-key $PRIVATE_KEY`.

Record all addresses and the three tx hashes (origin / react / callback) in
RESULTS.md, and verify the Lasna contract on Sourcify:
```
forge verify-contract --verifier sourcify --chain-id 5318007 \
  $REACTIVE_ADDR StopLossReactive
```

## Troubleshooting

- **Reactive contract silent** — check its lREACT balance and debt:
  a contract in debt receives nothing. Top it up (send lREACT to its
  address) and call `coverDebt()`.
- **Callback never lands** — check the vault's Base Sepolia ETH balance and
  debt the same way (`coverDebt()` on the vault). A failed callback still
  bills the vault; look for `CallbackFailure` events from the proxy
  `0x476F44b11F5C942c58f4c8E3d0300E5710743585`.
- **Position opened but never tracked** — `setVault` must come after the
  vault exists and before positions open; subscriptions only see new events.
