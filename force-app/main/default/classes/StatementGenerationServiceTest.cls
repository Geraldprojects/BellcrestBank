/**
 * @author: Gomolemo
 * @description: Covers StatementGenerationService.advance(), which moves one statement through
 *               generation a single step at a time.
 *
 *               advance() reports what it accomplished as an Outcome, and the caller decides what to do
 *               next. There are four outcomes, and there is a test for each:
 *
 *                   SUBMITTED - handed to Adobe, marked Generating
 *                   PENDING   - Adobe still working, nothing changed
 *                   COMPLETED - PDF stored, marked Ready
 *                   FAILED    - marked Failed with the reason recorded
 * @date: 2026/09/13
 **/

@IsTest
private class StatementGenerationServiceTest {

    @TestSetup
    static void setup() {
        Account household = StatementTestDataFactory.createHousehold('Generation Household');
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Gen FA', '7010', 'Savings');

        Household_Statement__c statement = StatementTestDataFactory.createStatement(
                household.Id, 'GEN-1', Date.newInstance(2026, 8, 1), Date.newInstance(2026, 8, 31), 'Draft'
        );
        StatementTestDataFactory.createLine(statement.Id, financialAccount.Id, 'GEN-1-A', 'Gen FA', false);
    }

    private static Household_Statement__c getStatement() {
        return [
                SELECT Id, Status__c, Adobe_Job_URI__c, Document_URL__c, Error_Detail__c, Retry_Count__c
                FROM Household_Statement__c
                WHERE Statement_Key__c = 'GEN-1'
        ];
    }

    @IsTest
    static void submittingHandsTheJobToAdobeAndMarksTheStatementGenerating() {
        // Given a draft statement that has never been submitted
        Household_Statement__c statement = getStatement();
        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobCompletes());

        // When the service advances it
        Test.startTest();
        StatementGenerationService.Result result =
                StatementGenerationService.advance(statement.Id, null, 0);
        Test.stopTest();

        // Then the job is submitted and the statement is waiting on Adobe
        Assert.areEqual(
                StatementGenerationService.Outcome.SUBMITTED, result.outcome,
                'A statement with no job URI should be submitted'
        );

