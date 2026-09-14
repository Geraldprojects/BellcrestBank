/**
 * @author: Gomolemo
 * @description: Query layer for PartyRelationshipGroup, the household grouping record.
 *               Declared inherited sharing so each caller's sharing context carries through unchanged.
 * @date: 2026/09/13
 **/

public inherited sharing class PartyRelationshipGroupsSelector extends fflib_SObjectSelector {

    private static final String HOUSEHOLD_TYPE = 'Household';
    private static final String ACTIVE_STATUS = 'Active';

    public Schema.SObjectType getSObjectType() {
        return PartyRelationshipGroup.SObjectType;
    }

    public List<Schema.SObjectField> getSObjectFieldList() {
        return new List<Schema.SObjectField>{
                PartyRelationshipGroup.Id,
                PartyRelationshipGroup.AccountId,
                PartyRelationshipGroup.Type,
                PartyRelationshipGroup.Status
        };
    }

    /**
     * A locator rather than a list, because the statement batch iterates every active household and the
     * collection is expected to outgrow a single query's row limit.
     */
    public Database.QueryLocator selectActiveHouseholdsLocator() {
        String householdType = HOUSEHOLD_TYPE;
        String activeStatus = ACTIVE_STATUS;
        return Database.getQueryLocator(
                newQueryFactory()
                        .setCondition('Type = :householdType AND Status = :activeStatus')
                        .toSOQL()
        );
    }
}