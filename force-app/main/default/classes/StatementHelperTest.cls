/**
 * @author: Gomolemo
 * @description: Covers StatementHelper, which creates a statement per household and freezes a line per
 *               financial account.
 *
 *               "Frozen" is the point of this class: name, number, type and joint ownership are copied
 *               onto the line at creation, so a later rename or change of owners cannot alter a
 *               statement that has already been issued.
 * @date: 2026/09/13
 **/

@IsTest
private class StatementHelperTest {

    private static final Date PERIOD_START = Date.newInstance(2026, 8, 1);
    private static final Date PERIOD_END = Date.newInstance(2026, 8, 31);

    @IsTest
    static void aStatementIsCreatedPerHouseholdWithALinePerAccount() {
        // Given a household holding one financial account
        Account household = StatementTestDataFactory.createHousehold('Helper Household');
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Helper FA', '9010', 'Savings');
        StatementTestDataFactory.createParty(financialAccount.Id, household.Id, 'Owner');

        // When statements are created for the period
        Test.startTest();
        List<Household_Statement__c> created = StatementHelper.createStatements(
                new Map<Id, Set<Id>>{ household.Id => new Set<Id>{ financialAccount.Id } },
                PERIOD_START, PERIOD_END
        );
        Test.stopTest();

        // Then one statement exists, with one line on it
        Assert.areEqual(1, created.size(), 'One household should produce one statement');

        List<Statement_Line__c> lines = [
                SELECT Financial_Account_Name__c, Financial_Account_Number__c, Financial_Account_Type__c
                FROM Statement_Line__c
        ];
        Assert.areEqual(1, lines.size(), 'One account should produce one line');
        Assert.areEqual('Helper FA', lines[0].Financial_Account_Name__c, 'The name should be copied onto the line');
        Assert.areEqual('9010', lines[0].Financial_Account_Number__c, 'The number should be copied onto the line');
        Assert.areEqual('Savings', lines[0].Financial_Account_Type__c, 'The type should be copied onto the line');
    }

    @IsTest
    static void anAccountWithTwoOwnersIsFrozenOntoItsLineAsJoint() {
        // Given an account held by an owner and a co-owner
        Account household = StatementTestDataFactory.createHousehold('Joint Helper Household');
        Account partner = StatementTestDataFactory.createHousehold('Joint Helper Partner');
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Joint Helper FA', '9020', 'Investment Account');
        StatementTestDataFactory.createParty(financialAccount.Id, household.Id, 'Owner');
        StatementTestDataFactory.createParty(financialAccount.Id, partner.Id, 'Co-Owner');

        // When statements are created
        Test.startTest();
        StatementHelper.createStatements(
                new Map<Id, Set<Id>>{ household.Id => new Set<Id>{ financialAccount.Id } },
                PERIOD_START, PERIOD_END
        );
        Test.stopTest();

        // Then the line records it as joint
        Assert.isTrue([SELECT Is_Joint__c FROM Statement_Line__c].Is_Joint__c, 'Two owners means a joint account');
    }

    @IsTest
    static void totalsAreSummedFromTheLines() {
        // Given an account with a closing balance and a fee inside the period
        Account household = StatementTestDataFactory.createHousehold('Totals Household');
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Totals FA', '9030', 'Savings');
        StatementTestDataFactory.createParty(financialAccount.Id, household.Id, 'Owner');
        StatementTestDataFactory.createBalance(financialAccount.Id, 500, Datetime.newInstance(2026, 8, 10, 0, 0, 0));
        StatementTestDataFactory.createFee(financialAccount.Id, 25, Date.newInstance(2026, 8, 2), null);

        // When statements are created
        Test.startTest();
        StatementHelper.createStatements(
                new Map<Id, Set<Id>>{ household.Id => new Set<Id>{ financialAccount.Id } },
                PERIOD_START, PERIOD_END
        );
        Test.stopTest();

        // Then the header totals match the lines beneath it
        Household_Statement__c statement = [SELECT Total_Balance__c, Total_Fees__c FROM Household_Statement__c];
        Assert.areEqual(500, statement.Total_Balance__c, 'The balance should be summed onto the statement');
        Assert.areEqual(25, statement.Total_Fees__c, 'The fees should be summed onto the statement');
    }

    @IsTest
    static void anAccountWithNoSnapshotLeavesItsBalanceEmptyRatherThanZero() {
        // Given an account with no balance snapshot in the period
        Account household = StatementTestDataFactory.createHousehold('Gap Household');
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Gap FA', '9040', 'Savings');
        StatementTestDataFactory.createParty(financialAccount.Id, household.Id, 'Owner');

        // When statements are created
        Test.startTest();
        StatementHelper.createStatements(
                new Map<Id, Set<Id>>{ household.Id => new Set<Id>{ financialAccount.Id } },
                PERIOD_START, PERIOD_END
        );
        Test.stopTest();

        // Then the gap stays visible instead of being filled with a misleading zero
        Assert.isNull(
                [SELECT Closing_Balance__c FROM Statement_Line__c].Closing_Balance__c,
                'A missing snapshot should leave the balance empty, not zero'
        );
    }

    @IsTest
    static void rerunningAPeriodUpdatesTheSameStatementInsteadOfDuplicatingIt() {
        // Given a period that has already been run once
        Account household = StatementTestDataFactory.createHousehold('Rerun Household');
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Rerun FA', '9050', 'Savings');
        StatementTestDataFactory.createParty(financialAccount.Id, household.Id, 'Owner');

        Map<Id, Set<Id>> input =
                new Map<Id, Set<Id>>{ household.Id => new Set<Id>{ financialAccount.Id } };
        StatementHelper.createStatements(input, PERIOD_START, PERIOD_END);

        // When the same period is run again
        Test.startTest();
        StatementHelper.createStatements(input, PERIOD_START, PERIOD_END);
        Test.stopTest();

        // Then the existing records are updated, because both are keyed on an external id
        Assert.areEqual(1, [SELECT COUNT() FROM Household_Statement__c], 'Rerunning should not duplicate statements');
        Assert.areEqual(1, [SELECT COUNT() FROM Statement_Line__c], 'Rerunning should not duplicate lines');
    }
}