        Household_Statement__c updated = getStatement();
        Assert.areEqual('Generating', updated.Status__c, 'The statement should now be Generating');
        Assert.areEqual(
                AdobeCalloutMock.JOB_PATH, updated.Adobe_Job_URI__c,
                'The job location should be stored as a path, not an absolute URL'
        );
    }

    @IsTest
    static void submittingUploadsTheTemplateAndReturnsItForReuse() {
        // Given a draft statement and no template uploaded yet
        Household_Statement__c statement = getStatement();
        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobCompletes());

        // When the service advances it without being given a template
        Test.startTest();
        StatementGenerationService.Result result =
                StatementGenerationService.advance(statement.Id, null, 0);
        Test.stopTest();

        // Then the uploaded template comes back so the rest of the run can reuse it
        Assert.areEqual(
                AdobeCalloutMock.ASSET_ID, result.templateAssetId,
                'The template asset id should be returned for the next statement to reuse'
        );
    }

    @IsTest
    static void anAlreadyUploadedTemplateIsPassedStraightThrough() {
        // Given a template that an earlier statement in this run already uploaded
        Household_Statement__c statement = getStatement();
        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobCompletes());

        // When the service advances with that template supplied
        Test.startTest();
        StatementGenerationService.Result result =
                StatementGenerationService.advance(statement.Id, 'existing-asset-id', 0);
        Test.stopTest();

        // Then it is reused rather than replaced by a fresh upload
        Assert.areEqual(
                'existing-asset-id', result.templateAssetId,
                'An existing template should be reused, not uploaded again'
        );
    }

    @IsTest
    static void aFinishedJobIsDownloadedStoredAndMarkedReady() {
        // Given a statement already submitted to Adobe
        Household_Statement__c statement = getStatement();
        statement.Adobe_Job_URI__c = AdobeCalloutMock.JOB_PATH;
        statement.Status__c = 'Generating';
        update statement;

        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobCompletes());

        // When the service polls and finds the job done
        Test.startTest();
        StatementGenerationService.Result result =
                StatementGenerationService.advance(statement.Id, AdobeCalloutMock.ASSET_ID, 0);
        Test.stopTest();

        // Then the PDF is stored against the statement and it is marked Ready
        Assert.areEqual(
                StatementGenerationService.Outcome.COMPLETED, result.outcome,
                'A finished job should complete the statement'
        );

        Household_Statement__c updated = getStatement();
        Assert.areEqual('Ready', updated.Status__c, 'The statement should now be Ready');
        Assert.isNotNull(updated.Document_URL__c, 'The document URL should point at the stored file');
        Assert.isNull(updated.Error_Detail__c, 'A successful run should clear any earlier error');

        List<ContentDocumentLink> files = [
                SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :statement.Id
        ];
        Assert.areEqual(1, files.size(), 'The generated PDF should be attached to the statement');
    }

    @IsTest
    static void theStoredFileIsNamedAfterTheHouseholdAndMonth() {
        // Given a statement for August already submitted to Adobe
        Household_Statement__c statement = getStatement();
        statement.Adobe_Job_URI__c = AdobeCalloutMock.JOB_PATH;
        update statement;

        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobCompletes());

        // When the finished document is stored
        Test.startTest();
        StatementGenerationService.advance(statement.Id, AdobeCalloutMock.ASSET_ID, 0);
        Test.stopTest();

        // Then the file reads as a month name rather than a month number
        ContentVersion stored = [
                SELECT Title FROM ContentVersion WHERE FirstPublishLocationId = :statement.Id LIMIT 1
        ];
        Assert.areEqual(
                'Generation Household Statement August', stored.Title,
                'The file should be named "<Household> Statement <Month>"'
        );
    }

    @IsTest
    static void aJobStillRunningLeavesTheStatementAloneAndAsksToBePolledAgain() {
        // Given a statement Adobe has not finished yet
        Household_Statement__c statement = getStatement();
        statement.Adobe_Job_URI__c = AdobeCalloutMock.JOB_PATH;
        statement.Status__c = 'Generating';
        update statement;

        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobIsStillRunning());

        // When the service polls it
        Test.startTest();
        StatementGenerationService.Result result =
                StatementGenerationService.advance(statement.Id, AdobeCalloutMock.ASSET_ID, 0);
        Test.stopTest();

        // Then nothing changes and the caller is told to come back
        Assert.areEqual(
                StatementGenerationService.Outcome.PENDING, result.outcome,
                'An unfinished job should stay pending'
        );

        Household_Statement__c updated = getStatement();
        Assert.areEqual('Generating', updated.Status__c, 'The status should be untouched while waiting');
        Assert.isNull(updated.Document_URL__c, 'No document should be stored yet');
    }

    @IsTest
    static void aJobAdobeReportsAsFailedMarksTheStatementFailed() {
        // Given a statement Adobe has given up on
        Household_Statement__c statement = getStatement();
        statement.Adobe_Job_URI__c = AdobeCalloutMock.JOB_PATH;
        update statement;

        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobFails());

        // When the service polls it
        Test.startTest();
        StatementGenerationService.Result result =
                StatementGenerationService.advance(statement.Id, AdobeCalloutMock.ASSET_ID, 0);
        Test.stopTest();

        // Then the reason is recorded and the job URI is cleared so a retry starts fresh
        Assert.areEqual(
                StatementGenerationService.Outcome.FAILED, result.outcome,
                'A failed job should fail the statement'
        );

        Household_Statement__c updated = getStatement();
        Assert.areEqual('Failed', updated.Status__c, 'The statement should be Failed');
        Assert.areEqual(
                'Adobe reported a failed job', updated.Error_Detail__c,
                'The reason should be readable on the record'
        );
        Assert.areEqual(1, updated.Retry_Count__c, 'The failure should be counted');
        Assert.isNull(
                updated.Adobe_Job_URI__c,
                'The dead job URI should be cleared so a retry submits a new job'
        );
    }

    @IsTest
    static void aStatementGivesUpAfterTooManyPolls() {
        // Given a statement that has already been polled the maximum number of times
        Household_Statement__c statement = getStatement();
        statement.Adobe_Job_URI__c = AdobeCalloutMock.JOB_PATH;
        update statement;

        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobIsStillRunning());

        // When it is polled once more
        Test.startTest();
        StatementGenerationService.Result result =
                StatementGenerationService.advance(statement.Id, AdobeCalloutMock.ASSET_ID, 30);
        Test.stopTest();

        // Then it stops waiting rather than polling forever
        Assert.areEqual(
                StatementGenerationService.Outcome.FAILED, result.outcome,
                'Polling should not continue indefinitely'
        );
        Assert.areEqual(
                'Timed out waiting for Adobe', getStatement().Error_Detail__c,
                'The record should say it timed out rather than that Adobe failed'
        );
    }

    @IsTest
    static void aCalloutFailureIsRecordedOnTheStatementRatherThanThrown() {
        // Given Adobe rejecting the credentials
        Household_Statement__c statement = getStatement();
        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.tokenIsRejected());

        // When the service advances it
        Test.startTest();
        StatementGenerationService.Result result =
                StatementGenerationService.advance(statement.Id, null, 0);
        Test.stopTest();

        // Then the run continues to the next statement instead of the exception escaping
        Assert.areEqual(
                StatementGenerationService.Outcome.FAILED, result.outcome,
                'A callout failure should fail this statement, not the whole run'
        );

        Household_Statement__c updated = getStatement();
        Assert.areEqual('Failed', updated.Status__c, 'The statement should be Failed');
        Assert.isTrue(
                updated.Error_Detail__c.contains('Token request failed'),
                'The cause should be readable on the record, was: ' + updated.Error_Detail__c
        );
    }

    @IsTest
    static void advancingAStatementThatNoLongerExistsThrows() {
        // Given a statement that has been deleted mid-run
        Household_Statement__c statement = getStatement();
        Id deletedId = statement.Id;
        delete statement;

        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobCompletes());

        // When the service tries to advance it
        Boolean threw = false;
        Test.startTest();
        try {
            StatementGenerationService.advance(deletedId, null, 0);
        } catch (StatementGenerationService.GenerationException e) {
            threw = true;
        }
        Test.stopTest();

        // Then it throws, because there is no record left to mark as failed
        Assert.isTrue(threw, 'A missing statement should throw rather than be silently skipped');
    }
}