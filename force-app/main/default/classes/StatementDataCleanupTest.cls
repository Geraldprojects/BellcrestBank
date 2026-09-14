/**
 * @author: Gomolemo
 * @description: Covers StatementDataCleanup, which clears generated statement data so the org can be
 *               retested from a clean slate.
 *
 *               Two things matter about this class and both are asserted here: it removes everything
 *               a run produced, and it leaves the source data alone so the batch can be run again.
 * @date: 2026/09/14
 **/

@IsTest
private class StatementDataCleanupTest {

    @TestSetup
    static void setup() {
        Account household = StatementTestDataFactory.createHousehold('Cleanup Household');
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Cleanup FA', '3010', 'Savings');
        StatementTestDataFactory.createParty(financialAccount.Id, household.Id, 'Owner');
        StatementTestDataFactory.createRelationshipGroup(household.Id, 'Cleanup Group', 'Household', 'Active');

        Household_Statement__c statement = StatementTestDataFactory.createStatement(
                household.Id, 'CLEAN-1', Date.newInstance(2026, 8, 1), Date.newInstance(2026, 8, 31), 'Ready'
        );
        StatementTestDataFactory.createLine(statement.Id, financialAccount.Id, 'CLEAN-1-A', 'Alpha', false);
        StatementTestDataFactory.createLine(statement.Id, financialAccount.Id, 'CLEAN-1-B', 'Beta', true);
        StatementTestDataFactory.createDocument(statement.Id, 'Cleanup Statement');
    }

    @IsTest
    static void previewReportsWhatWouldBeRemovedWithoutRemovingIt() {
        // Given a generated statement with lines and a stored document

        // When the cleanup is previewed
        Test.startTest();
        StatementDataCleanup.Summary summary = StatementDataCleanup.preview();
        Test.stopTest();

        // Then it reports the counts
        Assert.areEqual(1, summary.statements, 'One statement should be reported');
        Assert.areEqual(2, summary.lines, 'Both lines should be reported');
        Assert.areEqual(1, summary.documents, 'The stored document should be reported');

        // And nothing has actually been deleted
        Assert.areEqual(1, [SELECT COUNT() FROM Household_Statement__c], 'Preview must not delete');
        Assert.areEqual(2, [SELECT COUNT() FROM Statement_Line__c], 'Preview must not delete');
    }

    @IsTest
    static void runRemovesTheStatementsAndTheirLines() {
        // Given a generated statement with lines

        // When the cleanup runs
        Test.startTest();
        StatementDataCleanup.Summary summary = StatementDataCleanup.run();
        Test.stopTest();

        // Then the statements are gone, and the lines go with them via the master-detail
        Assert.areEqual(1, summary.statements, 'It should report the statement it removed');
        Assert.areEqual(0, [SELECT COUNT() FROM Household_Statement__c], 'No statements should remain');
        Assert.areEqual(
                0, [SELECT COUNT() FROM Statement_Line__c],
                'Lines cascade with their parent statement'
        );
    }

    @IsTest
    static void runRemovesTheGeneratedDocuments() {
        // Given a statement with a stored PDF
        Assert.areEqual(1, [SELECT COUNT() FROM ContentDocument], 'The document should exist to begin with');

        // When the cleanup runs
        Test.startTest();
        StatementDataCleanup.Summary summary = StatementDataCleanup.run();
        Test.stopTest();

        // Then the file is deleted rather than left orphaned once its statement is gone
        Assert.areEqual(1, summary.documents, 'It should report the document it removed');
        Assert.areEqual(
                0, [SELECT COUNT() FROM ContentDocument],
                'Deleting a statement only drops the link, so the file must be deleted explicitly'
        );
    }

    @IsTest
    static void runLeavesTheSourceDataAloneSoTheBatchCanRunAgain() {
        // Given households, financial accounts and parties that the batch reads from

        // When the cleanup runs
        Test.startTest();
        StatementDataCleanup.run();
        Test.stopTest();

        // Then everything generation reads from is still there
        Assert.areEqual(1, [SELECT COUNT() FROM Account], 'Households should survive the cleanup');
        Assert.areEqual(1, [SELECT COUNT() FROM FinancialAccount], 'Financial accounts should survive');
        Assert.areEqual(1, [SELECT COUNT() FROM FinancialAccountParty], 'Account holders should survive');
        Assert.areEqual(
                1, [SELECT COUNT() FROM PartyRelationshipGroup],
                'The household groups the batch iterates should survive'
        );
    }

    @IsTest
    static void runningOnAnAlreadyCleanOrgIsSafe() {
        // Given an org that has already been cleared
        StatementDataCleanup.run();

        // When the cleanup runs a second time
        Test.startTest();
        StatementDataCleanup.Summary summary = StatementDataCleanup.run();
        Test.stopTest();

        // Then it reports nothing and does nothing, rather than failing on empty collections
        Assert.areEqual(0, summary.statements, 'There is nothing left to remove');
        Assert.areEqual(0, summary.lines, 'There is nothing left to remove');
        Assert.areEqual(0, summary.documents, 'There is nothing left to remove');
    }

    @IsTest
    static void theSummaryReadsAsALineOfText() {
        // When a summary is produced
        Test.startTest();
        String summary = String.valueOf(StatementDataCleanup.preview());
        Test.stopTest();

        // Then it is readable in a debug log without unpacking it
        Assert.isTrue(summary.contains('statements=1'), 'The summary should name its counts: ' + summary);
        Assert.isTrue(summary.contains('lines=2'), 'The summary should name its counts: ' + summary);
        Assert.isTrue(summary.contains('documents=1'), 'The summary should name its counts: ' + summary);
    }
}