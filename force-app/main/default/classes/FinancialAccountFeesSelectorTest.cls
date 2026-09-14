/**
 * @author: Gomolemo
 * @description: Covers FinancialAccountFeesSelector, including fees that straddle the period boundaries.
 * @date: 2026/09/13
 **/

@IsTest
private class FinancialAccountFeesSelectorTest {

    private static final Date PERIOD_START = Date.newInstance(2026, 8, 1);
    private static final Date PERIOD_END = Date.newInstance(2026, 8, 31);

    @IsTest
    static void selectForPeriodReturnsAFeeRunningThroughThePeriod() {
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Fee FA', '2020', 'Checking');
        StatementTestDataFactory.createFee(
                financialAccount.Id, 50, Date.newInstance(2026, 8, 10), Date.newInstance(2026, 8, 20)
        );

        List<FinancialAccountFee> results = new FinancialAccountFeesSelector()
                .selectForPeriod(new Set<Id>{ financialAccount.Id }, PERIOD_START, PERIOD_END);

        Assert.areEqual(1, results.size(), 'A fee wholly inside the period should be returned');
        Assert.areEqual(50, results[0].Amount, 'Amount should be in the selector field list');
    }

    @IsTest
    static void selectForPeriodReturnsAnOpenEndedFee() {
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Open Fee FA', '2021', 'Checking');
        StatementTestDataFactory.createFee(financialAccount.Id, 25, Date.newInstance(2026, 1, 1), null);

        List<FinancialAccountFee> results = new FinancialAccountFeesSelector()
                .selectForPeriod(new Set<Id>{ financialAccount.Id }, PERIOD_START, PERIOD_END);

        Assert.areEqual(1, results.size(), 'A fee with no end date is still in force during the period');
    }

    @IsTest
    static void selectForPeriodReturnsAFeeEndingPartWayThroughThePeriod() {
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Straddle FA', '2022', 'Checking');
        StatementTestDataFactory.createFee(
                financialAccount.Id, 30, Date.newInstance(2026, 7, 1), Date.newInstance(2026, 8, 15)
        );

        List<FinancialAccountFee> results = new FinancialAccountFeesSelector()
                .selectForPeriod(new Set<Id>{ financialAccount.Id }, PERIOD_START, PERIOD_END);

        Assert.areEqual(1, results.size(), 'A fee in force for part of the period counts');
    }

    @IsTest
    static void selectForPeriodExcludesFeesThatEndedBeforeOrStartedAfter() {
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Stale Fee FA', '2023', 'Checking');
        StatementTestDataFactory.createFee(
                financialAccount.Id, 5, Date.newInstance(2026, 6, 1), Date.newInstance(2026, 7, 31)
        );
        StatementTestDataFactory.createFee(
                financialAccount.Id, 5, Date.newInstance(2026, 9, 1), Date.newInstance(2026, 9, 30)
        );

        List<FinancialAccountFee> results = new FinancialAccountFeesSelector()
                .selectForPeriod(new Set<Id>{ financialAccount.Id }, PERIOD_START, PERIOD_END);

        Assert.isTrue(results.isEmpty(), 'Fees entirely outside the period should be excluded');
    }
}