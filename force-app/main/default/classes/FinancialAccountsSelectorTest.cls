/**
 * @author: Gomolemo
 * @description: Covers FinancialAccountsSelector.
 * @date: 2026/09/13
 **/

@IsTest
private class FinancialAccountsSelectorTest {

    @IsTest
    static void selectByIdReturnsTheFrozenAttributeFields() {
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Savings One', '3333', 'Savings');

        List<FinancialAccount> results =
                new FinancialAccountsSelector().selectById(new Set<Id>{ financialAccount.Id });

        Assert.areEqual(1, results.size(), 'The requested account should be returned');
        Assert.areEqual('Savings One', results[0].Name, 'Name is copied onto statement lines');
        Assert.areEqual('3333', results[0].FinancialAccountNumber, 'Number is copied onto statement lines');
        Assert.areEqual('Savings', results[0].Type, 'Type is copied onto statement lines');
    }

    @IsTest
    static void selectMapByIdIsKeyedByRecordId() {
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Savings Two', '4444', 'Checking');

        Map<Id, FinancialAccount> results =
                new FinancialAccountsSelector().selectMapById(new Set<Id>{ financialAccount.Id });

        Assert.areEqual(1, results.size(), 'One account was requested');
        Assert.areEqual('Checking', results.get(financialAccount.Id).Type, 'The map should be keyed by id');
    }
}