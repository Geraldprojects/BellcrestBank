/**
 * @author: Gomolemo
 * @description: Supplies the current statement cycle's generation status for a household, backing the
 *               statementGenerationStatus LWC on the Household record page.
 * @date: 2026/09/13
 **/

public with sharing class StatementStatusController {

    /**
     * One statement cycle, flattened for the component. Status is returned as the stored picklist value;
     * how it is labelled and coloured is the component's business, not this class's.
     */
    public class CycleStatus {
        @AuraEnabled public Id statementId;
        @AuraEnabled public String status;
        @AuraEnabled public Date periodStart;
        @AuraEnabled public Date periodEnd;
        @AuraEnabled public String documentUrl;
        @AuraEnabled public String errorDetail;
        @AuraEnabled public Integer retryCount;
        @AuraEnabled public Integer accountCount;
        @AuraEnabled public Decimal totalBalance;
        @AuraEnabled public Decimal totalFees;
        @AuraEnabled public Datetime lastUpdated;
    }

    /**
     * Returns the household's most recent statement cycle, or null when none has been created yet.
     * Ordered by period end rather than created date, so backfilling an older cycle doesn't displace
     * the current one on the page.
     */
    @AuraEnabled(cacheable=true)
    public static CycleStatus getCurrentCycle(Id householdId) {
        if (householdId == null) {
            return null;
        }

        List<Household_Statement__c> statements =
                new HouseholdStatementsSelector().selectCurrentCycleByHousehold(householdId);

        if (statements.isEmpty()) {
            return null;
        }

        Household_Statement__c statement = statements[0];

        CycleStatus cycle = new CycleStatus();
        cycle.statementId = statement.Id;
        cycle.status = statement.Status__c;
        cycle.periodStart = statement.Period_Start__c;
        cycle.periodEnd = statement.Period_End__c;
        cycle.documentUrl = statement.Document_URL__c;
        cycle.errorDetail = statement.Error_Detail__c;
        cycle.retryCount = statement.Retry_Count__c == null ? 0 : statement.Retry_Count__c.intValue();
        cycle.accountCount = statement.Statement_Lines__r.size();
        cycle.totalBalance = statement.Total_Balance__c;
        cycle.totalFees = statement.Total_Fees__c;
        cycle.lastUpdated = statement.LastModifiedDate;
        return cycle;
    }
}