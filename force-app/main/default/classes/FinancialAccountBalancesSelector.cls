/**
 * @author: Gomolemo
 * @description: Query layer for FinancialAccountBalance.
 *               Declared inherited sharing so each caller's sharing context carries through unchanged.
 * @date: 2026/09/13
 **/

public inherited sharing class FinancialAccountBalancesSelector extends fflib_SObjectSelector {

    private static final String TOTAL_BALANCE = 'Total Balance';

    public Schema.SObjectType getSObjectType() {
        return FinancialAccountBalance.SObjectType;
    }

    public List<Schema.SObjectField> getSObjectFieldList() {
        return new List<Schema.SObjectField>{
                FinancialAccountBalance.Id,
                FinancialAccountBalance.FinancialAccountId,
                FinancialAccountBalance.Amount,
                FinancialAccountBalance.BalanceAsOfDate,
                FinancialAccountBalance.Type
        };
    }

    public override String getOrderBy() {
        // Newest first, so a caller taking the first row per account gets the closing balance.
        return 'BalanceAsOfDate DESC';
    }

    /**
     * Total-balance snapshots falling inside the period. BalanceAsOfDate is a Datetime, so the period
     * runs up to midnight after its last day.
     */
    public List<FinancialAccountBalance> selectForPeriod(
            Set<Id> financialAccountIds,
            Date periodStart,
            Date periodEnd
    ) {
        Datetime periodStartTime = Datetime.newInstance(periodStart, Time.newInstance(0, 0, 0, 0));
        Datetime periodEndTime = Datetime.newInstance(periodEnd.addDays(1), Time.newInstance(0, 0, 0, 0));
        String balanceType = TOTAL_BALANCE;

        return (List<FinancialAccountBalance>) Database.query(
                newQueryFactory()
                        .setCondition(
                                'FinancialAccountId IN :financialAccountIds'
                                        + ' AND BalanceAsOfDate >= :periodStartTime'
                                        + ' AND BalanceAsOfDate < :periodEndTime'
                        )
                        .toSOQL()
        );
    }
}