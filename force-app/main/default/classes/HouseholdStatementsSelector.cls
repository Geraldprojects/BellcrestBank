/**
 * @author: Gomolemo
 * @description: Query layer for Household_Statement__c.
 *
 *               Declared inherited sharing so each caller's context carries through: the LWC controller
 *               runs with sharing, while the platform event trigger runs without it as the Automated
 *               Process user, and a selector shouldn't silently change either.
 * @date: 2026/09/13
 **/

public inherited sharing class HouseholdStatementsSelector extends fflib_SObjectSelector {

    public Schema.SObjectType getSObjectType() {
        return Household_Statement__c.SObjectType;
    }

    public List<Schema.SObjectField> getSObjectFieldList() {
        return new List<Schema.SObjectField>{
                Household_Statement__c.Id,
                Household_Statement__c.Status__c,
                Household_Statement__c.Adobe_Job_URI__c,
                Household_Statement__c.Retry_Count__c,
                Household_Statement__c.Period_Start__c,
                Household_Statement__c.Period_End__c,
                Household_Statement__c.Document_URL__c,
                Household_Statement__c.Error_Detail__c,
                Household_Statement__c.Total_Balance__c,
                Household_Statement__c.Total_Fees__c,
                Household_Statement__c.Statement_Key__c,
                Household_Statement__c.Household__c,
                // Shown as "Updated" on the status tile, so it has to travel with the record.
                Household_Statement__c.LastModifiedDate
        };
    }

    public override String getOrderBy() {
        return 'Period_End__c DESC';
    }

    public List<Household_Statement__c> selectById(Set<Id> statementIds) {
        return (List<Household_Statement__c>) selectSObjectsById(statementIds);
    }

    /**
     * One statement with the household name resolved, for the generation pipeline. Returns a list so a
     * deleted record is the caller's decision to handle rather than an exception thrown from here.
     */
    public List<Household_Statement__c> selectByIdWithHousehold(Set<Id> statementIds) {
        fflib_QueryFactory query = newQueryFactory()
                .selectField('Household__r.Name')
                .setCondition('Id IN :statementIds');
        return (List<Household_Statement__c>) Database.query(query.toSOQL());
    }

    /**
     * Statements with their lines attached, for building the Adobe merge payload and for counting
     * accounts on the status tile.
     */
    public List<Household_Statement__c> selectByIdWithLines(Set<Id> statementIds) {
        fflib_QueryFactory query = newQueryFactory()
                .selectField('Household__r.Name')
                .setCondition('Id IN :statementIds');

        new StatementLinesSelector().addQueryFactorySubselect(query, 'Statement_Lines__r');

        return (List<Household_Statement__c>) Database.query(query.toSOQL());
    }

    /**
     * The household's most recent cycle. Ordered by period end rather than created date, so backfilling
     * an older period doesn't displace the current one.
     */
    public List<Household_Statement__c> selectCurrentCycleByHousehold(Id householdId) {
        fflib_QueryFactory query = newQueryFactory()
                .setCondition('Household__c = :householdId')
                .setOrdering('Period_End__c', fflib_QueryFactory.SortOrder.DESCENDING)
                .setLimit(1);

        new StatementLinesSelector().addQueryFactorySubselect(query, 'Statement_Lines__r');

        return (List<Household_Statement__c>) Database.query(query.toSOQL());
    }

    public List<Household_Statement__c> selectByStatusAndPeriodEnd(Set<String> statuses, Date periodEnd) {
        return (List<Household_Statement__c>) Database.query(
                newQueryFactory()
                        .setCondition('Status__c IN :statuses AND Period_End__c = :periodEnd')
                        .toSOQL()
        );
    }

    public List<Household_Statement__c> selectAll() {
        return (List<Household_Statement__c>) Database.query(newQueryFactory().toSOQL());
    }
}