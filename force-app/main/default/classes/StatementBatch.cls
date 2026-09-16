/**
 * @author: Gomolemo
 * @description: Creates periodic statements for the financial accounts of every active household.
 *
 *               A chunk that fails is rolled back and its households are remembered rather than lost. When
 *               the run finishes, the batch is started again for just those households, one per chunk so a
 *               single bad household can't sink the rest, up to MAX_ATTEMPTS in total. Statement creation
 *               upserts on its keys, so reprocessing a household is safe.
 * @date: 2026/09/11
 **/

public with sharing class StatementBatch implements Database.Batchable<SObject>, Database.Stateful {

    private static final String LOG_TAG = 'Statement Batch';

    @TestVisible
    private static final Integer MAX_ATTEMPTS = 3;
    private static final Integer RETRY_BATCH_SIZE = 1;

    // Lets a test force a chunk to fail, since real failures are hard to arrange.
    @TestVisible
    private static Boolean simulateFailure = false;

    private Date periodStart;
    private Date periodEnd;

    // Null on the first attempt, which means every active household.
    private Set<Id> relationshipGroupIds;
    private Integer attempt;

    // Carried across chunks by Database.Stateful.
    @TestVisible
    private Set<Id> failedRelationshipGroupIds = new Set<Id>();

    public StatementBatch(Date periodStart, Date periodEnd) {
        this(periodStart, periodEnd, null, 1);
    }

    @TestVisible
    private StatementBatch(Date periodStart, Date periodEnd, Set<Id> relationshipGroupIds, Integer attempt) {
        this.periodStart = periodStart;
        this.periodEnd = periodEnd;
        this.relationshipGroupIds = relationshipGroupIds;
        this.attempt = attempt;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        PartyRelationshipGroupsSelector selector = new PartyRelationshipGroupsSelector();

        // A retry only revisits the households that failed on the previous attempt.
        if (isRetry()) {
            return selector.selectActiveHouseholdsLocatorById(relationshipGroupIds);
        }
        return selector.selectActiveHouseholdsLocator();
    }

    private Boolean isRetry() {
        return relationshipGroupIds != null;
    }

    public void execute(Database.BatchableContext context, List<PartyRelationshipGroup> households) {
        Set<Id> householdIds = new Set<Id>();
        for (PartyRelationshipGroup household : households) {
            householdIds.add(household.AccountId);
        }

   /*     Set<Id> financialAccountIds = new Set<Id>();
        for (Set<Id> ids : StatementService.getFinancialAccountIdsByHousehold(householdIds).values()) {
            financialAccountIds.addAll(ids);
        }*/

        // Catching the exception stops the platform rolling the chunk back, so undo its partial work here.
        Savepoint savepoint = Database.setSavepoint();
        try {
            if (Test.isRunningTest() && simulateFailure) {
                throw new StatementBatchException('Simulated failure');
            }
            List<Household_Statement__c> created = StatementHelper.createStatements(
                    StatementService.getFinancialAccountIdsByHousehold(householdIds), periodStart, periodEnd
            );
            Nebula.Logger.info(
                    'Created ' + created.size() + ' statement(s) from ' + householdIds.size() + ' household(s)'
            ).addTag(LOG_TAG);
        } catch (Exception e) {
            Database.rollback(savepoint);
            for (PartyRelationshipGroup household : households) {
                failedRelationshipGroupIds.add(household.Id);
            }
            Nebula.Logger.error(
                    'Statement creation failed for ' + householdIds.size() + ' household(s) on attempt ' + attempt
                            + ' of ' + MAX_ATTEMPTS, e
            ).addTag(LOG_TAG);
        }

        Nebula.Logger.saveLog();
    }

    public void finish(Database.BatchableContext context) {
        if (!failedRelationshipGroupIds.isEmpty()) {
            if (attempt < MAX_ATTEMPTS) {
                Nebula.Logger.warn(
                        'Retrying ' + failedRelationshipGroupIds.size() + ' failed household(s), attempt '
                                + (attempt + 1) + ' of ' + MAX_ATTEMPTS
                ).addTag(LOG_TAG);
                Nebula.Logger.saveLog();

                // Documents wait for the final attempt, so drafts aren't queued once per retry.
                Database.executeBatch(
                        new StatementBatch(periodStart, periodEnd, failedRelationshipGroupIds, attempt + 1),
                        RETRY_BATCH_SIZE
                );
                return;
            }

            Nebula.Logger.error(
                    'Gave up on ' + failedRelationshipGroupIds.size() + ' household(s) after ' + MAX_ATTEMPTS
                            + ' attempts: ' + failedRelationshipGroupIds
            ).addTag(LOG_TAG);
        }

        List<Id> statementIds = new List<Id>(new Map<Id, Household_Statement__c>(
                new HouseholdStatementsSelector()
                        .selectByStatusAndPeriodEnd(new Set<String>{ 'Draft' }, periodEnd)
        ).keySet());

        if (statementIds.isEmpty()) {
            Nebula.Logger.warn('No draft statements for period ending ' + periodEnd + ' - nothing to generate')
                    .addTag(LOG_TAG);
        } else {
            StatementDocumentQueueable.start(statementIds);
            Nebula.Logger.info(
                    'Queued ' + statementIds.size() + ' statement(s) for period ' + periodStart + ' to ' + periodEnd
            ).addTag(LOG_TAG);
        }

        Nebula.Logger.saveLog();
    }

    public class StatementBatchException extends Exception {}
}
