/**
 * @author: Gomolemo
 * @description: Reacts to statement lifecycle events. Kept to a single delegating line so the
 *               behaviour stays testable outside a trigger context.
 * @date: 2026/09/13
 **/

trigger StatementReadyTrigger on Statement_Ready__e (after insert) {
    StatementNotificationService.handle(Trigger.new);
}