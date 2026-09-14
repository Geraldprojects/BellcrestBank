/**
 * @author: Gomolemo
 * @description: Query layer for FinancialAccountParty, which records who holds a financial account.
 *               Declared inherited sharing so each caller's sharing context carries through unchanged.
 * @date: 2026/09/13
 **/

public inherited sharing class FinancialAccountPartiesSelector extends fflib_SObjectSelector {

    // Roles that confer ownership. Beneficiaries, leasees and drivers are parties to an account without
    // owning it. 'Co-Owner' is absent from the Role picklist but present in the data, so it is matched
    // explicitly rather than inferred from the picklist.
    private static final Set<String> OWNERSHIP_ROLES = new Set<String>{ 'Owner', 'Co-Owner' };

    public Schema.SObjectType getSObjectType() {
        return FinancialAccountParty.SObjectType;
    }

    public List<Schema.SObjectField> getSObjectFieldList() {
        return new List<Schema.SObjectField>{
                FinancialAccountParty.Id,
                FinancialAccountParty.AccountId,
                FinancialAccountParty.FinancialAccountId,
                FinancialAccountParty.Role,
                FinancialAccountParty.IsRoleActive
        };
    }

    public override String getOrderBy() {
        return 'FinancialAccountId';
    }

    public List<FinancialAccountParty> selectByAccountId(Set<Id> accountIds) {
        return (List<FinancialAccountParty>) Database.query(
                newQueryFactory().setCondition('AccountId IN :accountIds').toSOQL()
        );
    }

    /**
     * Financial accounts held jointly, meaning more than one active party in an ownership role.
     *
     * Written as raw SOQL rather than through the query factory because fflib builds field selections,
     * not aggregates - there is no GROUP BY equivalent on fflib_QueryFactory.
     */
    public Set<Id> selectJointFinancialAccountIds(Set<Id> financialAccountIds) {
        Set<String> ownershipRoles = OWNERSHIP_ROLES;
        Set<Id> jointIds = new Set<Id>();
        for (AggregateResult result : [
                SELECT FinancialAccountId financialAccountId, COUNT(Id) ownerCount
                FROM FinancialAccountParty
                WHERE FinancialAccountId IN :financialAccountIds
                AND Role IN :ownershipRoles
                AND IsRoleActive = TRUE
                GROUP BY FinancialAccountId
                HAVING COUNT(Id) > 1
        ]) {
            jointIds.add((Id) result.get('financialAccountId'));
        }
        return jointIds;
    }
}