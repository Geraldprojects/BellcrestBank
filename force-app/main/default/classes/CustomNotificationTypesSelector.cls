/**
 * @author: Gomolemo
 * @description: Query layer for CustomNotificationType.
 *               Declared inherited sharing so each caller's sharing context carries through unchanged.
 * @date: 2026/09/13
 **/

public inherited sharing class CustomNotificationTypesSelector extends fflib_SObjectSelector {

    public Schema.SObjectType getSObjectType() {
        return CustomNotificationType.SObjectType;
    }

    public List<Schema.SObjectField> getSObjectFieldList() {
        return new List<Schema.SObjectField>{
                CustomNotificationType.Id,
                CustomNotificationType.DeveloperName,
                CustomNotificationType.MasterLabel
        };
    }

    public override String getOrderBy() {
        return 'DeveloperName';
    }

    public List<CustomNotificationType> selectByDeveloperName(Set<String> developerNames) {
        return (List<CustomNotificationType>) Database.query(
                newQueryFactory().setCondition('DeveloperName IN :developerNames').toSOQL()
        );
    }
}