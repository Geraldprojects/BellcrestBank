/**
 * @author: Gomolemo
 * @description: Tells the relationship manager when a household's statement is ready, by reacting to
 *               Statement_Ready__e. Subscribing rather than being called from the generation path
 *               keeps StatementGenerationService unaware that notifications exist.
 *
 *               Runs without sharing because a platform event trigger executes as the Automated Process
 *               user: resolving who owns a household is system bookkeeping, and shouldn't depend on what
 *               that user happens to have visibility of.
 * @date: 2026/09/13
 **/

public without sharing class StatementNotificationService {

    private static final String NOTIFICATION_TYPE = 'Statement_Ready';
    private static final String READY_STATUS = 'Ready';
    private static final String LOG_TAG = 'Statement Notification';

    public static void handle(List<Statement_Ready__e> events) {
        List<Statement_Ready__e> ready = new List<Statement_Ready__e>();
        Set<Id> householdIds = new Set<Id>();

        for (Statement_Ready__e event : events) {
            if (event.Status__c == READY_STATUS && String.isNotBlank(event.Household_Id__c)) {
                ready.add(event);
                householdIds.add((Id) event.Household_Id__c);
            }
        }

        if (ready.isEmpty()) {
            return;
        }

        Id notificationTypeId = getNotificationTypeId();
        if (notificationTypeId == null) {
            // The type is deployed metadata; if it is missing the org is misconfigured rather than the
            // statement being at fault, so this stays quiet instead of failing the event.
            Nebula.Logger.error('Custom notification type ' + NOTIFICATION_TYPE + ' not found - no relationship manager was told').addTag(LOG_TAG);
            Nebula.Logger.saveLog();
            return;
        }

        Map<Id, Id> managerByHousehold = getRelationshipManagers(householdIds);

        for (Statement_Ready__e event : ready) {
            Id managerId = managerByHousehold.get((Id) event.Household_Id__c);
            if (managerId == null) {
                // The household has no owner, or the owner is inactive. Skipping quietly would leave a
                // finished statement nobody was told about and no record of why.
                Nebula.Logger.warn(
                        'No active relationship manager for ' + event.Household_Name__c
                                + ' - ready notification not sent',
                        (Id) event.Household_Statement_Id__c
                ).addTag(LOG_TAG);
                continue;
            }
            notify(notificationTypeId, managerId, event);
        }

        // A platform event trigger is its own transaction, so the buffer has to be flushed here or
        // every entry above is discarded when it ends.
        Nebula.Logger.saveLog();
    }

    /**
     * The relationship manager is the household's owner. Inactive owners are skipped: a notification
     * addressed to one fails at send time and would take the whole batch with it.
     * @param householdIds set of householdsIds
     * @return map of account owners
     */
    @TestVisible
    private static Map<Id, Id> getRelationshipManagers(Set<Id> householdIds) {
        Map<Id, Id> managerByHousehold = new Map<Id, Id>();
        for (Account household : new AccountsSelector().selectWithActiveOwner(householdIds)) {
            managerByHousehold.put(household.Id, household.OwnerId);
        }
        return managerByHousehold;
    }

    private static Id getNotificationTypeId() {
        List<CustomNotificationType> types = new CustomNotificationTypesSelector()
                .selectByDeveloperName(new Set<String>{ NOTIFICATION_TYPE });
        return types.isEmpty() ? null : types[0].Id;
    }

    private static void notify(Id notificationTypeId, Id recipientId, Statement_Ready__e event) {
        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        notification.setNotificationTypeId(notificationTypeId);
        notification.setTitle('Statement ready: ' + event.Household_Name__c);
        notification.setBody('The statement for ' + event.Household_Name__c + ' has finished generating.');
        // Targets the statement, so opening the notification lands on the record with the document on it.
        notification.setTargetId(event.Household_Statement_Id__c);

        try {
            notification.send(new Set<String>{ recipientId });
        } catch (Exception e) {
            // An uncaught exception makes the platform retry the event, which would re-notify everyone
            // else in the batch. A statement that generated fine shouldn't be disturbed by a failed alert -
            // but swallowing it silently would hide the fact that nobody was told, so it is logged instead.
            Nebula.Logger.error('Notification to relationship manager failed', recipientId, e).addTag(LOG_TAG);
        }
    }
}