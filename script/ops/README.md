# Ops scripts

One-off admin operations against a live deployment. Each script reads the chain's address book
(`addresses/addresses-<chainId>.json`) and the `.env` that forge loads from this directory. They
never read a private key: the signer comes from the wallet flags on the command line.

## Genesis origination pool

| Script | When | Transactions (all from `ADMIN_ADDRESS_0`) |
| --- | --- | --- |
| `GenesisPoolLaunch.s.sol` | Launch day, just after 12:00 UTC | `removeConfig(daily)` → `addConfig(genesis)` → `deployOriginationPool(genesisId)` → `removeConfig(genesis)` |
| `GenesisPoolReopenDaily.s.sol` | Day 21, once the genesis pool enters DEPLOY | `addConfig(daily)` |

Inputs:

- `ADMIN_ADDRESS_0`: the signer. Must hold `DEFAULT_ADMIN_ROLE` on the scheduler.
- `INITIAL_ORIGINATION_POOL_0_*`: the daily config, exactly as DeployAll added it. The launch
  script refuses to run unless the scheduler holds exactly one config and its id matches.
- `GENESIS_ORIGINATION_POOL_{NAME_PREFIX,SYMBOL_PREFIX,DEPOSIT_PHASE_DURATION,DEPLOY_PHASE_DURATION,DEFAULT_POOL_LIMIT,POOL_LIMIT_GROWTH_RATE_BPS,POOL_MULTIPLIER_BPS}`:
  optional; default to `Genesis Origination Pool`, `GEN-OP`, 21 days, 14 days, `1_000_000_000e18`, 0, 0.
- `GENESIS_MAX_EPOCH_ELAPSED`: optional, default `3600`. The launch reverts when more seconds than
  this have passed since the last 12:00 UTC boundary.

The launch script checks after the run that the pool landed at the predicted address, is registered,
is in DEPOSIT, has the expected phase timestamps and limit, that the GeneralManager holds
`DEPLOY_ROLE` on it, and that `configLength() == 0`. Removing the genesis config does not
deregister the pool, so the GeneralManager and RolloverVault keep accepting it, while no second
genesis pool can be deployed.

### Why broadcast right after a 12:00 UTC boundary

The scheduler anchors phase timestamps to the start of the current epoch (epochs start at 12:00 UTC),
not to the block time: `deployPhaseTimestamp = epochStart + depositPhaseDuration`. Every minute
between the boundary and the broadcast is a minute cut from the 21-day deposit phase, and a
broadcast at 11:59 UTC gets a deposit phase of 20 days and 1 minute. Broadcasting just after the
boundary also keeps the simulation and the mined transactions in the same epoch, so the pool lands
at the simulated address with the simulated timestamps. The script's output says whether the
day's daily pool was already deployed this epoch; if it was, that pool runs its normal 1-day
deposit phase alongside the genesis pool.

### Dry run on an anvil fork

From `packages/contracts`, in one terminal:

```bash
anvil --fork-url https://rpc.mainnet.chain.robinhood.com --port 8547
```

In another, move the fork just past the next 12:00 UTC boundary and impersonate the admin:

```bash
FORK=http://127.0.0.1:8547
ADMIN=$(cast call 0xF33359eeA22DB1Ba2943732C4933917025B6c92f "oPoolAdmin()(address)" --rpc-url $FORK)
NOW=$(cast block latest -f timestamp --rpc-url $FORK)
NEXT=$(( NOW - (NOW - 43200) % 86400 + 86400 ))
cast rpc evm_setNextBlockTimestamp $((NEXT + 120)) --rpc-url $FORK && cast rpc evm_mine --rpc-url $FORK
cast rpc anvil_impersonateAccount $ADMIN --rpc-url $FORK
cast rpc anvil_setBalance $ADMIN 0x56BC75E2D63100000 --rpc-url $FORK

# simulation only
forge script script/ops/GenesisPoolLaunch.s.sol --rpc-url $FORK
# execute on the fork
forge script script/ops/GenesisPoolLaunch.s.sol --rpc-url $FORK --broadcast --unlocked --sender $ADMIN --slow

# day 21 on the fork
DEPLOY_TS=$(cast call <genesis pool> "deployPhaseTimestamp()(uint256)" --rpc-url $FORK | awk '{print $1}')
cast rpc evm_setNextBlockTimestamp $((DEPLOY_TS + 120)) --rpc-url $FORK && cast rpc evm_mine --rpc-url $FORK
forge script script/ops/GenesisPoolReopenDaily.s.sol --rpc-url $FORK --broadcast --unlocked --sender $ADMIN --slow
```

Executing against the fork writes `broadcast/<script>/4663/run-*.json`, which looks like a mainnet
record. Delete those files afterwards (`rm -rf broadcast/GenesisPool*.s.sol cache/GenesisPool*.s.sol`).

To simulate against the live chain without sending anything (no `--broadcast`), outside the
launch window:

```bash
GENESIS_MAX_EPOCH_ELAPSED=86400 forge script script/ops/GenesisPoolLaunch.s.sol --rpc-url robinhood
```

### Broadcast

Within the first minutes after 12:00 UTC, with the admin's wallet flags (for example
`--ledger --mnemonic-indexes N`, or `--account <keystore>`):

```bash
forge script script/ops/GenesisPoolLaunch.s.sol --rpc-url robinhood --sender <ADMIN_ADDRESS_0> --slow --broadcast <wallet flags>
```

Use `--slow` so each transaction is mined before the next is sent. The genesis config is live on the
scheduler between the second and fourth transactions, so the roller can see it for those blocks. If
`deployOriginationPool` reverts because someone deployed the pool first, the pool still exists at
the predicted address; send the final `removeConfig(genesis)` on its own and confirm
`configLength() == 0`.

Day 21, at or after the pool's `deployPhaseTimestamp`:

```bash
forge script script/ops/GenesisPoolReopenDaily.s.sol --rpc-url robinhood --sender <ADMIN_ADDRESS_0> --slow --broadcast <wallet flags>
```

The reopened daily config has the same id as before, but `removeConfig` deleted its deployment
record, so the first daily pool after reopening is sized at `defaultPoolLimit` and the
`poolLimitGrowthRateBps` history starts over.

### Record after broadcast

From the script output and `broadcast/GenesisPoolLaunch.s.sol/4663/run-latest.json`:

- genesis pool address (predicted and deployed must match), name and symbol (`GEN-OP-<epoch>`)
- scheduler epoch, and the block number and hash of each of the four transactions
- `depositPhaseTimestamp`, `deployPhaseTimestamp`, `redemptionPhaseTimestamp`
- confirmation reads: `isRegistered(pool) == true`, `configLength() == 0`, `currentPhase() == 0`

Commit the `broadcast/GenesisPoolLaunch.s.sol/4663/` record the same way as other mainnet runs.
