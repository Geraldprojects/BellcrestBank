/**
 * @author: Gomolemo
 * @description: Covers StatementLinesSelector.
 * @date: 2026/09/13
 **/

@IsTest
private class StatementLinesSelectorTest {

    @TestSetup
    static void setup() {
        Account household = StatementTestDataFactory.createHousehold('Line Household');
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('FA Line', '2222', 'Checking');

        Household_Statement__c withLines = StatementTestDataFactory.createStatement(
                household.Id, 'LINE-1', Date.today().addDays(-30), Date.today(), 'Draft'
        );
        Household_Statement__c withoutLines = StatementTestDataFactory.createStatement(
                household.Id, 'LINE-2', Date.today().addDays(-60), Date.today().addDays(-31), 'Draft'
        );

        StatementTestDataFactory.createLine(withLines.Id, financialAccount.Id, 'LINE-1-A', 'Alpha', false);
        StatementTestDataFactory.createLine(withLines.Id, financialAccount.Id, 'LINE-1-B', 'Beta', true);
    }

    @IsTest
    static void selectByStatementIdReturnsOnlyThatStatementsLines() {
        Household_Statement__c withLines = [
                SELECT Id FROM Household_Statement__c WHERE Statement_Key__c = 'LINE-1'
        ];
        Household_Statement__c withoutLines = [
                SELECT Id FROM Household_Statement__c WHERE Statement_Key__c = 'LINE-2'
        ];
        StatementLinesSelector selector = new StatementLinesSelector();

        List<Statement_Line__c> lines = selector.selectByStatementId(new Set<Id>{ withLines.Id });
        List<Statement_Line__c> none = selector.selectByStatementId(new Set<Id>{ withoutLines.Id });

        Assert.areEqual(2, lines.size(), 'Both lines of that statement should be returned');
        Assert.isTrue(none.isEmpty(), 'A statement with no lines should return nothing');
    }

    @IsTest
    static void selectByStatementIdOrdersByAccountName() {
        Household_Statement__c statement = [
                SELECT Id FROM Household_Statement__c WHERE Statement_Key__c = 'LINE-1'
        ];

        List<Statement_Line__c> lines =
                new StatementLinesSelector().selectByStatementId(new Set<Id>{ statement.Id });

        Assert.areEqual('Alpha', lines[0].Financial_Account_Name__c, 'Lines should be ordered by account name');
        Assert.areEqual('Beta', lines[1].Financial_Account_Name__c, 'Lines should be ordered by account name');
    }

    @IsTest
    static void countAllCountsEveryLine() {
        Assert.areEqual(2, new StatementLinesSelector().countAll(), 'Both lines should be counted');
    }
}