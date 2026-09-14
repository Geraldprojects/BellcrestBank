/**
 * @author: Gomolemo
 * @description: Query layer for ContentVersion, the stored statement PDFs.
 *               Declared inherited sharing so each caller's sharing context carries through unchanged.
 * @date: 2026/09/13
 **/

public inherited sharing class ContentVersionsSelector extends fflib_SObjectSelector {

    public Schema.SObjectType getSObjectType() {
        return ContentVersion.SObjectType;
    }

    public List<Schema.SObjectField> getSObjectFieldList() {
        return new List<Schema.SObjectField>{
                ContentVersion.Id,
                ContentVersion.Title,
                ContentVersion.ContentDocumentId,
                ContentVersion.FileExtension,
                ContentVersion.ContentSize
        };
    }

    public override String getOrderBy() {
        return 'Title';
    }

    public List<ContentVersion> selectById(Set<Id> versionIds) {
        return (List<ContentVersion>) selectSObjectsById(versionIds);
    }
}