// AgentPay demo agent — an AI agent that spends tUSD8 within its allowance.
//
// Full end-to-end demo on QDay Aevum Testnet (chain ID 44005):
//   1. Deposit tUSD8 into the vault
//   2. Create an allowance for the agent (cap + expiry)
//   3. Agent pays a payee from the allowance (twice: one success, one over-cap
//      attempt that reverts, proving the guard works)
//   4. Print receipts with explorer links
//
// The deploy key plays BOTH roles in this demo (owner + agent) so the whole
// flow runs with a single testnet key. In production the owner and the agent
// are different addresses.
//
// Usage:
//   npm install
//   AGENTPAY_ADDRESS=0x... PAYEE=0x... node agent/run-agent.js
//   (PAYEE defaults to the agent itself — paying yourself still proves the
//   on-chain flow without sending test funds anywhere.)
//
// The private key comes from AGENT_PRIVATE_KEY, or (locally) from
// ../hidden_keys/deploy-key.json (mode 600, never committed).
// It is never printed or logged.

const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const RPC = "https://rpc-test.qday.info";
const EXPLORER = "https://explorer-test.qday.info";
const TUSD8 = "0x456569838f1d43009A91ebA4263147Afd7233483";
const AGENTPAY_ADDRESS = process.env.AGENTPAY_ADDRESS;
if (!AGENTPAY_ADDRESS) {
  console.error("Set AGENTPAY_ADDRESS env var to the deployed AgentPay address.");
  process.exit(1);
}

const AGENTPAY_ABI = require("../out/AgentPay.sol/AgentPay.json").abi;
const ERC20_ABI = [
  "function approve(address spender, uint256 amount) returns (bool)",
  "function balanceOf(address account) view returns (uint256)",
  "function decimals() view returns (uint8)",
];

async function main() {
  const privateKey =
    process.env.AGENT_PRIVATE_KEY ||
    JSON.parse(fs.readFileSync(path.join(__dirname, "..", "..", "hidden_keys", "deploy-key.json"), "utf8")).privateKey;
  const provider = new ethers.JsonRpcProvider(RPC);
  const wallet = new ethers.Wallet(privateKey, provider);
  const agentPay = new ethers.Contract(AGENTPAY_ADDRESS, AGENTPAY_ABI, wallet);
  const tusd8 = new ethers.Contract(TUSD8, ERC20_ABI, wallet);
  const payee = process.env.PAYEE || wallet.address;

  const link = (hash) => `${EXPLORER}/tx/${hash}`;
  console.log("Agent:", wallet.address);
  console.log("AgentPay:", AGENTPAY_ADDRESS);
  console.log("Payee:", payee);

  const bal = await tusd8.balanceOf(wallet.address);
  console.log("tUSD8 balance:", ethers.formatUnits(bal, 6));
  if (bal === 0n) {
    console.error("No tUSD8. Claim 1 tUSD8 from https://faucet.qday.info/en first.");
    process.exit(1);
  }

  // 1. Approve + deposit 1 tUSD8 (or the whole balance if smaller).
  const deposit = bal >= 1_000_000n ? 1_000_000n : bal;
  console.log("\n[1] Approving + depositing", ethers.formatUnits(deposit, 6), "tUSD8...");
  await (await tusd8.approve(AGENTPAY_ADDRESS, deposit)).wait();
  let tx = await agentPay.deposit(deposit);
  console.log("    deposit tx:", link(tx.hash));
  await tx.wait();

  // 2. Create a 1 tUSD8 allowance for the agent, expiring in 1 day.
  console.log("\n[2] Creating allowance: cap 1 tUSD8, expiry +1 day...");
  const expiry = Math.floor(Date.now() / 1000) + 24 * 3600;
  tx = await agentPay.createAllowance(wallet.address, 1_000_000n, expiry);
  const receipt = await tx.wait();
  console.log("    createAllowance tx:", link(tx.hash));
  const id = await agentPay.nextAllowanceId().then((n) => n - 1n);
  console.log("    allowance id:", id.toString());

  // 3a. Agent pays 0.5 tUSD8 — should succeed.
  console.log("\n[3a] Agent pays 0.5 tUSD8 (within cap)...");
  tx = await agentPay.pay(id, payee, 500_000n, "demo: api-call #1");
  console.log("    pay tx:", link(tx.hash));
  await tx.wait();
  console.log("    remaining:", ethers.formatUnits(await agentPay.allowanceRemaining(id), 6), "tUSD8");

  // 3b. Agent tries to pay 0.6 tUSD8 — exceeds the remaining 0.5, must revert.
  console.log("\n[3b] Agent tries to pay 0.6 tUSD8 (over remaining cap) — expect revert...");
  try {
    tx = await agentPay.pay(id, payee, 600_000n, "demo: over-cap attempt");
    await tx.wait();
    console.log("    !! UNEXPECTED: over-cap payment succeeded");
  } catch (e) {
    console.log("    Reverted as designed:", (e.shortMessage || e.message || "").split("\n")[0]);
  }
  console.log("    remaining:", ethers.formatUnits(await agentPay.allowanceRemaining(id), 6), "tUSD8");

  console.log("\nDone. Verify every step on the explorer links above.");
}

main().catch((e) => {
  console.error("Agent run failed:", e.shortMessage || e.message);
  process.exit(1);
});
