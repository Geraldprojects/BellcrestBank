/**
 * @author: Gomolemo
 * @description: Covers StatementDocumentQueueable, which walks a list of statements through generation
 *               one transaction at a time.
 *
 *               The queueable holds no business logic - it asks StatementGenerationService what
 *               happened and decides only whether to poll the same statement again or move on to the
 *               next one. These tests therefore check orchestration, not generation.
 *
 *               The chain does run to completion inside Test.stopTest(), so these assert the state of
 *               the whole run rather than of a single step.
 * @date: 2026/09/13
 **/

@IsTest
private class StatementDocumentQueueableTest {

    @TestSetup
    static void setup() {
        Account household = StatementTestDataFactory.createHousehold('Queueable Household');
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Queue FA', '6010', 'Savings');

        Household_Statement__c first = StatementTestDataFactory.createStatement(
                household.Id, 'QUEUE-1', Date.newInstance(2026, 8, 1), Date.newInstance(2026, 8, 31), 'Draft'
        );
        Household_Statement__c second = StatementTestDataFactory.createStatement(
                household.Id, 'QUEUE-2', Date.newInstance(2026, 7, 1), Date.newInstance(2026, 7, 31), 'Draft'
        );

        StatementTestDataFactory.createLine(first.Id, financialAccount.Id, 'QUEUE-1-A', 'Queue FA', false);
        StatementTestDataFactory.createLine(second.Id, financialAccount.Id, 'QUEUE-2-A', 'Queue FA', false);
    }

    private static Household_Statement__c getStatement(String key) {
        return [
                SELECT Id, Status__c, Adobe_Job_URI__c, Document_URL__c, Retry_Count__c
                FROM Household_Statement__c
                WHERE Statement_Key__c = :key
        ];
    }

    @IsTest
    static void aRunGeneratesEveryStatementItIsGiven() {
        // Given two draft statements and Adobe completing every job
        List<Id> statementIds = new List<Id>{ getStatement('QUEUE-1').Id, getStatement('QUEUE-2').Id };
        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobCompletes());

        // When the run is started
        Test.startTest();
        StatementDocumentQueueable.start(statementIds);
        Test.stopTest();

        // Then both statements are generated, not just the first
        Assert.areEqual('Ready', getStatement('QUEUE-1').Status__c, 'The first statement should be Ready');
        Assert.areEqual('Ready', getStatement('QUEUE-2').Status__c, 'The run should move on to the second');
        Assert.areEqual(
                2, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId IN :statementIds],
                'Each statement should have its own stored PDF'
        );
    }

    @IsTest
    static void pollingAnAlreadySubmittedStatementStoresTheDocument() {
        // Given a statement already submitted to Adobe
        Household_Statement__c first = getStatement('QUEUE-1');
        first.Adobe_Job_URI__c = AdobeCalloutMock.JOB_PATH;
        first.Status__c = 'Generating';
        update first;

        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobCompletes());

        // When the queueable picks it up
        Test.startTest();
        StatementDocumentQueueable.start(new List<Id>{ first.Id });
        Test.stopTest();

        // Then it polls rather than resubmitting, and stores the finished document
        Household_Statement__c updated = getStatement('QUEUE-1');
        Assert.areEqual('Ready', updated.Status__c, 'A finished job should complete the statement');
        Assert.isNotNull(updated.Document_URL__c, 'The stored document should be linked from the record');
    }

    @IsTest
    static void anEmptyListOfStatementsDoesNothing() {
        // Given nothing to process
        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobCompletes());

        // When a run is started with an empty list
        Test.startTest();
        StatementDocumentQueueable.start(new List<Id>());
        Test.stopTest();

        // Then no statement is touched
        Assert.areEqual(
                2, [SELECT COUNT() FROM Household_Statement__c WHERE Status__c = 'Draft'],
                'Both statements should be left alone'
        );
    }

    @IsTest
    static void aFailingStatementDoesNotStopTheRestOfTheRun() {
        // Given Adobe rejecting the credentials, so every statement will fail
        List<Id> statementIds = new List<Id>{ getStatement('QUEUE-1').Id, getStatement('QUEUE-2').Id };
        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.tokenIsRejected());

        // When the run is started
        Test.startTest();
        StatementDocumentQueueable.start(statementIds);
        Test.stopTest();

        // Then the run carried on past the first failure and attempted the second as well,
        // which is the behaviour that keeps one bad statement from stranding the rest of a batch
        Assert.areEqual('Failed', getStatement('QUEUE-1').Status__c, 'The first statement should be Failed');
        Assert.areEqual(
                'Failed', getStatement('QUEUE-2').Status__c,
                'The second should have been attempted too, not abandoned'
        );
        Assert.areEqual(1, getStatement('QUEUE-2').Retry_Count__c, 'Its failure should be counted');
    }
}