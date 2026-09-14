/**
 * @author: Gomolemo
 * @description: Runs StatementBatch on a schedule.
 *
 *               A scheduled job is serialized when it is scheduled and deserialized on every firing, so
 *               the period is worked out inside execute() rather than in the constructor. Computing it
 *               up front would freeze the dates at the moment of scheduling and bill the same month
 *               every time, forever.
 *
 *               Schedule it with:
 *                   StatementBatchScheduler.scheduleMonthly();
 * @date: 2026/09/14
 **/

public with sharing class StatementBatchScheduler implements Schedulable {

    private static final String LOG_TAG = 'Statement Schedule';
    private static final String JOB_NAME = 'Monthly Household Statements';

    // 02:00 on the first of every month, once the month being billed has closed.
    private static final String MONTHLY_CRON = '0 0 2 1 * ?';

    private static final Integer BATCH_SIZE = 200;

    // Both null on a scheduled run, which means "the month that has just closed, decided at run time".
    // Set only when a specific period is requested, for a one-off or a backfill.
    private final Date requestedStart;
    private final Date requestedEnd;

    /**
     * The normal, recurring case: bill whichever month has just closed when the job fires.
     */
    public StatementBatchScheduler() {
        this(null, null);
    }

    /**
     * A fixed period, for a one-off run or to backfill a month that was missed.
     */
    public StatementBatchScheduler(Date periodStart, Date periodEnd) {
        this.requestedStart = periodStart;
        this.requestedEnd = periodEnd;
    }

    /**
     * Starts the recurring monthly job and returns its id. Safe to call once; scheduling it a second
     * time under the same name throws, which is Salesforce telling you it is already running.
     */
    public static String scheduleMonthly() {
        return System.schedule(JOB_NAME, MONTHLY_CRON, new StatementBatchScheduler());
    }

    public void execute(SchedulableContext context) {
        Date periodStart = billingPeriodStart();
        Date periodEnd = billingPeriodEnd();

        Nebula.Logger.info(
                'Scheduled statement run starting for ' + periodStart + ' to ' + periodEnd
        ).addTag(LOG_TAG);
        Nebula.Logger.saveLog();

        Database.executeBatch(new StatementBatch(periodStart, periodEnd), BATCH_SIZE);
    }

    /**
     * The first day of the month before today, unless a specific period was requested.
     */
    @TestVisible
    private Date billingPeriodStart() {
        if (requestedStart != null) {
            return requestedStart;
        }
        Date lastMonth = Date.today().addMonths(-1);
        return Date.newInstance(lastMonth.year(), lastMonth.month(), 1);
    }

    /**
     * The last day of that same month. Derived by stepping forward a month and back a day, so month
     * lengths and leap years take care of themselves.
     */
    @TestVisible
    private Date billingPeriodEnd() {
        if (requestedEnd != null) {
            return requestedEnd;
        }
        return billingPeriodStart().addMonths(1).addDays(-1);
    }
}