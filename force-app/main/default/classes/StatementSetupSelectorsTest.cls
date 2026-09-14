/**
 * @author: Gomolemo
 * @description: Covers StaticResourcesSelector and CustomNotificationTypesSelector.
 *
 *               Both read setup metadata that cannot be inserted in a test, so these assert the query
 *               shape against names that are guaranteed not to exist. Asserting a real static resource
 *               or notification type would need SeeAllData and would fail in any org lacking them.
 * @date: 2026/09/13
 **/

@IsTest
private class StatementSetupSelectorsTest {

    @IsTest
    static void staticResourceSelectorReturnsNothingForAnUnknownName() {
        List<StaticResource> results =
                new StaticResourcesSelector().selectByName(new Set<String>{ 'No_Such_Resource_12345' });

        Assert.isTrue(results.isEmpty(), 'An unknown resource name should match nothing');
    }

    @IsTest
    static void notificationTypeSelectorReturnsNothingForAnUnknownDeveloperName() {
        List<CustomNotificationType> results = new CustomNotificationTypesSelector()
                .selectByDeveloperName(new Set<String>{ 'No_Such_Notification_Type_12345' });

        Assert.isTrue(results.isEmpty(), 'An unknown developer name should match nothing');
    }
}