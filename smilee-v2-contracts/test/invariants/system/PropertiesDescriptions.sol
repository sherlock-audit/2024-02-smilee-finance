// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

abstract contract PropertiesDescriptions {
    struct InvariantInfo {
        string code;
        string desc;
    }

    // INVARIANTS
    InvariantInfo internal _IG_03_1     =   InvariantInfo("IG_03_1",    "IG_03_1: Given a certain oracle price and time, for both buy & sell, IG premium expected <= IG premium computed using the max level of IV given by the bonding curve");
    InvariantInfo internal _IG_03_2     =   InvariantInfo("IG_03_2",    "IG_03_2: Given a certain price and time, for both buy & sell, IG premium expected >= IG premium computed using the min level of IV given by the bonding curve ");
    InvariantInfo internal _IG_03_3     =   InvariantInfo("IG_03_3",    "IG_03_3: For any buy, IG premium paid >= IG premium expected");
    InvariantInfo internal _IG_03_4     =   InvariantInfo("IG_03_4",    "IG_03_4: For any sell, IG payoff earned <= IG payoff expected");
    InvariantInfo internal _IG_04       =   InvariantInfo("IG_04",      "IG_04: User cannot buy IG, sell it for a profit if neither: utilisation grows or price moves up for bull, down for bear, or both for smile");
    InvariantInfo internal _IG_05_1     =   InvariantInfo("IG_05_1",    "IG_05_1: A IG bull premium is always <= than that of a call with the same strike and notional");
    InvariantInfo internal _IG_05_2     =   InvariantInfo("IG_05_2",    "IG_05_2: A IG bull premium is always >= than that of a call with the strike in kb and same notional");
    InvariantInfo internal _IG_06       =   InvariantInfo("IG_06",      "IG_06: IG Bear payoff / premium is superiorly limited by V, the user notional. So it is the premium -> premium < V && payoff < V");
    InvariantInfo internal _IG_07_1     =   InvariantInfo("IG_07_1",    "IG_07_1: A IG bear premium is always <= than that of a put with the same strike and notional");
    InvariantInfo internal _IG_07_2     =   InvariantInfo("IG_07_2",    "IG_07_2: A IG bear premium is always >= than that of a put with the strike in kb and same notional");
    InvariantInfo internal _IG_08_1     =   InvariantInfo("IG_08_1",    "IG_08_1: A IG Smile premium is always <= than that of a straddle with the same strike and notional");
    InvariantInfo internal _IG_08_2     =   InvariantInfo("IG_08_2",    "IG_08_2: A IG Smile premium is always >= than that of a strangle with the strike in ka and kb and notional");
    InvariantInfo internal _IG_09       =   InvariantInfo("IG_09",      "IG_09: The option seller never gains more than the payoff");
    InvariantInfo internal _IG_10       =   InvariantInfo("IG_10",      "IG_10: The option buyer never loses more than the premium");
    InvariantInfo internal _IG_11       =   InvariantInfo("IG_11",      "IG_11: Payoff never exeed accepted slippage");
    InvariantInfo internal _IG_12       =   InvariantInfo("IG_12",      "IG_12: A IG bull payoff is always positive above the strike price & zero at or below the strike price");
    InvariantInfo internal _IG_13       =   InvariantInfo("IG_13",      "IG_13: A IG bear payoff is always positive under the strike price & zero at or above the strike price");
    InvariantInfo internal _IG_14       =   InvariantInfo("IG_14",      "IG_14: For each buy / sell, IG premium >= IG payoff for a given price; Both calculated with price oracle");
    InvariantInfo internal _IG_15       =   InvariantInfo("IG_15",      "IG_15: Notional (aka V0) does not change during epoch");
    InvariantInfo internal _IG_16       =   InvariantInfo("IG_16",      "IG_16: Strike does not change during epoch");
    InvariantInfo internal _IG_17       =   InvariantInfo("IG_17",      "IG_17: IG finance params does not change during epoch");
    InvariantInfo internal _IG_18       =   InvariantInfo("IG_18",      "IG_18: IG minted never > than Notional (aka V0)");
    InvariantInfo internal _IG_20       =   InvariantInfo("IG_20",      "IG_20: IG price always >= 0 + MIN fee");
    InvariantInfo internal _IG_21       =   InvariantInfo("IG_21",      "IG_21: Fee always >= MIN fee");
    InvariantInfo internal _IG_22       =   InvariantInfo("IG_22",      "IG_22: IG bull delta is always positive -> control that limsup > 0 after every rollEpoch");
    InvariantInfo internal _IG_23       =   InvariantInfo("IG_23",      "IG_23: IG bear delta is always negative -> control that liminf < 0 after every rollEpoch");
    InvariantInfo internal _IG_24_1     =   InvariantInfo("IG_24_1",    "IG_24_1: If price goes up, IG bull premium goes up, IG bear premium goes down, and viceversa");
    InvariantInfo internal _IG_24_2     =   InvariantInfo("IG_24_2",    "IG_24_2: If IV goes up, all premium goes up, if IV goes down,  all premium goes down");
    InvariantInfo internal _IG_24_3     =   InvariantInfo("IG_24_3",    "IG_24_3: For IG bull the more time passes the more the premiums drop");
    InvariantInfo internal _IG_27       =   InvariantInfo("IG_27",      "IG_27: IG smilee payoff is always positive if the strike price change & zero the strike price doesn't change");

    InvariantInfo internal _GENERAL_1 = InvariantInfo("GENERAL_1", "GENERAL_1: This should never revert");
    InvariantInfo internal _GENERAL_4 = InvariantInfo("GENERAL_4", "GENERAL_4: After timestamp roll-epoch should not revert");
    InvariantInfo internal _GENERAL_5 = InvariantInfo("GENERAL_5", "GENERAL_5: Can't revert before timestamp");
    InvariantInfo internal _GENERAL_6 = InvariantInfo("GENERAL_6", "GENERAL_6: Buy and sell should not revert");

    InvariantInfo internal _VAULT_01    =   InvariantInfo("VAULT_01",     "VAULT_01: Vault payoff at roll-epoch >= DEX LP payoff");
    InvariantInfo internal _VAULT_03    =   InvariantInfo("VAULT_03",     "VAULT_03: Vault balances = (or >=) PendingWithdraw + PendingPayoff + PendingDeposit + (vault share * sharePrice)");
    InvariantInfo internal _VAULT_04    =   InvariantInfo("VAULT_04",     "VAULT_04: Vault base tokens = (or >=) PendingWithdraw + PendingPayoff + PendingDeposit");
    InvariantInfo internal _VAULT_06    =   InvariantInfo("VAULT_06",     "VAULT_06: Vault balances minus PendingWithdraw and PendingPayoff are equal to an Equal Weight portfolio after roll-epoch");
    InvariantInfo internal _VAULT_08    =   InvariantInfo("VAULT_08",     "VAULT_08: SharePrice does not change during epoch");
    InvariantInfo internal _VAULT_10    =   InvariantInfo("VAULT_10",     "VAULT_10: Payoff Transfer (which happens everytime an IG position is sold or burnt) <= base token in vualt");
    InvariantInfo internal _VAULT_11    =   InvariantInfo("VAULT_11",     "VAULT_11: Vaults never exeecds tokens available when swap to hedge delta");
    InvariantInfo internal _VAULT_13    =   InvariantInfo("VAULT_13",     "VAULT_13: OutstandingShares does not change during the epoch (liquidity is added to vault only at roll-epoch)");
    InvariantInfo internal _VAULT_15    =   InvariantInfo("VAULT_15",     "VAULT_15: Deposit are converted at SharePrice (aka the fair price)");
    InvariantInfo internal _VAULT_16    =   InvariantInfo("VAULT_16",     "VAULT_16: SharePrice never goes to 0");
    InvariantInfo internal _VAULT_17    =   InvariantInfo("VAULT_17",     "VAULT_17: PendingWithdraw & PendingPayoff does not change during epoch");
    InvariantInfo internal _VAULT_18    =   InvariantInfo("VAULT_18",     "VAULT_18: NewPendingWithdraw & NewPendingPayoff are zero during epoch");
    InvariantInfo internal _VAULT_19    =   InvariantInfo("VAULT_19",     "VAULT_19: Withdrawal Share are converted at SharePrice (aka the fair price). Withdraw = withdrawal Share * Share Price");
    InvariantInfo internal _VAULT_20    =   InvariantInfo("VAULT_20",     "VAULT_20: Vault balances >= PendingWithdraw + PendingPayoff + PendingDeposit + LP value + IG minted value");
    InvariantInfo internal _VAULT_23    =   InvariantInfo("VAULT_23",     "VAULT_23: OutstandingShare_epoch_t = OutstandingShare_epoch_t-1 + NewShare_at_roll_epoch - WithdrawalShare_at_roll_epoch");
}
