/**
 * @author: Gomolemo
 * @description: Covers the three file selectors that between them find a stored statement PDF:
 *               ContentVersionsSelector, ContentDocumentsSelector and ContentDocumentLinksSelector.
 * @date: 2026/09/13
 **/

@IsTest
private class StatementFileSelectorsTest {

    @IsTest
    static void documentLinksResolveFromTheRecordTheFileWasPublishedAgainst() {
        Account household = StatementTestDataFactory.createHousehold('File Household');
        Household_Statement__c statement = StatementTestDataFactory.createStatement(
                household.Id, 'FILE-1', Date.today().addDays(-30), Date.today(), 'Ready'
        );
        ContentVersion version = StatementTestDataFactory.createDocument(statement.Id, 'Statement File');

        Set<Id> documentIds = new ContentDocumentLinksSelector()
                .selectDocumentIdsByLinkedEntity(new Set<Id>{ statement.Id });

        Assert.areEqual(1, documentIds.size(), 'The published file should be found through its link');
        Assert.isTrue(
                documentIds.contains(version.ContentDocumentId),
                'The document id should match the inserted version'
        );
    }

    @IsTest
    static void documentLinksReturnsEmptyWithoutQueryingWhenGivenNoIds() {
        Integer queriesBefore = Limits.getQueries();

        Set<Id> documentIds = new ContentDocumentLinksSelector()
                .selectDocumentIdsByLinkedEntity(new Set<Id>());

        Assert.isTrue(documentIds.isEmpty(), 'No ids means no documents');
        Assert.areEqual(
                queriesBefore, Limits.getQueries(),
                'An empty id set should short-circuit rather than spend a query'
        );
    }

    @IsTest
    static void contentVersionSelectorResolvesTheOwningDocument() {
        Account household = StatementTestDataFactory.createHousehold('Version Household');
        Household_Statement__c statement = StatementTestDataFactory.createStatement(
                household.Id, 'FILE-2', Date.today().addDays(-30), Date.today(), 'Ready'
        );
        ContentVersion version = StatementTestDataFactory.createDocument(statement.Id, 'Version File');

        List<ContentVersion> results =
                new ContentVersionsSelector().selectById(new Set<Id>{ version.Id });

        Assert.areEqual(1, results.size(), 'The requested version should be returned');
        Assert.areEqual(
                version.ContentDocumentId, results[0].ContentDocumentId,
                'ContentDocumentId is what builds the document URL on the statement'
        );
    }

    @IsTest
    static void contentDocumentSelectorReturnsTheDocumentsToDelete() {
        Account household = StatementTestDataFactory.createHousehold('Document Household');
        Household_Statement__c statement = StatementTestDataFactory.createStatement(
                household.Id, 'FILE-3', Date.today().addDays(-30), Date.today(), 'Ready'
        );
        ContentVersion version = StatementTestDataFactory.createDocument(statement.Id, 'Document File');

        List<ContentDocument> results =
                new ContentDocumentsSelector().selectById(new Set<Id>{ version.ContentDocumentId });

        Assert.areEqual(1, results.size(), 'The owning document should be returned');
    }
}