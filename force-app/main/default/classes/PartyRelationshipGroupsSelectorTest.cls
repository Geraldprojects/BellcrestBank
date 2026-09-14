/**
 * @author: Gomolemo
 * @description: Covers PartyRelationshipGroupsSelector, the locator the statement batch iterates.
 * @date: 2026/09/13
 **/

@IsTest
private class PartyRelationshipGroupsSelectorTest {

    @IsTest
    static void locatorReturnsOnlyActiveHouseholds() {
        Account first = StatementTestDataFactory.createHousehold('Locator Household');
        Account second = StatementTestDataFactory.createHousehold('Inactive Household');
        StatementTestDataFactory.createRelationshipGroup(first.Id, 'Active Group', 'Household', 'Active');
        StatementTestDataFactory.createRelationshipGroup(second.Id, 'Closed Group', 'Household', 'Inactive');

        Database.QueryLocator locator = new PartyRelationshipGroupsSelector().selectActiveHouseholdsLocator();

        List<PartyRelationshipGroup> found = new List<PartyRelationshipGroup>();
        Database.QueryLocatorIterator iterator = locator.iterator();
        while (iterator.hasNext()) {
            found.add((PartyRelationshipGroup) iterator.next());
        }

        Assert.areEqual(1, found.size(), 'Only the active household group should be iterated');
        Assert.areEqual(first.Id, found[0].AccountId, 'It should be the active one');
    }
}