/**
 * @author: Gomolemo
 * @description: Covers StatementDocumentPayload, which builds the JSON Adobe merges into the Word
 *               template. Every assertion here mirrors a tag in that template - if a key is renamed,
 *               the document silently renders a blank, so the keys are asserted by name.
 * @date: 2026/09/13
 **/

@IsTest
private class StatementDocumentPayloadTest {

    @TestSetup
    static void setup() {
        Account household = StatementTestDataFactory.createHousehold('Payload Household');
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Payload FA', '1234567890', 'Savings');

        Household_Statement__c statement = StatementTestDataFactory.createStatement(
                household.Id, 'PAY-1', Date.newInstance(2026, 8, 1), Date.newInstance(2026, 8, 31), 'Draft'
        );
        StatementTestDataFactory.createLine(statement.Id, financialAccount.Id, 'PAY-1-A', 'Alpha', true);
        StatementTestDataFactory.createLine(statement.Id, financialAccount.Id, 'PAY-1-B', 'Beta', false);
    }

    private static Map<String, Object> buildPayload() {
        return StatementDocumentPayload.build([SELECT Id FROM Household_Statement__c].Id);
    }

    @IsTest
    static void thePayloadCarriesEveryKeyTheTemplateExpects() {
        // When the payload is built
        Test.startTest();
        Map<String, Object> payload = buildPayload();
        Test.stopTest();

        // Then every top-level template tag has a value
        Assert.isTrue(payload.containsKey('cycleKey'), 'Template tag {{cycleKey}}');
        Assert.isTrue(payload.containsKey('statementDate'), 'Template tag {{statementDate}}');
        Assert.isTrue(payload.containsKey('accountCount'), 'Template tag {{accountCount}}');
        Assert.isTrue(payload.containsKey('totalBalance'), 'Template tag {{totalBalance}}');
        Assert.isTrue(payload.containsKey('totalFees'), 'Template tag {{totalFees}}');
        Assert.isTrue(payload.containsKey('lines'), 'Template repeats a table row over {{lines.*}}');
    }

    @IsTest
    static void eachLineCarriesEveryColumnTheTableExpects() {
        // When the payload is built
        Test.startTest();
        Map<String, Object> payload = buildPayload();
        Test.stopTest();

        // Then each row has the five columns the template renders
        List<Object> lines = (List<Object>) payload.get('lines');
        Assert.areEqual(2, lines.size(), 'Both statement lines should be in the payload');

        Map<String, Object> line = (Map<String, Object>) lines[0];
        Assert.isTrue(line.containsKey('accountNumber'), 'Column: Account');
        Assert.isTrue(line.containsKey('accountType'), 'Column: Type');
        Assert.isTrue(line.containsKey('held'), 'Column: Held');
        Assert.isTrue(line.containsKey('balance'), 'Column: Balance');
        Assert.isTrue(line.containsKey('fees'), 'Column: Fees');
    }

    @IsTest
    static void accountCountMatchesTheNumberOfLines() {
        // When the payload is built
        Test.startTest();
        Map<String, Object> payload = buildPayload();
        Test.stopTest();

        // Then the header count agrees with the table beneath it
        Assert.areEqual(2, payload.get('accountCount'), 'accountCount should match the number of lines');
    }

    @IsTest
    static void aJointAccountIsRenderedAsJointAndASoleAccountAsIndividual() {
        // When the payload is built
        Test.startTest();
        Map<String, Object> payload = buildPayload();
        Test.stopTest();

        // Then the Held column is resolved in Apex, because Adobe has no if/else construct
        Set<String> heldValues = new Set<String>();
        for (Object row : (List<Object>) payload.get('lines')) {
            heldValues.add((String) ((Map<String, Object>) row).get('held'));
        }

        Assert.isTrue(heldValues.contains('Joint'), 'The joint line should read Joint');
        Assert.isTrue(heldValues.contains('Individual'), 'The sole line should read Individual');
    }

    @IsTest
    static void accountNumbersAreMaskedToTheLastFourDigits() {
        // When the payload is built
        Test.startTest();
        Map<String, Object> payload = buildPayload();
        Test.stopTest();

        // Then a client-facing document never carries a full account number
        Map<String, Object> line = (Map<String, Object>) ((List<Object>) payload.get('lines'))[0];
        Assert.areEqual('****7890', line.get('accountNumber'), 'Only the last four digits should survive');
    }

    @IsTest
    static void theCycleIsRenderedAsAReadableDateRange() {
        // When the payload is built
        Test.startTest();
        Map<String, Object> payload = buildPayload();
        Test.stopTest();

        // Then the period reads as dates rather than as the record's external id
        String cycleKey = (String) payload.get('cycleKey');
        Assert.isTrue(cycleKey.contains('Aug 2026'), 'The cycle should name the period, was: ' + cycleKey);
    }

    @IsTest
    static void buildingAPayloadForAMissingStatementThrows() {
        // Given a statement that has been deleted
        Household_Statement__c statement = [SELECT Id FROM Household_Statement__c];
        Id deletedId = statement.Id;
        delete statement;

        // When a payload is requested for it
        Boolean threw = false;
        Test.startTest();
        try {
            StatementDocumentPayload.build(deletedId);
        } catch (StatementDocumentPayload.PayloadException e) {
            threw = true;
        }
        Test.stopTest();

        // Then it says so plainly rather than failing on an empty list
        Assert.isTrue(threw, 'A missing statement should throw a named exception');
    }
}