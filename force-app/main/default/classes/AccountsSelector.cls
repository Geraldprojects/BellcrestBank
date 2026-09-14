/**
 * @author: Gomolemo
 * @description: Query layer for Account, which is how households are stored.
 *               Declared inherited sharing so each caller's sharing context carries through unchanged.
 * @date: 2026/09/13
 **/

public inherited sharing class AccountsSelector extends fflib_SObjectSelector {

    public Schema.SObjectType getSObjectType() {
        return Account.SObjectType;
    }

    public List<Schema.SObjectField> getSObjectFieldList() {
        return new List<Schema.SObjectField>{
                Account.Id,
                Account.Name,
                Account.OwnerId
        };
    }

    public List<Account> selectById(Set<Id> accountIds) {
        return (List<Account>) selectSObjectsById(accountIds);
    }

    /**
     * Households whose owner is still active. An inactive owner is filtered out here rather than by the
     * caller, because a notification addressed to one throws at send time.
     */
    public List<Account> selectWithActiveOwner(Set<Id> accountIds) {
        return (List<Account>) Database.query(
                newQueryFactory()
                        .setCondition('Id IN :accountIds AND Owner.IsActive = TRUE')
                        .toSOQL()
        );
    }
}