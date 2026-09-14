/**
 * @author: Gomolemo
 * @description: Covers AccountsSelector, including the active-owner filter the notification service relies on.
 * @date: 2026/09/13
 **/

@IsTest
private class AccountsSelectorTest {

    @IsTest
    static void selectByIdReturnsTheRequestedAccounts() {
        Account household = StatementTestDataFactory.createHousehold('Owner Household');

        List<Account> results = new AccountsSelector().selectById(new Set<Id>{ household.Id });

        Assert.areEqual(1, results.size(), 'The requested account should be returned');
        Assert.areEqual('Owner Household', results[0].Name, 'Name should be in the selector field list');
        Assert.isNotNull(results[0].OwnerId, 'OwnerId should be in the selector field list');
    }

    @IsTest
    static void selectWithActiveOwnerReturnsHouseholdsOwnedByAnActiveUser() {
        Account household = StatementTestDataFactory.createHousehold('Active Owner Household');

        List<Account> results = new AccountsSelector().selectWithActiveOwner(new Set<Id>{ household.Id });

        Assert.areEqual(1, results.size(), 'The running user is active, so the household should match');
        Assert.areEqual(UserInfo.getUserId(), results[0].OwnerId, 'The owner should be the running user');
    }

    @IsTest
    static void selectWithActiveOwnerReturnsNothingForUnknownIds() {
        List<Account> results = new AccountsSelector().selectWithActiveOwner(new Set<Id>());

        Assert.isTrue(results.isEmpty(), 'An empty id set should match nothing');
    }
}