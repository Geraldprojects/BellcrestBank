/**
 * @author: Gomolemo
 * @description: Covers StatementBatchScheduler.
 *
 *               The period arithmetic gets the most attention here, because it is the part that is
 *               easy to get subtly wrong and hard to notice: a scheduled job that bills the wrong
 *               month still runs, still succeeds, and still produces statements.
 * @date: 2026/09/14
 **/

@IsTest
private class StatementBatchSchedulerTest {

    @IsTest
    static void aScheduledRunBillsTheMonthThatHasJustClosed() {
        // Given the default scheduler, which decides its own period
        StatementBatchScheduler scheduler = new StatementBatchScheduler();
        Date lastMonth = Date.today().addMonths(-1);

        // When the period is worked out
        Date periodStart = scheduler.billingPeriodStart();
        Date periodEnd = scheduler.billingPeriodEnd();

        // Then it covers the whole of the previous calendar month
        Assert.areEqual(
                Date.newInstance(lastMonth.year(), lastMonth.month(), 1), periodStart,
                'The period should start on the first of last month'
        );
        Assert.areEqual(lastMonth.month(), periodEnd.month(), 'The period should end in that same month');
        Assert.areEqual(
                periodStart.addMonths(1).addDays(-1), periodEnd,
                'The period should end on the last day of that month'
        );
    }

    @IsTest
    static void thePeriodEndLandsOnTheRealLastDayOfTheMonth() {
        // Given a scheduler asked for February in a leap year
        StatementBatchScheduler scheduler = new StatementBatchScheduler(
                Date.newInstance(2028, 2, 1), null
        );

        // When the period end is worked out
        Date periodEnd = scheduler.billingPeriodEnd();

        // Then month length and leap years are handled by the date arithmetic, not by a lookup table
        Assert.areEqual(
                Date.newInstance(2028, 2, 29), periodEnd,
                'February 2028 is a leap year and ends on the 29th'
        );
    }

    @IsTest
    static void aRequestedPeriodIsUsedInsteadOfTheDefault() {
        // Given a scheduler asked for a specific historical period
        StatementBatchScheduler scheduler = new StatementBatchScheduler(
                Date.newInstance(2026, 3, 1), Date.newInstance(2026, 3, 31)
        );

        // When the period is worked out
        // Then the requested dates win, so a missed month can be backfilled
        Assert.areEqual(
                Date.newInstance(2026, 3, 1), scheduler.billingPeriodStart(),
                'A requested start should be used as given'
        );
        Assert.areEqual(
                Date.newInstance(2026, 3, 31), scheduler.billingPeriodEnd(),
                'A requested end should be used as given'
        );
    }

    @IsTest
    static void schedulingRegistersARecurringMonthlyJob() {
        // When the monthly job is scheduled
        Test.startTest();
        String jobId = StatementBatchScheduler.scheduleMonthly();
        Test.stopTest();

        // Then it is registered to fire at 02:00 on the first of each month
        CronTrigger job = [
                SELECT CronExpression, TimesTriggered, CronJobDetail.Name
                FROM CronTrigger
                WHERE Id = :jobId
        ];
        Assert.areEqual('0 0 2 1 * ?', job.CronExpression, 'It should run monthly on the 1st at 02:00');
        Assert.areEqual(0, job.TimesTriggered, 'It should not have fired yet');
        Assert.areEqual(
                'Monthly Household Statements', job.CronJobDetail.Name,
                'The job should be named so it can be found in Setup'
        );
    }

    @IsTest
    static void firingTheJobStartsAStatementRun() {
        // Given an active household holding one financial account, for last month
        Account household = StatementTestDataFactory.createHousehold('Scheduled Household');
        StatementTestDataFactory.createMember(household.Id, 'Member');
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Scheduled FA', '4010', 'Savings');
        StatementTestDataFactory.createParty(financialAccount.Id, household.Id, 'Owner');
        StatementTestDataFactory.createRelationshipGroup(
                household.Id, 'Scheduled Group', 'Household', 'Active'
        );

        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobCompletes());

        // When the scheduled job fires
        Test.startTest();
        new StatementBatchScheduler().execute(null);
        Test.stopTest();

        // Then the batch ran and produced a statement for the billed period
        Date lastMonth = Date.today().addMonths(-1);
        List<Household_Statement__c> statements = [
                SELECT Period_Start__c, Period_End__c FROM Household_Statement__c
        ];
        Assert.areEqual(1, statements.size(), 'The scheduled run should create the household a statement');
        Assert.areEqual(
                lastMonth.month(), statements[0].Period_Start__c.month(),
                'It should be billed for the month that just closed'
        );
    }
}