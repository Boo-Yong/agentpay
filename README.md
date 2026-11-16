# AgentPay — AI agents pay in tUSD8, inside limits you set

**Aevum Builder Challenge #1** (DoraHacks) — Native AI Assistants track.
Free, online hackathon on QDay Aevum Testnet. Prizes: $1,500 USDT (1st $800 / 2nd $500 / 3rd $200).

## Problem

AI agents are starting to do real work — calling APIs, ordering services, paying
for compute. But giving an agent your wallet is all-or-nothing: it can drain
everything, forever, with no receipt. What agents need is a **spending
allowance**: a cap, an expiry, and a kill switch — enforced on-chain, not by
trusting the agent's prompt.

## What AgentPay does

1. **You deposit tUSD8** into your vault in the `AgentPay` contract.
2. **You grant an agent an allowance**: max amount (`cap`) + expiry date.
3. **The agent pays payees** (APIs, merchants, services) from your vault —
   but only up to the cap, only before expiry, only while the allowance is active.
4. **You can revoke anytime.** Every payment emits a `PaymentMade` receipt
   event, verifiable on the explorer.

One end-to-end flow: deposit → allowance → agent payment → on-chain receipt.

## Architecture

```
User (MetaMask) ──deposit tUSD8──▶ AgentPay vault (tUSD8)
User ──createAllowance(agent, cap, expiry)──▶ AgentPay
Agent (script) ──pay(id, payee, amount, memo)──▶ AgentPay ──tUSD8──▶ Payee
   ▲ enforced on-chain: caller is the agent, not revoked, not expired,
   │ spent + amount <= cap, vault funded. Anything else reverts.
   └─ every payment emits PaymentMade(id, agent, payee, amount, memo)
UI (ui/index.html) — balances, deposit/withdraw, allowances, receipts
```

## Tech

- Solidity 0.8.20, Foundry, OpenZeppelin (IERC20 + SafeERC20 + ReentrancyGuard)
- Network: QDay Aevum Testnet — chain ID **44005**, RPC `https://rpc-test.qday.info`,
  explorer `https://explorer-test.qday.info`
- Token: **tUSD8** `0x456569838f1d43009A91ebA4263147Afd7233483` (ERC-20, 6 decimals)
- Frontend: static page + ethers v6 (CDN), MetaMask
- Agent: Node.js + ethers v6 (`agent/run-agent.js`)

## Repo layout

```
src/AgentPay.sol        the contract
test/AgentPay.t.sol     11 forge tests (cap, expiry, revoke, agent-only, ...)
script/Deploy.s.sol     deployment script
agent/run-agent.js      demo agent: deposit → allowance → pay → over-cap revert
ui/index.html + abi.js  demo UI (connect wallet, deposit, allowances, receipts)
```

## Run it

```bash
# install
forge install            # already vendored under lib/
npm install              # agent deps (ethers)

# test
forge test

# deploy (needs a funded testnet key — see below)
TUSD8=0x456569838f1d43009A91ebA4263147Afd7233483 \
forge script script/Deploy.s.sol --rpc-url https://rpc-test.qday.info \
  --private-key $PRIVATE_KEY --broadcast

# verify on the explorer
forge verify-contract <ADDRESS> src/AgentPay.sol:AgentPay \
  --chain-id 44005 --verifier blockscout \
  --verifier-url https://explorer-test.qday.info/api \
  --constructor-args $(cast abi-encode "constructor(address)" $TUSD8)

# run the demo agent (after deploy)
AGENTPAY_ADDRESS=0x... node agent/run-agent.js

# UI: serve ui/ and open index.html?contract=0x... (any static server),
# connect MetaMask on Aevum
```

## Testnet funds

Get tQDAY (gas) + tUSD8 from https://faucet.qday.info/en — 5 tQDAY + 1 tUSD8
per 24h. Note: the faucet checks that the **recipient address holds ETH, USDT
or USDC on Ethereum mainnet** (anti-Sybil). If your address is fresh, claim to
a wallet that holds one of those, then send the testnet tokens onward — or ask
the QDay team in their Discord (office hours Mon–Fri 10:00–18:00 HKT).

## Deployed addresses (Aevum Testnet, 44005)

| Contract | Address |
| -------- | ------- |
| tUSD8 | `0x456569838f1d43009A91ebA4263147Afd7233483` |
| AgentPay | `0x4f7eb8e04b26213acfb02b19b4334f64f13b73e7` (verified; deploy tx `0x005bb0c7e9a874fb000f911d45e4d69adda676409706d59508429b7820045147`) |

## Security notes

- Least privilege by design: an agent can only spend up to its cap, only before
  expiry, and the owner can revoke instantly. The agent never holds user funds.
- `pay` is `nonReentrant` and uses `SafeERC20`; all failure modes revert with
  custom errors (`CapExceeded`, `AllowanceExpired`, `AllowanceAlreadyRevoked`,
  `NotAgent`, `InsufficientVault`, ...).
- No admin keys, no upgradeability, no owner backdoor. Testnet only — tUSD8
  has no monetary value.

## How it maps to the judging criteria

- **Innovation (20)** — agentic payment primitive: allowances for autonomous agents.
- **Safety, trust & controls (15)** — caps, expiry, instant revocation, audit trail.
- **Technical quality (15)** — tested (11/11), verified source, standard tooling.
- **Real-world utility (15)** — every AI agent that pays for APIs/services needs this.
- **UX (15) / Demo (10) / Docs (10)** — one-click UI, reproducible demo script, this README.

## License

MIT
