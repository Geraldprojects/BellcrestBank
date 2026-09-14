/**
 * @author: Gomolemo
 * @description: Covers AccountContactRelationsSelector.
 * @date: 2026/09/13
 **/

@IsTest
private class AccountContactRelationsSelectorTest {

    @IsTest
    static void selectActiveByHouseholdReturnsMembersWithTheirPersonAccount() {
        Account household = StatementTestDataFactory.createHousehold('Membership Household');
        StatementTestDataFactory.createMember(household.Id, 'Member');

        List<AccountContactRelation> results =
                new AccountContactRelationsSelector().selectActiveByHousehold(new Set<Id>{ household.Id });

        Assert.areEqual(1, results.size(), 'The relation created with the contact should be returned');
        Assert.areEqual(household.Id, results[0].AccountId, 'The relation should point at the household');
        Assert.isTrue(results[0].IsActive, 'Only active relations are selected');
    }

    @IsTest
    static void selectActiveByHouseholdReturnsNothingForAHouseholdWithoutMembers() {
        Account household = StatementTestDataFactory.createHousehold('Empty Household');

        List<AccountContactRelation> results =
                new AccountContactRelationsSelector().selectActiveByHousehold(new Set<Id>{ household.Id });

        Assert.isTrue(results.isEmpty(), 'A household with no contacts should return nothing');
    }
}