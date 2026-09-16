/**
 * @author: Gomolemo
 * @description: Query layer for ContentDocumentLink, joining stored files to their records.
 *               Declared inherited sharing so each caller's sharing context carries through unchanged.
 * @date: 2026/09/13
 **/

public inherited sharing class ContentDocumentLinksSelector extends fflib_SObjectSelector {

    public Schema.SObjectType getSObjectType() {
        return ContentDocumentLink.SObjectType;
    }

    public List<Schema.SObjectField> getSObjectFieldList() {
        return new List<Schema.SObjectField>{
                ContentDocumentLink.Id,
                ContentDocumentLink.ContentDocumentId,
                ContentDocumentLink.LinkedEntityId
        };
    }

    public override String getOrderBy() {
        return 'ContentDocumentId';
    }

    /**
     * Documents attached to the given records.
     *
     * ContentDocumentLink must be filtered by LinkedEntityId or ContentDocumentId and rejects semi-join
     * subqueries, so the ids are always bound in rather than reached through a nested select.
     */
    public Set<Id> selectDocumentIdsByLinkedEntity(Set<Id> linkedEntityIds) {
        Set<Id> documentIds = new Set<Id>();
        if (linkedEntityIds.isEmpty()) {
            return documentIds;
        }
        for (ContentDocumentLink link : (List<ContentDocumentLink>) Database.query(
                newQueryFactory().setCondition('LinkedEntityId IN :linkedEntityIds').toSOQL()
        )) {
            documentIds.add(link.ContentDocumentId);
        }
        return documentIds;
    }
}