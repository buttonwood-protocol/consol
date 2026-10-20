# Ops scripts

One-off admin operations against a live deployment. Each script reads the chain's address book
(`addresses/addresses-<chainId>.json`) and the environment. Forge loads `.env` from the project
root (`packages/contracts/.env`), not from this directory. The scripts never read a private key:
the signer comes from the wallet flags on the command line.

## Genesis origination pool

| Script | When | Transactions (all from `ADMIN_ADDRESS_0`) |
| --- | --- | --- |
| `GenesisPoolLaunch.s.sol` | Launch day, just after 12:00 UTC | `removeConfig(daily)` → `addConfig(genesis)` → `deployOriginationPool(genesisId)` → `removeConfig(genesis)`, or only the steps still missing |
| `GenesisPoolVerify.s.sol` | Right after each launch or reopen broadcast | none (read-only) |
| `GenesisPoolReopenDaily.s.sol` | Day 7, once the genesis pool has left DEPOSIT | `addConfig(daily)` |

Inputs:

- `ADMIN_ADDRESS_0`: the signer. Must hold `DEFAULT_ADMIN_ROLE` on the scheduler.
- `INITIAL_ORIGINATION_POOL_0_*`: the daily config, exactly as DeployAll added it.
- `GENESIS_ORIGINATION_POOL_{NAME_PREFIX,SYMBOL_PREFIX,DEPOSIT_PHASE_DURATION,DEPLOY_PHASE_DURATION,DEFAULT_POOL_LIMIT,POOL_LIMIT_GROWTH_RATE_BPS,POOL_MULTIPLIER_BPS}`:
  optional; default to `Genesis Origination Pool`, `GEN-OP`, 7 days, 7 days, `1_000_000_000e18`, 0, 0.
  A set value that does not parse reverts (no silent fallback to the default). Bounds: deposit
  phase 7–35 days, deploy phase 1–30 days, pool limit `1_000_000e18`–`1e30`, both bps at most
  `10_000`; a value outside them reverts with the variable's name.
- `GENESIS_MAX_EPOCH_ELAPSED`: optional, default `3600`. A launch run that still has to deploy
  reverts when more seconds than this have passed since the last 12:00 UTC boundary. With
  `--broadcast`, a value above `3600` is refused; it can only widen simulations.
- `GENESIS_POOL_ADDRESS`: the deployed genesis pool. Leave it unset (or set to the predicted,
  not yet deployed, address) for the launch. Set it as soon as the launch is verified: the reopen
  and verify scripts require it, and the launch refuses to run again once it points at a
  registered pool ("genesis already launched"). The roller reads the same variable in genesis mode.
- `GENESIS_EXPECTED_DAILY_CONFIG_ID`: required by the reopen. The launch logs it
  (`GENESIS_EXPECTED_DAILY_CONFIG_ID=0x…`); record it in the launch notes and in `.env`.

With the defaults, counted from the launch epoch's 12:00 UTC boundary: deposits close at day 7
(`deployPhaseTimestamp`), the deploy phase runs from day 7 to day 14, and from day 14
(`redemptionPhaseTimestamp = deployPhaseTimestamp + deployPhaseDuration`) depositors can
`redeem` their receipt tokens for their share of the USDX left undeployed and of the Consol the
pool received.

### What the launch does

The launch reads the scheduler and continues from wherever it is, sending only the missing steps:

| Scheduler state | Sends |
| --- | --- |
| `{daily}` | all four transactions |
| `{}`, no genesis pool this epoch | `addConfig(genesis)`, `deployOriginationPool`, `removeConfig(genesis)` |
| `{genesis}`, pool not deployed | `deployOriginationPool`, `removeConfig(genesis)` |
| `{genesis}`, pool not deployed, more than an hour past 12:00 UTC | `removeConfig(genesis)` only, leaving `{}` for the next boundary |
| `{genesis}`, pool already deployed (front-run) | `removeConfig(genesis)` |
| `{}`, genesis pool deployed this epoch | nothing; logs "Nothing to do" |

Anything else (two configs, an unknown config, a genesis config whose pool is from an earlier
epoch, the daily config next to a genesis pool already deployed this epoch) reverts before
broadcasting. When the predicted pool address already has code, the deploy is skipped instead of
colliding. The elapsed-time guard applies only to runs that still deploy; a run that only has to
remove the genesis config works at any time.

