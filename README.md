
# Smilee Finance contest details

- Join [Sherlock Discord](https://discord.gg/MABEWyASkp)
- Submit findings using the issue page in your private contest repo (label issues as med or high)
- [Read for more details](https://docs.sherlock.xyz/audits/watsons)

# Q&A

### Q: On what chains are the smart contracts going to be deployed?
Now: Arbitrum
In future: Berachain and additional Ethereum L2s
___

### Q: Which ERC20 tokens do you expect will interact with the smart contracts? 
Smilee can work with any ERC20 tokens.
Smilee architecture is designed around vaults which collect liquidity used to mint and burn Decentralized Volatility Products (DVPs).
Each Smilee vault has two reference tokens: a base token and a side token.
The base token is used as input/ output for any user' actions (i.e., vault deposits & withdraws, DVP positions buy & sell). For instance, a vault that has USDC as base token, requires deposits to be in USDC, executes withdraw in USDC and computes premia to buy/sell DVP positions in USDC. 
The side token is the other token of the vault. Smilee vaults replicate a DEX pool with the base token and the side token as pair. For instance a Smilee vault can have USDC as base token and wBTC as side token. 
The side token is not provided by users, the vault obtains it in the correct amount by swapping on an underlying DEX. 
Initially Smilee will have as:
- Base token: USDC
- Side tokens: ETH, wBTC, ARB, GMX, JOE
- Underlying DEX: Uniswap V3
In future:
- Base tokens: other stable coins will be considered
- Side tokens: other side tokens will be added
- Underlying DEX: other DEXs will be added
Current limitations:
- Base tokens: Smilee can work with base tokens that are not stable coins, but such functionality has not been fully tested yet
- DEX liquidity: Smilee can work only with tokens that have DEX pools liquid enough to allow the protocol to swap
- Tokens prices: Smilee may have some rounding issues if using side tokens whose price in base tokens is a number lower than 10^-4
___

### Q: Which ERC721 tokens do you expect will interact with the smart contracts? 
Smilee does not interact with external ERC721.
Smilee uses its own ERC721 in:
- DVP positions are ERC721
- NFTs to grant priority access to vaults and DVPs (for whitelisted launch) are ERC721
___

### Q: Do you plan to support ERC1155?
No
___

### Q: Which ERC777 tokens do you expect will interact with the smart contracts? 
None
___

### Q: Are there any FEE-ON-TRANSFER tokens interacting with the smart contracts?

Smilee has not been designed to work with FOT tokens and its functioning has neither been tested nor guaranteed.
We are aware some established tokens have the option to become a FOT. Should any switch to be a FOT, we will manage the change, at worst pausing and killing such vaults


___

### Q: Are there any REBASING tokens interacting with the smart contracts?

Smilee has not been designed to work with rebasing tokens and its functioning has neither been tested nor guaranteed
___

### Q: Are the admins of the protocols your contracts integrate with (if any) TRUSTED or RESTRICTED?
TRUSTED
In details, Smilee has been designed to function directly using DEX prices, which are obtained by directly swapping on the DEX.
To avoid to incur in excessive slippage or market manipulation, DEX prices are checked against a Price Oracle. 
Anytime DEX prices and Oracle prices deviate more than an accepted threshold, swaps revert ensuring no risk of loss to the users or the protocol. 
Therefore the TRUST in each is minimized by checking once against the other. 
Smilee uses Chainlink as Price Oracle and Uniswap v3 as DEX. Other Oracles and DEXs will be added in future.
___

### Q: Is the admin/owner of the protocol/contracts TRUSTED or RESTRICTED?
TRUSTED
Smilee is a brand new protocol that enables previously impossible strategies in DeFi. Given its complexity and experimental nature, it has been struck a balance between decentralization and the possibility to counteract unforeseen issues.

This translates into having some financial parameters and peripheral smart contracts that can be updated. 
At the same time, to ensure adequate decentralization and users' protection, Smilee has put in place:
- Strong Role-based Access Control (RBAC) rules.
- Strict time lock and cap / floor values.

Furthermore, Smilee will follow a gradual decentralization roadmap based on three stages:
- Stage 1, protocol launch & initial growth: RBAC roles are managed by the core team.
- Stage 2, protocol scaling: RBAC roles are assigned to the DAO.
- Stage 3, protocol maturity: the DAO can renounce to all or some RBAC roles, effectively making the smart contracts immutable.
___

### Q: Are there any additional protocol roles? If yes, please explain in detail:
Detailed explenation here: https://dvrs.notion.site/RBAC-setters-time-locks-vualt-DVP-function-limitations-86e57ab687fa442db0273eba88ebd887?pvs=4
___

### Q: Is the code/contract expected to comply with any EIPs? Are there specific assumptions around adhering to those EIPs that Watsons should be aware of?
Vaults are a modified version of ERC4626 to implement queue deposits and withdraws (within epoch lifecycle).
Position manager is an ERC721.
DVPs do not complie with any standard but DVP positions are wrapped with the Position manager
___

### Q: Please list any known issues/acceptable risks that should not result in a valid finding.
CENTRALIZATION ISSUES: centralization issues generated by the control over the protocol by the admin and mitigated by the RBAC model with time lock, cap and floors have to be considered already known. As example you may look at the issues pointed out in the audit report.

INTEGRATION ISSUES: integration issues with external componets (DEX, Price Oracle, Deribit for Implied Volatility Data), some of which also pointed out in the previous audit, have to be considered already known.

FINANCIAL ISSUES: financial issue reported in here (https://docs.google.com/spreadsheets/d/1Ff7oeqtM8CjKmcV9OP8Q7HcFsGFgBPTYST8MfGfRzIs/edit?usp=sharing) are known and mitigated. However new / still effective ways to exploit such issues are valid for the contest.

TOKENS: all the issues related to interactions with tokens upgreadable and pausable are known

DEX SWAP: issues related to impacts of fees and slippage are known and mitigated

ORACLE & DEX MANIPULATION: issues related to manipulation of oracle prices and / or DEX prices are known. However sophisticated and particularly effective exploits are considered valid (aka simply saying DEX manipulation may impact is not enough, we expect you to provide super effective attack to the protocol)
___

### Q: Please provide links to previous audits (if any).
https://dvrs.notion.site/Audit-by-Trust-Security-a1ee3c292870404a85037ab94c86eba6?pvs=74
___

### Q: Are there any off-chain mechanisms or off-chain procedures for the protocol (keeper bots, input validation expectations, etc)?
Smilee uses an off-chain scheduler to roll epochs. 
Only the scheduler has the “permission” to execute such action. 
The scheduler address can be changed by the admin.
In any case, smart contracts enforce that an epoch can be rolled only after its epoch end timestamp has been reached. 

In addition, Smilee can function using Implied Volatility data taken from Deribit (for more details see Smilee docs - Oracles & Risk).
The scheduler is responsible for calling Deribit API and update oracle data.
In any case, Smilee already implements on-chain mechanism to price volatility and can be moved to use on-chain data only.

The scheduler is implemented to ensure resiliency and retrial of any failed jobs.
___

### Q: In case of external protocol integrations, are the risks of external contracts pausing or executing an emergency withdrawal acceptable? If not, Watsons will submit issues related to these situations that can harm your protocol's functionality.
Smilee is integrated to DEX (Uniswap v3, other in future) and Oracle Prices (Chainlink, other potentially in future).
DEX pause is accepted.
DEX withdraw shall not impact Smilee. DEXs are only used to swap and if liquidity becomes to little (therefore translating into too high price impact from swaps) transactions revert due to a max deviation check against Price Oracle.
Price Oracle pause is accepted.
Price Oracle data are checked against stale feed and deviation from DEX prices (as above, in case of deviation, transactions revert to protect users)
___

### Q: Do you expect to use any of the following tokens with non-standard behaviour with the smart contracts?
Pausable tokens, upgradable tokens, low decimals (as low as 6 decimals).
Should any token pause or upgrade, the team will manage the change.
___

### Q: Add links to relevant protocol resources
Smilee docs: https://docs.smilee.finance/
Additional technical docs: https://dvrs.notion.site/Additional-docs-for-audit-0d5bba5b11c64c56b5c241b067d89434?pvs=4
Financial engineering docs: https://dvrs.notion.site/Smilee-v1-69-Financial-Engineering-docs-da543e863837404daca089ec0ad47d9f?pvs=4

___



# Audit scope


[smilee-v2-contracts @ 441a3cbdc8b926e7625a4ea82d6bdf7add1ee9f6](https://github.com/dverso/smilee-v2-contracts/tree/441a3cbdc8b926e7625a4ea82d6bdf7add1ee9f6)
- [smilee-v2-contracts/src/AddressProvider.sol](smilee-v2-contracts/src/AddressProvider.sol)
- [smilee-v2-contracts/src/DVP.sol](smilee-v2-contracts/src/DVP.sol)
- [smilee-v2-contracts/src/EpochControls.sol](smilee-v2-contracts/src/EpochControls.sol)
- [smilee-v2-contracts/src/FeeManager.sol](smilee-v2-contracts/src/FeeManager.sol)
- [smilee-v2-contracts/src/IG.sol](smilee-v2-contracts/src/IG.sol)
- [smilee-v2-contracts/src/MarketOracle.sol](smilee-v2-contracts/src/MarketOracle.sol)
- [smilee-v2-contracts/src/Vault.sol](smilee-v2-contracts/src/Vault.sol)
- [smilee-v2-contracts/src/interfaces/IPositionManager.sol](smilee-v2-contracts/src/interfaces/IPositionManager.sol)
- [smilee-v2-contracts/src/lib/Amount.sol](smilee-v2-contracts/src/lib/Amount.sol)
- [smilee-v2-contracts/src/lib/AmountsMath.sol](smilee-v2-contracts/src/lib/AmountsMath.sol)
- [smilee-v2-contracts/src/lib/EpochController.sol](smilee-v2-contracts/src/lib/EpochController.sol)
- [smilee-v2-contracts/src/lib/EpochFrequency.sol](smilee-v2-contracts/src/lib/EpochFrequency.sol)
- [smilee-v2-contracts/src/lib/Finance.sol](smilee-v2-contracts/src/lib/Finance.sol)
- [smilee-v2-contracts/src/lib/FinanceIG.sol](smilee-v2-contracts/src/lib/FinanceIG.sol)
- [smilee-v2-contracts/src/lib/FinanceIGDelta.sol](smilee-v2-contracts/src/lib/FinanceIGDelta.sol)
- [smilee-v2-contracts/src/lib/FinanceIGPayoff.sol](smilee-v2-contracts/src/lib/FinanceIGPayoff.sol)
- [smilee-v2-contracts/src/lib/FinanceIGPrice.sol](smilee-v2-contracts/src/lib/FinanceIGPrice.sol)
- [smilee-v2-contracts/src/lib/Notional.sol](smilee-v2-contracts/src/lib/Notional.sol)
- [smilee-v2-contracts/src/lib/Position.sol](smilee-v2-contracts/src/lib/Position.sol)
- [smilee-v2-contracts/src/lib/SignedMath.sol](smilee-v2-contracts/src/lib/SignedMath.sol)
- [smilee-v2-contracts/src/lib/TimeLock.sol](smilee-v2-contracts/src/lib/TimeLock.sol)
- [smilee-v2-contracts/src/lib/TokensPair.sol](smilee-v2-contracts/src/lib/TokensPair.sol)
- [smilee-v2-contracts/src/lib/VaultLib.sol](smilee-v2-contracts/src/lib/VaultLib.sol)
- [smilee-v2-contracts/src/lib/WadTime.sol](smilee-v2-contracts/src/lib/WadTime.sol)
- [smilee-v2-contracts/src/periphery/PositionManager.sol](smilee-v2-contracts/src/periphery/PositionManager.sol)
- [smilee-v2-contracts/src/providers/SwapAdapterRouter.sol](smilee-v2-contracts/src/providers/SwapAdapterRouter.sol)
- [smilee-v2-contracts/src/providers/chainlink/ChainlinkPriceOracle.sol](smilee-v2-contracts/src/providers/chainlink/ChainlinkPriceOracle.sol)
- [smilee-v2-contracts/src/providers/uniswap/UniswapAdapter.sol](smilee-v2-contracts/src/providers/uniswap/UniswapAdapter.sol)

