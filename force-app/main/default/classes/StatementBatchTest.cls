/**
 * @author: Gomolemo
 * @description: Covers StatementBatch, which creates the period's statements and then hands them to
 *               StatementDocumentQueueable to generate.
 *
 *               The batch itself does very little: it iterates active households, asks StatementHelper
 *               to create their statements, and starts the generation run. These tests check that it
 *               selects the right households and creates the right statements.
 * @date: 2026/09/14
 **/

@IsTest
private class StatementBatchTest {

    private static final Date PERIOD_START = Date.newInstance(2026, 8, 1);
    private static final Date PERIOD_END = Date.newInstance(2026, 8, 31);

    /**
     * A household that will produce a statement needs the whole chain in place: a member contact, a
     * financial account, and a party linking the two. StatementService walks exactly that path.
     */
    private static Account createHouseholdThatHoldsAnAccount(String name, String accountNumber) {
        Account household = StatementTestDataFactory.createHousehold(name);
        StatementTestDataFactory.createMember(household.Id, 'Member');
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount(name + ' FA', accountNumber, 'Savings');
        StatementTestDataFactory.createParty(financialAccount.Id, household.Id, 'Owner');
        return household;
    }

    @IsTest
    static void aStatementIsCreatedForEachActiveHousehold() {
        // Given two active households, each holding one financial account
        Account first = createHouseholdThatHoldsAnAccount('Batch One', '5010');
        Account second = createHouseholdThatHoldsAnAccount('Batch Two', '5020');
        StatementTestDataFactory.createRelationshipGroup(first.Id, 'Group One', 'Household', 'Active');
        StatementTestDataFactory.createRelationshipGroup(second.Id, 'Group Two', 'Household', 'Active');

        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobCompletes());

        // When the batch runs for the period
        Test.startTest();
        Database.executeBatch(new StatementBatch(PERIOD_START, PERIOD_END), 200);
        Test.stopTest();

        // Then each household has a statement for that period
        List<Household_Statement__c> statements = [
                SELECT Household__c FROM Household_Statement__c WHERE Period_End__c = :PERIOD_END
        ];
        Assert.areEqual(2, statements.size(), 'Each active household should get a statement');