The checks the launch prints after its transactions run against forge's local simulation, not
against the mined chain, and its console output is not a record. `GenesisPoolVerify` is the
check against the chain.

### Why broadcast right after a 12:00 UTC boundary

The scheduler anchors phase timestamps to the start of the current epoch (epochs start at 12:00 UTC),
not to the block time: `deployPhaseTimestamp = epochStart + depositPhaseDuration`. Every minute
between the boundary and the broadcast is a minute cut from the 7-day deposit phase, and a
broadcast at 11:59 UTC gets a deposit phase of 6 days and 1 minute. Broadcasting just after the
boundary also keeps the simulation and the mined transactions in the same epoch, so the pool lands
at the simulated address with the simulated timestamps. The script's output says whether the
day's daily pool was already deployed this epoch; if it was, that pool runs its normal 1-day
deposit phase alongside the genesis pool.

### Before the launch window

- The roller deploys the current-epoch pool of every config it sees, so it would race the
  launch for `deployOriginationPool(genesis)`. During the launch window it must be **stopped**,
  or **already in genesis mode with `GENESIS_POOL_ADDRESS` set** to the predicted pool (the
  launch simulation prints `Genesis pool (predicted)`).
- Run the simulation (below) and note the predicted pool and the logged
  `GENESIS_EXPECTED_DAILY_CONFIG_ID`.

### Dry run on an anvil fork

From `packages/contracts`, in one terminal:

```bash
anvil --fork-url https://rpc.mainnet.chain.robinhood.com --port 8547
```

In another, move the fork just past the next 12:00 UTC boundary and impersonate `ADMIN_ADDRESS_0`
(the address the script broadcasts from, not `oPoolAdmin()`):

```bash
FORK=http://127.0.0.1:8547
ADMIN=$ADMIN_ADDRESS_0
NOW=$(cast block latest -f timestamp --rpc-url $FORK)
NEXT=$(( NOW - (NOW - 43200) % 86400 + 86400 ))
cast rpc evm_setNextBlockTimestamp $((NEXT + 120)) --rpc-url $FORK && cast rpc evm_mine --rpc-url $FORK
cast rpc anvil_impersonateAccount $ADMIN --rpc-url $FORK
cast rpc anvil_setBalance $ADMIN 0x56BC75E2D63100000 --rpc-url $FORK

# simulation only
forge script script/ops/GenesisPoolLaunch.s.sol --rpc-url $FORK
# execute on the fork, then verify
forge script script/ops/GenesisPoolLaunch.s.sol --rpc-url $FORK --broadcast --unlocked --sender $ADMIN
GENESIS_POOL_ADDRESS=<genesis pool> forge script script/ops/GenesisPoolVerify.s.sol --rpc-url $FORK

# day 7 on the fork
DEPLOY_TS=$(cast call <genesis pool> "deployPhaseTimestamp()(uint256)" --rpc-url $FORK | awk '{print $1}')
cast rpc evm_setNextBlockTimestamp $((DEPLOY_TS + 120)) --rpc-url $FORK && cast rpc evm_mine --rpc-url $FORK
GENESIS_POOL_ADDRESS=<genesis pool> GENESIS_EXPECTED_DAILY_CONFIG_ID=<id from the launch log> \
  forge script script/ops/GenesisPoolReopenDaily.s.sol --rpc-url $FORK --broadcast --unlocked --sender $ADMIN
GENESIS_POOL_ADDRESS=<genesis pool> forge script script/ops/GenesisPoolVerify.s.sol --rpc-url $FORK
```

Executing against the fork writes `broadcast/GenesisPool*.s.sol/4663/` files that look exactly
like mainnet records, because the fork keeps chain id 4663. Delete them before doing anything
else, and never commit them:

```bash
rm -rf broadcast/GenesisPool*.s.sol cache/GenesisPool*.s.sol
```

To simulate against the live chain without sending anything (no `--broadcast`), outside the
launch window:

```bash
GENESIS_MAX_EPOCH_ELAPSED=86400 forge script script/ops/GenesisPoolLaunch.s.sol --rpc-url robinhood
```

