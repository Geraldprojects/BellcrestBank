/**
 * @author: Gomolemo
 * @description: Query layer for AccountContactRelation, used to resolve household membership.
 *               Declared inherited sharing so each caller's sharing context carries through unchanged.
 * @date: 2026/09/13
 **/

public inherited sharing class AccountContactRelationsSelector extends fflib_SObjectSelector {

    public Schema.SObjectType getSObjectType() {
        return AccountContactRelation.SObjectType;
    }

    public List<Schema.SObjectField> getSObjectFieldList() {
        return new List<Schema.SObjectField>{
                AccountContactRelation.Id,
                AccountContactRelation.AccountId,
                AccountContactRelation.ContactId,
                AccountContactRelation.IsActive
        };
    }

    public override String getOrderBy() {
        return 'AccountId';
    }

    /**
     * Active members of the given households. Contact.AccountId comes along because the relationship
     * points at the person's contact while financial account parties are recorded against their
     * person account.
     */
    public List<AccountContactRelation> selectActiveByHousehold(Set<Id> householdIds) {
        return (List<AccountContactRelation>) Database.query(
                newQueryFactory()
                        .selectField('Contact.AccountId')
                        .setCondition('AccountId IN :householdIds AND IsActive = TRUE')
                        .toSOQL()
        );
    }
}