        Set<Id> households = new Set<Id>();
        for (Household_Statement__c statement : statements) {
            households.add(statement.Household__c);
        }
        Assert.isTrue(households.contains(first.Id), 'The first household should have a statement');
        Assert.isTrue(households.contains(second.Id), 'The second household should have a statement');
    }

    @IsTest
    static void aHouseholdThatIsNotActiveIsSkipped() {
        // Given one active household and one that is not
        Account active = createHouseholdThatHoldsAnAccount('Batch Active', '5030');
        Account inactive = createHouseholdThatHoldsAnAccount('Batch Inactive', '5040');
        StatementTestDataFactory.createRelationshipGroup(active.Id, 'Active Group', 'Household', 'Active');
        StatementTestDataFactory.createRelationshipGroup(inactive.Id, 'Closed Group', 'Household', 'Inactive');

        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobCompletes());

        // When the batch runs
        Test.startTest();
        Database.executeBatch(new StatementBatch(PERIOD_START, PERIOD_END), 200);
        Test.stopTest();

        // Then only the active household is billed
        List<Household_Statement__c> statements = [SELECT Household__c FROM Household_Statement__c];
        Assert.areEqual(1, statements.size(), 'Only the active household should get a statement');
        Assert.areEqual(active.Id, statements[0].Household__c, 'It should be the active household');
    }

    @IsTest
    static void aRelationshipGroupThatIsNotAHouseholdIsSkipped() {
        // Given a group of some other type
        Account other = createHouseholdThatHoldsAnAccount('Batch Other', '5050');
        StatementTestDataFactory.createRelationshipGroup(other.Id, 'Other Group', 'Group', 'Active');

        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobCompletes());

        // When the batch runs
        Test.startTest();
        Database.executeBatch(new StatementBatch(PERIOD_START, PERIOD_END), 200);
        Test.stopTest();

        // Then nothing is created, because the batch only bills households
        Assert.areEqual(
                0, [SELECT COUNT() FROM Household_Statement__c],
                'Only groups of type Household should produce statements'
        );
    }

    @IsTest
    static void statementLinesAreCreatedForTheAccountsAHouseholdHolds() {
        // Given an active household holding one financial account
        Account household = createHouseholdThatHoldsAnAccount('Batch Lines', '5060');
        StatementTestDataFactory.createRelationshipGroup(household.Id, 'Lines Group', 'Household', 'Active');

        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobCompletes());

        // When the batch runs
        Test.startTest();
        Database.executeBatch(new StatementBatch(PERIOD_START, PERIOD_END), 200);
        Test.stopTest();

        // Then the account appears as a line beneath the statement
        List<Statement_Line__c> lines = [
                SELECT Financial_Account_Name__c, Financial_Account_Type__c FROM Statement_Line__c
        ];
        Assert.areEqual(1, lines.size(), 'The held account should appear as a statement line');
        Assert.areEqual(
                'Batch Lines FA', lines[0].Financial_Account_Name__c,
                'The account name should be frozen onto the line'
        );
    }

    @IsTest
    static void aFailedChunkIsRolledBackAndItsHouseholdsKeptForRetry() {
        // Given an active household whose chunk will fail
        Account household = createHouseholdThatHoldsAnAccount('Batch Failure', '5070');
        PartyRelationshipGroup relationshipGroup = StatementTestDataFactory.createRelationshipGroup(
                household.Id, 'Failure Group', 'Household', 'Active'
        );
        StatementBatch.simulateFailure = true;
        StatementBatch batch = new StatementBatch(PERIOD_START, PERIOD_END);

        // When the chunk runs
        Test.startTest();
        batch.execute(null, [SELECT Id, AccountId FROM PartyRelationshipGroup WHERE Id = :relationshipGroup.Id]);
        Test.stopTest();

        // Then nothing is left half-written, and the household is remembered for the retry
        Assert.areEqual(
                0, [SELECT COUNT() FROM Household_Statement__c],
                'A failed chunk should leave no statements behind'
        );
        Assert.isTrue(
                batch.failedRelationshipGroupIds.contains(relationshipGroup.Id),
                'The failed household should be kept for the retry'
        );
    }

    @IsTest
    static void aRetryOnlyProcessesTheHouseholdsThatFailed() {
        // Given two active households, only one of which failed
        Account failed = createHouseholdThatHoldsAnAccount('Batch Retry', '5080');
        Account succeeded = createHouseholdThatHoldsAnAccount('Batch Done', '5090');
        PartyRelationshipGroup failedGroup = StatementTestDataFactory.createRelationshipGroup(
                failed.Id, 'Retry Group', 'Household', 'Active'
        );
        StatementTestDataFactory.createRelationshipGroup(succeeded.Id, 'Done Group', 'Household', 'Active');

        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobCompletes());

        // When the retry runs for the failed household
        Test.startTest();
        Database.executeBatch(
                new StatementBatch(PERIOD_START, PERIOD_END, new Set<Id>{ failedGroup.Id }, 2), 1
        );
        Test.stopTest();

        // Then only that household is reprocessed
        List<Household_Statement__c> statements = [SELECT Household__c FROM Household_Statement__c];
        Assert.areEqual(1, statements.size(), 'Only the failed household should be retried');
        Assert.areEqual(failed.Id, statements[0].Household__c, 'It should be the failed household');
    }

    @IsTest
    static void anOrgWithNoActiveHouseholdsCreatesNothing() {
        // Given no relationship groups at all
        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobCompletes());

        // When the batch runs
        Test.startTest();
        Database.executeBatch(new StatementBatch(PERIOD_START, PERIOD_END), 200);
        Test.stopTest();

        // Then it finishes quietly rather than failing on an empty run
        Assert.areEqual(
                0, [SELECT COUNT() FROM Household_Statement__c],
                'An empty run should create no statements'
        );
    }
}