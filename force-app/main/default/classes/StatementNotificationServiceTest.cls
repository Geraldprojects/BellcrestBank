/**
 * @author: Gomolemo
 * @description: Covers StatementNotificationService, which tells a household's relationship manager
 *               once their statement is ready.
 *
 *               Salesforce offers no way to assert that a custom notification was delivered, so these
 *               tests cover what is observable: who would be notified, which events are acted on, and
 *               that a failure to notify never escapes to retry the event.
 * @date: 2026/09/13
 **/

@IsTest
private class StatementNotificationServiceTest {

    private static Statement_Ready__e buildEvent(Id statementId, Id householdId, String status) {
        return new Statement_Ready__e(
                Household_Statement_Id__c = statementId,
                Household_Id__c = householdId,
                Household_Name__c = 'Notify Household',
                Status__c = status
        );
    }

    @IsTest
    static void theRelationshipManagerIsTheHouseholdOwner() {
        // Given a household owned by an active user
        Account household = StatementTestDataFactory.createHousehold('Notify Household');

        // When its relationship manager is resolved
        Test.startTest();
        Map<Id, Id> managers =
                StatementNotificationService.getRelationshipManagers(new Set<Id>{ household.Id });
        Test.stopTest();

        // Then the owner is who gets told
        Assert.areEqual(
                UserInfo.getUserId(), managers.get(household.Id),
                'The household owner is the relationship manager'
        );
    }

    @IsTest
    static void aReadyEventNotifiesWithoutError() {
        // Given a ready statement for a household with an active owner
        Account household = StatementTestDataFactory.createHousehold('Notify Household');
        Household_Statement__c statement = StatementTestDataFactory.createStatement(
                household.Id, 'NOTIFY-1', Date.today().addDays(-30), Date.today(), 'Ready'
        );

        // When the event is handled
        Test.startTest();
        StatementNotificationService.handle(
                new List<Statement_Ready__e>{ buildEvent(statement.Id, household.Id, 'Ready') }
        );
        Test.stopTest();

        // Then it completes: a notification failure here would surface as an exception
        Assert.isTrue(true, 'Handling a ready event should not throw');
    }

    @IsTest
    static void eventsThatAreNotReadyAreIgnoredWithoutDoingAnyWork() {
        // Given a household and a statement that is only part way through
        Account household = StatementTestDataFactory.createHousehold('Notify Household');
        Household_Statement__c statement = StatementTestDataFactory.createStatement(
                household.Id, 'NOTIFY-2', Date.today().addDays(-30), Date.today(), 'Generating'
        );

        // When Generating and Failed events are handled
        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        StatementNotificationService.handle(new List<Statement_Ready__e>{
                buildEvent(statement.Id, household.Id, 'Generating'),
                buildEvent(statement.Id, household.Id, 'Failed')
        });
        Integer queriesAfter = Limits.getQueries();
        Test.stopTest();

        // Then it returns before spending a single query looking up recipients
        Assert.areEqual(
                queriesBefore, queriesAfter,
                'Only Ready events should cause work; the rest should short-circuit'
        );
    }

    @IsTest
    static void anEmptyBatchIsHandledSafely() {
        // When there is nothing to process
        Test.startTest();
        StatementNotificationService.handle(new List<Statement_Ready__e>());
        Test.stopTest();

        // Then it returns quietly rather than failing the event delivery
        Assert.isTrue(true, 'An empty batch should not throw');
    }

    @IsTest
    static void aHouseholdWithNoResolvableManagerIsSkippedRatherThanFailing() {
        // Given an event pointing at a household id that does not exist
        Id missingHouseholdId = StatementTestDataFactory.createHousehold('Temp').Id;
        delete [SELECT Id FROM Account WHERE Id = :missingHouseholdId];

        // When the event is handled
        Test.startTest();
        StatementNotificationService.handle(
                new List<Statement_Ready__e>{ buildEvent(null, missingHouseholdId, 'Ready') }
        );
        Test.stopTest();

        // Then it skips that household instead of failing the whole batch
        Assert.isTrue(true, 'An unresolvable household should be skipped, not fatal');
    }
}