/**
 * @author: Gomolemo
 * @description: Query layer for ContentDocument, the stored statement files.
 *               Declared inherited sharing so each caller's sharing context carries through unchanged.
 * @date: 2026/09/13
 **/

public inherited sharing class ContentDocumentsSelector extends fflib_SObjectSelector {

    public Schema.SObjectType getSObjectType() {
        return ContentDocument.SObjectType;
    }

    public List<Schema.SObjectField> getSObjectFieldList() {
        return new List<Schema.SObjectField>{
                ContentDocument.Id,
                ContentDocument.Title,
                ContentDocument.FileExtension
        };
    }

    public override String getOrderBy() {
        return 'Title';
    }

    public List<ContentDocument> selectById(Set<Id> documentIds) {
        return (List<ContentDocument>) selectSObjectsById(documentIds);
    }
}