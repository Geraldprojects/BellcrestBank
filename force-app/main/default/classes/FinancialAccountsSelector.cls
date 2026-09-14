/**
 * @author: Gomolemo
 * @description: Query layer for FinancialAccount.
 *               Declared inherited sharing so each caller's sharing context carries through unchanged.
 * @date: 2026/09/13
 **/

public inherited sharing class FinancialAccountsSelector extends fflib_SObjectSelector {

    public Schema.SObjectType getSObjectType() {
        return FinancialAccount.SObjectType;
    }

    public List<Schema.SObjectField> getSObjectFieldList() {
        return new List<Schema.SObjectField>{
                FinancialAccount.Id,
                FinancialAccount.Name,
                FinancialAccount.FinancialAccountNumber,
                FinancialAccount.Type,
                FinancialAccount.Status
        };
    }

    public List<FinancialAccount> selectById(Set<Id> financialAccountIds) {
        return (List<FinancialAccount>) selectSObjectsById(financialAccountIds);
    }

    public Map<Id, FinancialAccount> selectMapById(Set<Id> financialAccountIds) {
        return new Map<Id, FinancialAccount>(selectById(financialAccountIds));
    }
}