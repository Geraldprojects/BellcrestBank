/**
 * @author: Gomolemo
 * @description: Creates a household statement and its frozen per-account lines for a statement period.
 * @date: 2026/09/11
 **/

public with sharing class StatementHelper {

    public static List<Household_Statement__c> createStatements(
            Map<Id, Set<Id>> financialAccountIdsByHousehold,
            Date periodStart,
            Date periodEnd
    ) {
        Set<Id> financialAccountIds = new Set<Id>();
        for (Set<Id> ids : financialAccountIdsByHousehold.values()) {
            financialAccountIds.addAll(ids);
        }

        Map<Id, FinancialAccountBalance> balanceByFinancialAccount =
                StatementService.getClosingBalanceByFinancialAccount(financialAccountIds, periodStart, periodEnd);
        Map<Id, List<FinancialAccountFee>> feesByFinancialAccount =
                StatementService.getFeesByFinancialAccount(financialAccountIds, periodStart, periodEnd);
        Map<Id, FinancialAccount> financialAccounts =
                new FinancialAccountsSelector().selectMapById(financialAccountIds);
        Set<Id> jointFinancialAccountIds =
                new FinancialAccountPartiesSelector().selectJointFinancialAccountIds(financialAccountIds);

        // Headers first: the lines need their Ids for the master-detail and their own upsert key.
        Map<Id, Household_Statement__c> statementByHousehold = new Map<Id, Household_Statement__c>();
        for (Id householdId : financialAccountIdsByHousehold.keySet()) {
            statementByHousehold.put(householdId, new Household_Statement__c(
                    Household__c = householdId,
                    Statement_Key__c = householdId + '-' + String.valueOf(periodEnd),
                    Period_Start__c = periodStart,
                    Period_End__c = periodEnd,
                    Status__c = 'Draft',
                    Total_Balance__c = 0,
                    Total_Fees__c = 0
            ));
        }
        upsert statementByHousehold.values() Household_Statement__c.Fields.Statement_Key__c;

        List<Statement_Line__c> lines = new List<Statement_Line__c>();
        for (Id householdId : financialAccountIdsByHousehold.keySet()) {
            Household_Statement__c statement = statementByHousehold.get(householdId);
            Decimal totalBalance = 0;
            Decimal totalFees = 0;

            for (Id financialAccountId : financialAccountIdsByHousehold.get(householdId)) {
                FinancialAccount financialAccount = financialAccounts.get(financialAccountId);
                FinancialAccountBalance balance = balanceByFinancialAccount.get(financialAccountId);
                Decimal fees = sumFees(feesByFinancialAccount.get(financialAccountId));

                lines.add(new Statement_Line__c(
                        Household_Statement__c = statement.Id,
                        Financial_Account__c = financialAccountId,
                        Statement_Key__c = statement.Id + '-' + financialAccountId,
                        // Name, number, type and ownership are copied so a later rename, retyping or change of
                        // owners doesn't alter an issued statement.
                        Financial_Account_Name__c = financialAccount.Name,
                        Financial_Account_Number__c = financialAccount.FinancialAccountNumber,
                        Financial_Account_Type__c = financialAccount.Type,
                        Is_Joint__c = jointFinancialAccountIds.contains(financialAccountId),
                        // Left null when no snapshot arrived for the period, so the gap is visible instead of filled with stale data.
                        Closing_Balance__c = balance?.Amount,
                        Total_Fees__c = fees
                ));

                if (balance?.Amount != null) {
                    totalBalance += balance.Amount;
                }
                totalFees += fees;
            }

            // Summed in Apex rather than by roll-up summary, so an issued statement's totals can't shift later.
            statement.Total_Balance__c = totalBalance;
            statement.Total_Fees__c = totalFees;
        }

        // Keyed on statement + account, so rerunning a period updates the lines instead of duplicating them.
        upsert lines Statement_Line__c.Fields.Statement_Key__c;
        update statementByHousehold.values();
        return statementByHousehold.values();
    }

    private static Decimal sumFees(List<FinancialAccountFee> fees) {
        Decimal total = 0;
        if (fees == null) {
            return total;
        }
        for (FinancialAccountFee fee : fees) {
            // Rate-only fees have no Amount; they need the balance to price.
            if (fee.Amount != null) {
                total += fee.Amount;
            }
        }
        return total;
    }
}