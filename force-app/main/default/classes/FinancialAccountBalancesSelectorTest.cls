/**
 * @author: Gomolemo
 * @description: Covers FinancialAccountBalancesSelector, including the period boundaries and the newest-first
 *               ordering the closing balance depends on.
 * @date: 2026/09/13
 **/

@IsTest
private class FinancialAccountBalancesSelectorTest {

    private static final Date PERIOD_START = Date.newInstance(2026, 8, 1);
    private static final Date PERIOD_END = Date.newInstance(2026, 8, 31);

    @IsTest
    static void selectForPeriodReturnsBalancesInsideThePeriodNewestFirst() {
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Balance FA', '1010', 'Savings');
        StatementTestDataFactory.createBalance(
                financialAccount.Id, 100, Datetime.newInstance(2026, 8, 5, 0, 0, 0)
        );
        StatementTestDataFactory.createBalance(
                financialAccount.Id, 250, Datetime.newInstance(2026, 8, 20, 0, 0, 0)
        );

        List<FinancialAccountBalance> results = new FinancialAccountBalancesSelector()
                .selectForPeriod(new Set<Id>{ financialAccount.Id }, PERIOD_START, PERIOD_END);

        Assert.areEqual(2, results.size(), 'Both in-period snapshots should be returned');
        Assert.areEqual(
                250, results[0].Amount,
                'Newest first, so the first row is the closing balance for the period'
        );
    }

    @IsTest
    static void selectForPeriodIncludesTheLastDayOfThePeriod() {
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Edge FA', '1011', 'Savings');
        // Late on the final day: the period runs to midnight after its last day, so this is inside.
        StatementTestDataFactory.createBalance(
                financialAccount.Id, 75, Datetime.newInstance(2026, 8, 31, 23, 0, 0)
        );

        List<FinancialAccountBalance> results = new FinancialAccountBalancesSelector()
                .selectForPeriod(new Set<Id>{ financialAccount.Id }, PERIOD_START, PERIOD_END);

        Assert.areEqual(1, results.size(), 'A snapshot late on the last day is still inside the period');
    }

    @IsTest
    static void selectForPeriodExcludesBalancesOutsideThePeriod() {
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Outside FA', '1012', 'Savings');
        StatementTestDataFactory.createBalance(
                financialAccount.Id, 10, Datetime.newInstance(2026, 7, 31, 12, 0, 0)
        );
        StatementTestDataFactory.createBalance(
                financialAccount.Id, 20, Datetime.newInstance(2026, 9, 1, 0, 0, 0)
        );

        List<FinancialAccountBalance> results = new FinancialAccountBalancesSelector()
                .selectForPeriod(new Set<Id>{ financialAccount.Id }, PERIOD_START, PERIOD_END);

        Assert.isTrue(results.isEmpty(), 'Snapshots either side of the period should be excluded');
    }
}