/**
 * @author: Gomolemo
 * @description: Resolves households to their financial accounts, and those accounts to balances and fees for a statement period.
 * @date: 2026/09/11
 **/

public with sharing class StatementService {

    public static Map<Id, Set<Id>> getFinancialAccountIdsByHousehold(Set<Id> householdIds) {
        Map<Id, Set<Id>> memberIdsByHousehold = new Map<Id, Set<Id>>();
        for (Id householdId : householdIds) {
            memberIdsByHousehold.put(householdId, new Set<Id>());
        }

        // ACR points at the person's contact; parties are recorded against the person account.
        Set<Id> memberIds = new Set<Id>();
        for (AccountContactRelation member :
                new AccountContactRelationsSelector().selectActiveByHousehold(householdIds)) {
            memberIdsByHousehold.get(member.AccountId).add(member.Contact.AccountId);
            memberIds.add(member.Contact.AccountId);
        }

        Map<Id, Set<Id>> financialAccountIdsByMember = new Map<Id, Set<Id>>();
        for (FinancialAccountParty party :
                new FinancialAccountPartiesSelector().selectByAccountId(memberIds)) {
            if (!financialAccountIdsByMember.containsKey(party.AccountId)) {
                financialAccountIdsByMember.put(party.AccountId, new Set<Id>());
            }
            financialAccountIdsByMember.get(party.AccountId).add(party.FinancialAccountId);
        }

        // A joint account comes back once per owner; collecting into a Set counts it once per household.
        Map<Id, Set<Id>> financialAccountIdsByHousehold = new Map<Id, Set<Id>>();
        for (Id householdId : memberIdsByHousehold.keySet()) {
            Set<Id> financialAccountIds = new Set<Id>();
            for (Id memberId : memberIdsByHousehold.get(householdId)) {
                if (financialAccountIdsByMember.containsKey(memberId)) {
                    financialAccountIds.addAll(financialAccountIdsByMember.get(memberId));
                }
            }
            financialAccountIdsByHousehold.put(householdId, financialAccountIds);
        }
        return financialAccountIdsByHousehold;
    }

    public static Map<Id, FinancialAccountBalance> getClosingBalanceByFinancialAccount(
            Set<Id> financialAccountIds,
            Date periodStart,
            Date periodEnd
    ) {
        // BalanceAsOfDate is a Datetime, so the period runs up to midnight after its last day.
        Datetime periodStartTime = Datetime.newInstance(periodStart, Time.newInstance(0, 0, 0, 0));
        Datetime periodEndTime = Datetime.newInstance(periodEnd.addDays(1), Time.newInstance(0, 0, 0, 0));

        Map<Id, FinancialAccountBalance> balanceByFinancialAccount = new Map<Id, FinancialAccountBalance>();
        for (FinancialAccountBalance balance : new FinancialAccountBalancesSelector()
                .selectForPeriod(financialAccountIds, periodStart, periodEnd)) {
            // Newest first, so the first row seen per account is its closing balance for the period.
            if (!balanceByFinancialAccount.containsKey(balance.FinancialAccountId)) {
                balanceByFinancialAccount.put(balance.FinancialAccountId, balance);
            }
        }
        return balanceByFinancialAccount;
    }

    public static Map<Id, List<FinancialAccountFee>> getFeesByFinancialAccount(
            Set<Id> financialAccountIds,
            Date periodStart,
            Date periodEnd
    ) {
        Map<Id, List<FinancialAccountFee>> feesByFinancialAccount = new Map<Id, List<FinancialAccountFee>>();
        // Any fee in force for at least part of the period, including ones starting or ending mid-period.
        for (FinancialAccountFee fee : new FinancialAccountFeesSelector()
                .selectForPeriod(financialAccountIds, periodStart, periodEnd)) {
            if (!feesByFinancialAccount.containsKey(fee.FinancialAccountId)) {
                feesByFinancialAccount.put(fee.FinancialAccountId, new List<FinancialAccountFee>());
            }
            feesByFinancialAccount.get(fee.FinancialAccountId).add(fee);
        }
        return feesByFinancialAccount;
    }
}