Never put `GENESIS_MAX_EPOCH_ELAPSED` in `.env`; a broadcast refuses values above `3600` anyway.

### Broadcast

Within the first minutes after 12:00 UTC, with the admin's wallet flags (for example
`--ledger --mnemonic-indexes N`, or `--account <keystore>`):

```bash
forge script script/ops/GenesisPoolLaunch.s.sol --rpc-url robinhood --sender <ADMIN_ADDRESS_0> --broadcast <wallet flags>
```

Broadcast without `--slow`. On 4663 the sequencer is first-come-first-served with sub-second
blocks, so all transactions are sent back to back, and if someone deploys the pool first the
deploy reverts while the final `removeConfig(genesis)` still lands. With `--slow`, forge stops at
the first reverted receipt and the final transaction is never sent. Either way, a re-run of the
launch finishes whatever is left.

**Never use `forge script --resume`.** It replays the recorded transactions without running the
script: the epoch guard and every check are skipped, a resume in a later epoch deploys a
different pool than the one logged, and after a front-run it fails on the nonce without sending
`removeConfig(genesis)`.

Then, immediately, against the live RPC:

```bash
GENESIS_POOL_ADDRESS=<genesis pool> forge script script/ops/GenesisPoolVerify.s.sol --rpc-url robinhood
```

It reads the chain and checks that the pool is registered and in DEPOSIT, that its timestamps
match `depositPhaseDuration`/`deployPhaseDuration` from a 12:00 UTC boundary, the pool limit,
`configLength() == 0`, and that the GeneralManager holds `DEPLOY_ROLE`. It logs the pool's
admin (`oPoolAdmin()`), whether the scheduler's GeneralManager matches the address book, and how
many seconds after the boundary the pool was deployed. Take the pool address from the
`OriginationPoolDeployed` event in the deploy receipt (or `cast call <scheduler>
"predictOriginationPool(bytes32)(address)"` while the genesis config is still present).

### Recovery

If the launch stops partway (Ledger rejection, RPC error, a reverted deploy), **re-run the launch
command**. It resumes from the on-chain state, then run the verify script. A run that still has to
deploy must happen within the first hour after 12:00 UTC. Past that, a re-run from `{genesis}`
only removes the genesis config, and a re-run from `{}` reverts; either way no pools are deployed
until the next boundary, when the same command resumes from `{}`.

The one state that must not survive the next 12:00 UTC boundary is `{genesis}`: the roller, or
anyone, would deploy another genesis pool in the next epoch. If the script cannot be run, the
fallback is to send the final step by hand (values are the defaults; use the overrides if set),
then confirm `configLength() == 0`:

```bash
cast send 0xF33359eeA22DB1Ba2943732C4933917025B6c92f \
  "removeConfig((string,string,address,address,uint32,uint32,uint256,uint16,uint16))" \
  '("Genesis Origination Pool","GEN-OP",<consol>,<usdx>,604800,604800,1000000000000000000000000000,0,0)' \
  --rpc-url robinhood <wallet flags>
cast call 0xF33359eeA22DB1Ba2943732C4933917025B6c92f "configLength()(uint256)" --rpc-url robinhood
```

### Reopen (day 7)

At or after the pool's `deployPhaseTimestamp`, with `GENESIS_POOL_ADDRESS` and
`GENESIS_EXPECTED_DAILY_CONFIG_ID` set:

```bash
forge script script/ops/GenesisPoolReopenDaily.s.sol --rpc-url robinhood --sender <ADMIN_ADDRESS_0> --broadcast <wallet flags>
GENESIS_POOL_ADDRESS=<genesis pool> forge script script/ops/GenesisPoolVerify.s.sol --rpc-url robinhood
```

The reopen refuses unless the scheduler holds no configs, the genesis pool is registered and
past DEPOSIT, and the daily config rebuilt from `INITIAL_ORIGINATION_POOL_0_*` has the recorded
id. After the reopen, verify expects `configLength() == 1` with the daily config and the pool past
DEPOSIT. The reopened daily config has the same id as before, but `removeConfig` deleted its
deployment record, so the first daily pool after reopening is sized at `defaultPoolLimit` and the
`poolLimitGrowthRateBps` history starts over.

### Record after broadcast

Record from `cast call` against the chain or from the verify script's output, never from the
launch script's console output (that is simulation and has printed a wrong address when
transactions landed differently):

