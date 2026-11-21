#!/usr/bin/env node
/**
 * measure-loop.mjs — measure the full event -> react -> callback loop latency.
 *
 * The "Every Second Counts" brief asks for latency measured across the FULL
 * loop, not one leg. This script reconstructs the three timestamps from the
 * chains themselves:
 *
 *   T0  Base Sepolia block timestamp of the origin tx (PriceFeed.setPrice)
 *   T1  Lasna block timestamp of the reactive tx (StopLossReactive.react)
 *   T2  Base Sepolia block timestamp of the callback tx (ProtectionExecuted)
 *
 * Usage:
 *   node scripts/measure-loop.mjs --origin <setPriceTxHash> \
 *       --vault <GuardianVault address> --reactive <StopLossReactive address> \
 *       [--wait 240]
 *
 * It polls Lasna blocks for the first transaction to the reactive contract at
 * or after T0, and Base Sepolia logs for the vault's ProtectionExecuted event.
 * Zero dependencies (Node >= 18, uses global fetch).
 */

const BASE_RPC = process.env.BASE_SEPOLIA_RPC || "https://base-sepolia-rpc.publicnode.com";
const LASNA_RPC = process.env.LASNA_RPC || "https://lasna-rpc.rnk.dev/";
// topic0 of ProtectionExecuted(address,uint8,uint256,uint256,uint256),
// computed with `cast sig-event` (kept as a constant so the script stays
// dependency-free).
const PROTECTION_TOPIC =
  process.env.PROTECTION_TOPIC || "0x2b42216102e637551679f3d47a7a241940a0473788df36ec372d73e43d8c949f";

async function rpc(url, method, params) {
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  const json = await res.json();
  if (json.error) throw new Error(`${method}: ${JSON.stringify(json.error)}`);
  return json.result;
}

const hex = (n) => "0x" + n.toString(16);
const int = (h) => parseInt(h, 16);

async function blockTs(url, blockNumber) {
  const b = await rpc(url, "eth_getBlockByNumber", [hex(blockNumber), false]);
  return int(b.timestamp);
}

async function findReactTx(reactive, t0, waitSec) {
  const deadline = Date.now() + waitSec * 1000;
  let n = int(await rpc(LASNA_RPC, "eth_blockNumber", []));
  // Locate the scan start by block timestamp (Lasna does ~1 block/sec).
  // Cross-chain block clocks can skew by a few seconds, and a reactive tx
  // can sit in a Lasna block stamped slightly BEFORE the origin block's
  // timestamp. So locate the start a minute early for efficiency, but
  // only ACCEPT a delivery whose block is stamped within a few seconds
  // of t0 — tight enough not to mistake an earlier unrelated delivery
  // (such as the PositionOpened reaction) for this loop's react.
  const tSearch = t0 - 60;
  const tAccept = t0 - 5;
  let start = Math.max(0, n - 3600);
  const startTs = await blockTs(LASNA_RPC, start);
  if (startTs < tSearch) {
    // binary search for the first block with timestamp >= tSearch
    let lo = start, hi = n;
    while (lo < hi) {
      const mid = Math.floor((lo + hi) / 2);
      (await blockTs(LASNA_RPC, mid)) >= tSearch ? (hi = mid) : (lo = mid + 1);
    }
    start = lo;
  }
  // Deliveries are transactions TO the Reactive system contract
  // (0x8888…8888) that invoke the reactive contract internally, so a
  // block scan for tx.to == reactive can never find them. Instead, find
  // the first log EMITTED BY the reactive contract at or after tAccept:
  // its transaction is the react() delivery.
  for (;;) {
    const logs = await rpc(LASNA_RPC, "eth_getLogs", [
      { fromBlock: hex(start), toBlock: "latest", address: reactive },
    ]);
    for (const log of logs) {
      const block = int(log.blockNumber);
      const ts = await blockTs(LASNA_RPC, block);
      if (ts >= tAccept) return { hash: log.transactionHash, ts, block };
    }
    if (Date.now() > deadline) return null;
    await new Promise((r) => setTimeout(r, 2000));
  }
}

async function findCallbackTx(vault, fromBlock, waitSec) {
  const deadline = Date.now() + waitSec * 1000;
  for (;;) {
    const logs = await rpc(BASE_RPC, "eth_getLogs", [
      { fromBlock: hex(fromBlock), toBlock: "latest", address: vault, topics: [PROTECTION_TOPIC] },
    ]);
    if (logs.length > 0) {
      const log = logs[0];
      const ts = await blockTs(BASE_RPC, int(log.blockNumber));
      return { hash: log.transactionHash, ts, block: int(log.blockNumber) };
    }
    if (Date.now() > deadline) return null;
    await new Promise((r) => setTimeout(r, 2000));
  }
}

async function main() {
  const args = process.argv.slice(2);
  const get = (k) => args[args.indexOf(k) + 1];
  const origin = get("--origin");
  const vault = get("--vault");
  const reactive = get("--reactive");
  const waitSec = parseInt(get("--wait") || "240", 10);
  if (!origin || !vault || !reactive) {
    console.error("Required: --origin <txHash> --vault <addr> --reactive <addr> [--wait seconds]");
    process.exit(2);
  }

  const receipt = await rpc(BASE_RPC, "eth_getTransactionReceipt", [origin]);
  if (!receipt) throw new Error("origin tx not found on Base Sepolia");
  const originBlock = int(receipt.blockNumber);
  const t0 = await blockTs(BASE_RPC, originBlock);

  console.log(`Origin   : ${origin} (Base Sepolia block ${originBlock}, t=${t0})`);
  console.log("Scanning Lasna for the reactive transaction...");
  const react = await findReactTx(reactive, t0, waitSec);
  if (!react) throw new Error("reactive tx not found within wait window");
  console.log(`React    : ${react.hash} (Lasna block ${react.block}, t=${react.ts})  +${react.ts - t0}s`);

  console.log("Scanning Base Sepolia for the ProtectionExecuted callback...");
  const cb = await findCallbackTx(vault, originBlock, waitSec);
  if (!cb) throw new Error("callback tx not found within wait window");
  console.log(`Callback : ${cb.hash} (Base Sepolia block ${cb.block}, t=${cb.ts})  +${cb.ts - react.ts}s after react`);

  console.log("");
  console.log(`FULL LOOP (origin event -> protection executed): ${cb.ts - t0} seconds`);
  console.log(`  origin -> react   : ${react.ts - t0}s`);
  console.log(`  react  -> callback: ${cb.ts - react.ts}s`);
  console.log("");
  console.log("Explorer links:");
  console.log(`  origin   https://sepolia.basescan.org/tx/${origin}`);
  console.log(`  react    https://lasna.reactscan.net/tx/${react.hash}`);
  console.log(`  callback https://sepolia.basescan.org/tx/${cb.hash}`);
}

main().catch((e) => {
  console.error("ERROR:", e.message);
  process.exit(1);
});
