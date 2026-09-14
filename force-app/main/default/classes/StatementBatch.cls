/**
 * @author: Gomolemo
 * @description: Creates periodic statements for the financial accounts of every active household.
 * @date: 2026/09/11
 **/

public with sharing class StatementBatch implements Database.Batchable<SObject> {

    private static final String LOG_TAG = 'Statement Batch';

    private Date periodStart;
    private Date periodEnd;

    public StatementBatch(Date periodStart, Date periodEnd) {
        this.periodStart = periodStart;
        this.periodEnd = periodEnd;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return new PartyRelationshipGroupsSelector().selectActiveHouseholdsLocator();
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

        try {
            List<Household_Statement__c> created = StatementHelper.createStatements(
                    StatementService.getFinancialAccountIdsByHousehold(householdIds), periodStart, periodEnd
            );
            Nebula.Logger.info(
                    'Created ' + created.size() + ' statement(s) from ' + householdIds.size() + ' household(s)'
            ).addTag(LOG_TAG);
        } catch (Exception e) {
            // A batch chunk that throws is retried and then abandoned, taking the reason with it.
            Nebula.Logger.error('Statement creation failed for ' + householdIds.size() + ' household(s)', e)
                    .addTag(LOG_TAG);
            Nebula.Logger.saveLog();
            throw e;
        }

        Nebula.Logger.saveLog();
    }

    public void finish(Database.BatchableContext context) {
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
}