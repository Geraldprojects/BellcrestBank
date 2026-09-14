/**
 * @author: Gomolemo
 * @description: Covers StatementService, which resolves households to their financial accounts and
 *               those accounts to the balances and fees that belong to a statement period.
 * @date: 2026/09/13
 **/

@IsTest
private class StatementServiceTest {

    private static final Date PERIOD_START = Date.newInstance(2026, 8, 1);
    private static final Date PERIOD_END = Date.newInstance(2026, 8, 31);

    @IsTest
    static void aHouseholdResolvesToTheAccountsItsMembersHold() {
        // Given a household whose member holds one financial account
        Account household = StatementTestDataFactory.createHousehold('Service Household');
        Contact member = StatementTestDataFactory.createMember(household.Id, 'Holder');
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Member FA', '8010', 'Savings');
        StatementTestDataFactory.createParty(financialAccount.Id, household.Id, 'Owner');

        // When the household's accounts are resolved
        Test.startTest();
        Map<Id, Set<Id>> byHousehold =
                StatementService.getFinancialAccountIdsByHousehold(new Set<Id>{ household.Id });
        Test.stopTest();

        // Then the account is attributed to that household
        Assert.isTrue(byHousehold.containsKey(household.Id), 'The household should be in the result');
        Assert.areEqual(
                1, byHousehold.get(household.Id).size(),
                'The member\'s financial account should be attributed to the household'
        );
    }

    @IsTest
    static void aHouseholdWithNoMembersResolvesToNoAccounts() {
        // Given a household with nobody in it
        Account household = StatementTestDataFactory.createHousehold('Empty Service Household');

        // When its accounts are resolved
        Test.startTest();
        Map<Id, Set<Id>> byHousehold =
                StatementService.getFinancialAccountIdsByHousehold(new Set<Id>{ household.Id });
        Test.stopTest();

        // Then it is still present, just with nothing in it
        Assert.isTrue(byHousehold.containsKey(household.Id), 'Every requested household should be keyed');
        Assert.isTrue(byHousehold.get(household.Id).isEmpty(), 'An empty household holds no accounts');
    }

    @IsTest
    static void theClosingBalanceIsTheLatestSnapshotInsideThePeriod() {
        // Given two snapshots inside the period
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Balance Service FA', '8020', 'Savings');
        StatementTestDataFactory.createBalance(financialAccount.Id, 100, Datetime.newInstance(2026, 8, 5, 0, 0, 0));
        StatementTestDataFactory.createBalance(financialAccount.Id, 250, Datetime.newInstance(2026, 8, 25, 0, 0, 0));

        // When the closing balance is resolved
        Test.startTest();
        Map<Id, FinancialAccountBalance> balances = StatementService.getClosingBalanceByFinancialAccount(
                new Set<Id>{ financialAccount.Id }, PERIOD_START, PERIOD_END
        );
        Test.stopTest();

        // Then the most recent one wins
        Assert.areEqual(
                250, balances.get(financialAccount.Id).Amount,
                'The latest snapshot in the period is the closing balance'
        );
    }

    @IsTest
    static void anAccountWithNoSnapshotInThePeriodHasNoClosingBalance() {
        // Given a snapshot that falls before the period
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Stale Balance FA', '8021', 'Savings');
        StatementTestDataFactory.createBalance(financialAccount.Id, 100, Datetime.newInstance(2026, 7, 1, 0, 0, 0));

        // When the closing balance is resolved
        Test.startTest();
        Map<Id, FinancialAccountBalance> balances = StatementService.getClosingBalanceByFinancialAccount(
                new Set<Id>{ financialAccount.Id }, PERIOD_START, PERIOD_END
        );
        Test.stopTest();

        // Then the account is absent, so the statement line shows a gap rather than stale data
        Assert.isFalse(
                balances.containsKey(financialAccount.Id),
                'An account with no in-period snapshot should have no closing balance'
        );
    }

    @IsTest
    static void feesInForceDuringThePeriodAreReturned() {
        // Given one fee inside the period and one that ended before it
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Fee Service FA', '8030', 'Checking');
        StatementTestDataFactory.createFee(
                financialAccount.Id, 40, Date.newInstance(2026, 8, 2), Date.newInstance(2026, 8, 9)
        );
        StatementTestDataFactory.createFee(
                financialAccount.Id, 99, Date.newInstance(2026, 6, 1), Date.newInstance(2026, 6, 30)
        );

        // When fees are resolved for the period
        Test.startTest();
        Map<Id, List<FinancialAccountFee>> fees = StatementService.getFeesByFinancialAccount(
                new Set<Id>{ financialAccount.Id }, PERIOD_START, PERIOD_END
        );
        Test.stopTest();

        // Then only the in-period fee is included
        Assert.areEqual(1, fees.get(financialAccount.Id).size(), 'Only the in-period fee should be returned');
        Assert.areEqual(40, fees.get(financialAccount.Id)[0].Amount, 'It should be the in-period fee');
    }
}