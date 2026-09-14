/**
 * @author: Gomolemo
 * @description: Builds the record graph the statement selectors query against. Kept in one place so a
 *               change to a required field or restricted picklist is fixed once rather than in every
 *               test class.
 * @date: 2026/09/13
 **/

@IsTest
public class StatementTestDataFactory {

    // FinancialAccountFee.Type is a restricted picklist; this is one of the three values it allows.
    public static final String FEE_TYPE = 'Stop Payment Fee';
    public static final String BALANCE_TYPE = 'Total Balance';

    public static Account createHousehold(String name) {
        Account household = new Account(Name = name);
        insert household;
        return household;
    }

    /**
     * A contact against the household. Salesforce creates the AccountContactRelation automatically, so
     * nothing inserts one directly.
     */
    public static Contact createMember(Id householdId, String lastName) {
        Contact member = new Contact(LastName = lastName, AccountId = householdId);
        insert member;
        return member;
    }

    public static FinancialAccount createFinancialAccount(String name, String accountNumber, String type) {
        FinancialAccount financialAccount = new FinancialAccount(
                Name = name,
                FinancialAccountNumber = accountNumber,
                Type = type
        );
        insert financialAccount;
        return financialAccount;
    }

    /**
     * IsRoleActive is derived from the role dates rather than set directly, so the start date is
     * backdated to make the party active.
     */
    public static FinancialAccountParty createParty(Id financialAccountId, Id accountId, String role) {
        return createParty(financialAccountId, accountId, role, null);
    }

    /**
     * A party whose role has already ended, which makes IsRoleActive false. The end date is set on
     * insert rather than by a later update, because updating it trips field-level security.
     */
    public static FinancialAccountParty createEndedParty(Id financialAccountId, Id accountId, String role) {
        return createParty(financialAccountId, accountId, role, Date.today().addDays(-1));
    }

    private static FinancialAccountParty createParty(
            Id financialAccountId,
            Id accountId,
            String role,
            Date roleEndDate
    ) {
        FinancialAccountParty party = new FinancialAccountParty(
                FinancialAccountId = financialAccountId,
                AccountId = accountId,
                Role = role,
                RoleStartDate = Date.today().addDays(-30),
                RoleEndDate = roleEndDate
        );
        insert party;
        return party;
    }

    public static FinancialAccountBalance createBalance(Id financialAccountId, Decimal amount, Datetime asOf) {
        FinancialAccountBalance balance = new FinancialAccountBalance(
                FinancialAccountId = financialAccountId,
                Amount = amount,
                BalanceAsOfDate = asOf,
                Type = BALANCE_TYPE
        );
        insert balance;
        return balance;
    }

    public static FinancialAccountFee createFee(Id financialAccountId, Decimal amount, Date startDate, Date endDate) {
        FinancialAccountFee fee = new FinancialAccountFee(
                FinancialAccountId = financialAccountId,
                Type = FEE_TYPE,
                Amount = amount,
                Frequency = 'One Time',
                StartDate = startDate,
                EndDate = endDate
        );
        insert fee;
        return fee;
    }

    public static PartyRelationshipGroup createRelationshipGroup(Id householdId, String name, String type, String status) {
        PartyRelationshipGroup relationshipGroup = new PartyRelationshipGroup(
                Name = name,
                AccountId = householdId,
                Type = type,
                Status = status
        );
        insert relationshipGroup;
        return relationshipGroup;
    }

    public static Household_Statement__c createStatement(
            Id householdId,
            String key,
            Date periodStart,
            Date periodEnd,
            String status
    ) {
        Household_Statement__c statement = new Household_Statement__c(
                Household__c = householdId,
                Statement_Key__c = key,
                Period_Start__c = periodStart,
                Period_End__c = periodEnd,
                Status__c = status,
                Total_Balance__c = 0,
                Total_Fees__c = 0
        );
        insert statement;
        return statement;
    }

    public static Statement_Line__c createLine(
            Id statementId,
            Id financialAccountId,
            String key,
            String accountName,
            Boolean isJoint
    ) {
        Statement_Line__c line = new Statement_Line__c(
                Household_Statement__c = statementId,
                Financial_Account__c = financialAccountId,
                Statement_Key__c = key,
                Financial_Account_Name__c = accountName,
                Financial_Account_Number__c = '1234567890',
                Financial_Account_Type__c = 'Savings',
                Is_Joint__c = isJoint,
                Closing_Balance__c = 100,
                Total_Fees__c = 10
        );
        insert line;
        return line;
    }

    /**
     * A file published against a record, which is what creates the ContentDocumentLink the cleanup
     * selector looks for.
     */
    public static ContentVersion createDocument(Id linkedEntityId, String title) {
        ContentVersion version = new ContentVersion(
                Title = title,
                PathOnClient = title + '.pdf',
                VersionData = Blob.valueOf('test-pdf-content'),
                FirstPublishLocationId = linkedEntityId
        );
        insert version;
        return [SELECT Id, ContentDocumentId, Title FROM ContentVersion WHERE Id = :version.Id];
    }
}