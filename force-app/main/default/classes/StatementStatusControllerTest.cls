/**
 * @author: Gomolemo
 * @description: Covers StatementStatusController, the wire behind the statementGenerationStatus tile.
 *
 *               Every field the component renders is asserted individually. A selector field list that
 *               stops returning one of them fails at runtime rather than at compile time, so the only
 *               thing standing between that and the page is a test that reads each one.
 * @date: 2026/09/13
 **/

@IsTest
private class StatementStatusControllerTest {

    @TestSetup
    static void setup() {
        Account household = StatementTestDataFactory.createHousehold('Status Household');
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Status FA', '4242', 'Savings');

        Household_Statement__c older = StatementTestDataFactory.createStatement(
                household.Id, 'STATUS-OLD', Date.newInstance(2026, 6, 1), Date.newInstance(2026, 6, 30), 'Ready'
        );
        Household_Statement__c current = StatementTestDataFactory.createStatement(
                household.Id, 'STATUS-NEW', Date.newInstance(2026, 7, 1), Date.newInstance(2026, 7, 31), 'Generating'
        );

        StatementTestDataFactory.createLine(current.Id, financialAccount.Id, 'STATUS-NEW-1', 'Alpha', true);
        StatementTestDataFactory.createLine(current.Id, financialAccount.Id, 'STATUS-NEW-2', 'Beta', false);
        StatementTestDataFactory.createLine(older.Id, financialAccount.Id, 'STATUS-OLD-1', 'Gamma', false);
    }

    @IsTest
    static void everyFieldTheTileRendersIsPopulated() {
        Account household = [SELECT Id FROM Account WHERE Name = 'Status Household'];

        StatementStatusController.CycleStatus cycle = StatementStatusController.getCurrentCycle(household.Id);

        Assert.isNotNull(cycle, 'A household with statements should return a cycle');
        Assert.isNotNull(cycle.statementId, 'statementId is used to match incoming platform events');
        Assert.areEqual('Generating', cycle.status, 'status drives the badge');
        Assert.areEqual(Date.newInstance(2026, 7, 1), cycle.periodStart, 'periodStart is shown as the cycle');
        Assert.areEqual(Date.newInstance(2026, 7, 31), cycle.periodEnd, 'periodEnd is shown as the cycle');
        Assert.areEqual(2, cycle.accountCount, 'accountCount comes from the line subselect');
        Assert.isNotNull(cycle.totalBalance, 'totalBalance is shown on the tile');
        Assert.isNotNull(cycle.totalFees, 'totalFees is shown on the tile');
        Assert.areEqual(0, cycle.retryCount, 'retryCount is shown when a statement has failed before');
        // Regression guard: this was dropped from the selector field list and only surfaced on the page.
        Assert.isNotNull(cycle.lastUpdated, 'lastUpdated is rendered as "Updated" and must be selected');
    }

    @IsTest
    static void currentCycleIsTheLatestPeriodNotTheLatestCreated() {
        Account household = [SELECT Id FROM Account WHERE Name = 'Status Household'];

        StatementStatusController.CycleStatus cycle = StatementStatusController.getCurrentCycle(household.Id);

        Assert.areEqual(
                Date.newInstance(2026, 7, 31), cycle.periodEnd,
                'The cycle with the latest period end is the current one'
        );
    }

    @IsTest
    static void aReadyStatementCarriesItsDocumentAndNoError() {
        Account household = [SELECT Id FROM Account WHERE Name = 'Status Household'];
        Household_Statement__c current = [
                SELECT Id FROM Household_Statement__c WHERE Statement_Key__c = 'STATUS-NEW'
        ];
        current.Status__c = 'Ready';
        current.Document_URL__c = 'https://example.com/statement';
        update current;

        StatementStatusController.CycleStatus cycle = StatementStatusController.getCurrentCycle(household.Id);

        Assert.areEqual('Ready', cycle.status, 'The tile should reflect the stored status');
        Assert.areEqual(
                'https://example.com/statement', cycle.documentUrl,
                'documentUrl is what the View statement link points at'
        );
        Assert.isNull(cycle.errorDetail, 'A ready statement has no error to show');
    }

    @IsTest
    static void aFailedStatementCarriesItsReasonAndRetryCount() {
        Account household = [SELECT Id FROM Account WHERE Name = 'Status Household'];
        Household_Statement__c current = [
                SELECT Id FROM Household_Statement__c WHERE Statement_Key__c = 'STATUS-NEW'
        ];
        current.Status__c = 'Failed';
        current.Error_Detail__c = 'Adobe reported a failed job';
        current.Retry_Count__c = 2;
        update current;

        StatementStatusController.CycleStatus cycle = StatementStatusController.getCurrentCycle(household.Id);

        Assert.areEqual('Failed', cycle.status, 'The tile should reflect the stored status');
        Assert.areEqual(
                'Adobe reported a failed job', cycle.errorDetail,
                'errorDetail is rendered in the failure panel'
        );
        Assert.areEqual(2, cycle.retryCount, 'retryCount is rendered alongside the failure');
    }

    @IsTest
    static void aHouseholdWithoutStatementsReturnsNull() {
        Account other = StatementTestDataFactory.createHousehold('No Cycle Household');

        Assert.isNull(
                StatementStatusController.getCurrentCycle(other.Id),
                'The component renders its empty state from a null cycle'
        );
    }

    @IsTest
    static void aNullHouseholdIdReturnsNull() {
        // The wire fires before recordId is set on first render, so this must not throw.
        Assert.isNull(StatementStatusController.getCurrentCycle(null), 'A null household id should return null');
    }
}