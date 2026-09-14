/**
 * @author: Gomolemo
 * @description: Query layer for FinancialAccountFee.
 *               Declared inherited sharing so each caller's sharing context carries through unchanged.
 * @date: 2026/09/13
 **/

public inherited sharing class FinancialAccountFeesSelector extends fflib_SObjectSelector {

    public Schema.SObjectType getSObjectType() {
        return FinancialAccountFee.SObjectType;
    }

    public List<Schema.SObjectField> getSObjectFieldList() {
        return new List<Schema.SObjectField>{
                FinancialAccountFee.Id,
                FinancialAccountFee.FinancialAccountId,
                FinancialAccountFee.Type,
                FinancialAccountFee.Amount,
                FinancialAccountFee.Rate,
                FinancialAccountFee.Frequency,
                FinancialAccountFee.StartDate,
                FinancialAccountFee.EndDate
        };
    }

    public override String getOrderBy() {
        return 'FinancialAccountId';
    }

    /**
     * Any fee in force for at least part of the period, including ones starting or ending mid-period.
     */
    public List<FinancialAccountFee> selectForPeriod(
            Set<Id> financialAccountIds,
            Date periodStart,
            Date periodEnd
    ) {
        return (List<FinancialAccountFee>) Database.query(
                newQueryFactory()
                        .setCondition(
                                'FinancialAccountId IN :financialAccountIds'
                                        + ' AND StartDate <= :periodEnd'
                                        + ' AND (EndDate = NULL OR EndDate >= :periodStart)'
                        )
                        .toSOQL()
        );
    }
}