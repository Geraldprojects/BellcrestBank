/**
 * @author: Gomolemo
 * @description: Query layer for Statement_Line__c.
 *               Declared inherited sharing so each caller's sharing context carries through unchanged.
 * @date: 2026/09/13
 **/

public inherited sharing class StatementLinesSelector extends fflib_SObjectSelector {

    public Schema.SObjectType getSObjectType() {
        return Statement_Line__c.SObjectType;
    }

    public List<Schema.SObjectField> getSObjectFieldList() {
        return new List<Schema.SObjectField>{
                Statement_Line__c.Id,
                Statement_Line__c.Household_Statement__c,
                Statement_Line__c.Financial_Account__c,
                Statement_Line__c.Financial_Account_Name__c,
                Statement_Line__c.Financial_Account_Number__c,
                Statement_Line__c.Financial_Account_Type__c,
                Statement_Line__c.Is_Joint__c,
                Statement_Line__c.Closing_Balance__c,
                Statement_Line__c.Total_Fees__c,
                Statement_Line__c.Statement_Key__c
        };
    }

    public override String getOrderBy() {
        return 'Financial_Account_Name__c';
    }

    public List<Statement_Line__c> selectByStatementId(Set<Id> statementIds) {
        return (List<Statement_Line__c>) Database.query(
                newQueryFactory().setCondition('Household_Statement__c IN :statementIds').toSOQL()
        );
    }

    /**
     * Counted rather than selected: the cleanup summary only needs the number, and loading every line
     * to size a list would be wasteful once a few periods have accumulated.
     */
    public Integer countAll() {
        return [SELECT COUNT() FROM Statement_Line__c];
    }
}