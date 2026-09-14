/**
 * @author: Gomolemo
 * @description: Query layer for StaticResource, which holds the Word statement template.
 *               Declared inherited sharing so each caller's sharing context carries through unchanged.
 * @date: 2026/09/13
 **/

public inherited sharing class StaticResourcesSelector extends fflib_SObjectSelector {

    public Schema.SObjectType getSObjectType() {
        return StaticResource.SObjectType;
    }

    public List<Schema.SObjectField> getSObjectFieldList() {
        return new List<Schema.SObjectField>{
                StaticResource.Id,
                StaticResource.Name,
                StaticResource.Body
        };
    }

    public List<StaticResource> selectByName(Set<String> names) {
        return (List<StaticResource>) Database.query(
                newQueryFactory().setCondition('Name IN :names').toSOQL()
        );
    }
}