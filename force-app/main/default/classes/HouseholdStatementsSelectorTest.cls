/**
 * @author: Gomolemo
 * @description: Covers HouseholdStatementsSelector, including the period ordering the status tile depends on.
 * @date: 2026/09/13
 **/

@IsTest
private class HouseholdStatementsSelectorTest {

    @TestSetup
    static void setup() {
        Account household = StatementTestDataFactory.createHousehold('Selector Household');
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('FA One', '1111', 'Savings');

        Household_Statement__c older = StatementTestDataFactory.createStatement(
                household.Id, 'KEY-OLD', Date.newInstance(2026, 6, 1), Date.newInstance(2026, 6, 30), 'Ready'
        );
        Household_Statement__c newer = StatementTestDataFactory.createStatement(
                household.Id, 'KEY-NEW', Date.newInstance(2026, 7, 1), Date.newInstance(2026, 7, 31), 'Draft'
        );

        StatementTestDataFactory.createLine(newer.Id, financialAccount.Id, 'KEY-NEW-1', 'FA One', true);
        StatementTestDataFactory.createLine(older.Id, financialAccount.Id, 'KEY-OLD-1', 'FA One', false);
    }

    @IsTest
    static void selectByIdReturnsRequestedStatements() {
        Set<Id> ids = new Map<Id, Household_Statement__c>([SELECT Id FROM Household_Statement__c]).keySet();

        List<Household_Statement__c> results = new HouseholdStatementsSelector().selectById(ids);

        Assert.areEqual(2, results.size(), 'Both statements should be returned');
        Assert.isNotNull(results[0].Status__c, 'Status should be in the selector field list');
        Assert.isNotNull(results[0].Statement_Key__c, 'Statement key should be in the selector field list');
    }

    @IsTest
    static void selectByIdWithHouseholdResolvesTheHouseholdName() {
        Set<Id> ids = new Map<Id, Household_Statement__c>([SELECT Id FROM Household_Statement__c]).keySet();

        List<Household_Statement__c> results = new HouseholdStatementsSelector().selectByIdWithHousehold(ids);

        Assert.areEqual(2, results.size(), 'Both statements should be returned');
        Assert.areEqual(
                'Selector Household', results[0].Household__r.Name,
                'The household name should be resolved through the lookup'
        );
    }

    @IsTest
    static void selectByIdWithLinesAttachesChildLines() {
        Household_Statement__c statement = [
                SELECT Id FROM Household_Statement__c WHERE Statement_Key__c = 'KEY-NEW'
        ];

        List<Household_Statement__c> results =
                new HouseholdStatementsSelector().selectByIdWithLines(new Set<Id>{ statement.Id });

        Assert.areEqual(1, results.size(), 'One statement was requested');
        Assert.areEqual(1, results[0].Statement_Lines__r.size(), 'Its line should come back in the subselect');
        Assert.isTrue(
                results[0].Statement_Lines__r[0].Is_Joint__c,
                'Line fields should come from the line selector field list'
        );
    }

    @IsTest
    static void selectCurrentCycleReturnsTheLatestPeriodNotTheLatestCreated() {
        Id householdId = [SELECT Id FROM Account LIMIT 1].Id;

        List<Household_Statement__c> results =
                new HouseholdStatementsSelector().selectCurrentCycleByHousehold(householdId);

        Assert.areEqual(1, results.size(), 'Only the current cycle should come back');
        Assert.areEqual(
                Date.newInstance(2026, 7, 31), results[0].Period_End__c,
                'The cycle with the latest period end is the current one'
        );
    }

    @IsTest
    static void selectCurrentCycleReturnsEmptyForAHouseholdWithoutStatements() {
        Account other = StatementTestDataFactory.createHousehold('No Statements');

        List<Household_Statement__c> results =
                new HouseholdStatementsSelector().selectCurrentCycleByHousehold(other.Id);

        Assert.isTrue(results.isEmpty(), 'A household with no statements should return nothing');
    }

    @IsTest
    static void selectByStatusAndPeriodEndFiltersOnBoth() {
        HouseholdStatementsSelector selector = new HouseholdStatementsSelector();

        List<Household_Statement__c> matching = selector.selectByStatusAndPeriodEnd(
                new Set<String>{ 'Draft' }, Date.newInstance(2026, 7, 31)
        );
        List<Household_Statement__c> wrongStatus = selector.selectByStatusAndPeriodEnd(
                new Set<String>{ 'Failed' }, Date.newInstance(2026, 7, 31)
        );
        List<Household_Statement__c> wrongPeriod = selector.selectByStatusAndPeriodEnd(
                new Set<String>{ 'Draft' }, Date.newInstance(2026, 6, 30)
        );

        Assert.areEqual(1, matching.size(), 'The draft statement for that period should match');
        Assert.isTrue(wrongStatus.isEmpty(), 'A status that matches nothing should return nothing');
        Assert.isTrue(wrongPeriod.isEmpty(), 'A period that holds no draft should return nothing');
    }

    @IsTest
    static void selectAllReturnsEveryStatement() {
        Assert.areEqual(2, new HouseholdStatementsSelector().selectAll().size(), 'Both statements should come back');
    }
}