- genesis pool address, name and symbol (`GEN-OP-<epoch>`), and the scheduler epoch
- the block number and hash of each transaction (`broadcast/GenesisPoolLaunch.s.sol/4663/run-latest.json`)
- `depositPhaseTimestamp`, `deployPhaseTimestamp`, `redemptionPhaseTimestamp` (`cast call <pool> "<name>()(uint256)"`)
- `isRegistered(pool) == true`, `configLength() == 0`, `currentPhase() == 0`
- `GENESIS_EXPECTED_DAILY_CONFIG_ID`

Commit the `broadcast/GenesisPoolLaunch.s.sol/4663/` record of the mainnet run the same way as
other mainnet runs.

## Borrow caps

`SetBorrowCaps.s.sol` sets `GeneralManager.maximumCap` (and, when asked, `minimumCap`) for every
collateral in the address book, from `ADMIN_ADDRESS_0`, in one broadcast: one `setMaximumCap`
transaction per collateral (plus one `setMinimumCap` each when `BORROW_MIN_CAP` is set).

Inputs:

- `ADMIN_ADDRESS_0`: the signer. Must hold `DEFAULT_ADMIN_ROLE` on the GeneralManager.
- `BORROW_MAX_CAP`: required, no default. USDX wei (18 decimals); `10000e18` is accepted.
  Must be within `100e18`–`1_000_000e18`, otherwise it reverts naming the variable.
- `BORROW_MIN_CAP`: optional. When set it is applied too and must be below `BORROW_MAX_CAP`.
  When unset the on-chain minimums stay as they are, and the run reverts if any of them is not
  below `BORROW_MAX_CAP`.
- `COLLATERAL_FILTER`: optional, comma-separated collateral addresses. Restricts the run to those
  collaterals; each must be in the address book's `collateralAddresses`.

Pass the caps on the command line; do not put them in `.env`.

Before broadcasting, the script checks the admin role, that the address book lists at least one
collateral, and that each collateral has a price oracle on the GeneralManager. It skips any cap
already at its target (logged as `unchanged`), so a re-run after a partial broadcast sends only
what is missing, and a run with nothing to change sends nothing. After the broadcast it reads every
cap back and logs symbol, address and old → new value per collateral. Those reads run against
forge's local simulation; `verify()` reads the chain.

### 4663: raise the maximum cap from 500 to 10,000 USDX

GeneralManager `0xc127d8aBcbB08f7A5C0442AE5A24883027bd910C`, twelve collaterals. From
`packages/contracts`:

```bash
# simulation only: prints the twelve changes, sends nothing
BORROW_MAX_CAP=10000e18 forge script script/ops/SetBorrowCaps.s.sol --rpc-url robinhood

# broadcast, with one of the wallet flags below
BORROW_MAX_CAP=10000e18 forge script script/ops/SetBorrowCaps.s.sol --rpc-url robinhood \
  --sender <ADMIN_ADDRESS_0> --broadcast --slow <wallet flags>

# verify against the chain
BORROW_MAX_CAP=10000e18 forge script script/ops/SetBorrowCaps.s.sol --sig 'verify()' --rpc-url robinhood
```

Wallet flags:

| Flag | Signing |
| --- | --- |
| `--account <keystore>` | one password prompt, then every transaction is signed |
| `--private-key $ADMIN_KEY` | no prompt; keep the key out of shell history and `.env` |
| `--ledger --mnemonic-indexes N` | one confirmation on the device per transaction (twelve here) |

`--slow` sends each transaction after the previous one is mined, so a failure stops the run
cleanly. If the broadcast stops partway, re-run the same command: it sends only the caps still
missing. Never use `forge script --resume`; it replays the recorded transactions without the checks.

`verify()` reverts unless every selected collateral is at `BORROW_MAX_CAP` (and `BORROW_MIN_CAP`
when set), and logs each collateral's maximum and minimum. Spot-check one by hand with:

```bash
cast call 0xc127d8aBcbB08f7A5C0442AE5A24883027bd910C "maximumCap(address)(uint256)" <collateral> --rpc-url robinhood
```

Commit the `broadcast/SetBorrowCaps.s.sol/4663/` record of the mainnet run the same way as other
mainnet runs.
