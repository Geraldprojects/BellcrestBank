/**
 * @author: Gomolemo
 * @description: Walks a list of household statements through generation, one per transaction. Holds only
 *               the async plumbing — when to poll again, when to move on, how deep the chain may run.
 *               The generation itself lives in StatementGenerationService.
 * @date: 2026/09/12
 **/

public with sharing class StatementDocumentQueueable implements Queueable, Database.AllowsCallouts {

    // Zero, not one. enqueueJob's delay is in whole minutes, and Adobe finishes a statement in roughly
    // 10-15 seconds - so a one minute delay spent most of its time watching a job that was already done.
    // At zero the chain re-polls at queueable scheduling speed, a few seconds apart, which is closer to
    // how long the work actually takes. StatementGenerationService.MAX_POLL_ATTEMPTS is sized to match.
    private static final Integer POLL_DELAY_MINUTES = 0;
    private static final String LOG_SCENARIO = 'Statement Generation Run';
    // Developer Edition and Trial orgs cap chained queueables at a stack depth of 5. This chain spends one
    // link per statement submitted and one per poll, so a run of more than two statements exhausts that
    // before it finishes and dies with "Maximum stack depth has been reached". Production orgs have no
    // such cap, so raising it is a no-op once the trial ends.
    private static final Integer MAX_STACK_DEPTH = 500;

    private List<Id> statementIds;
    private String templateAssetId;
    private Integer pollAttempts;

    public StatementDocumentQueueable(List<Id> statementIds) {
        this(statementIds, null, 0);
    }

    /**
     * Starts a generation run. Always enter the chain through here rather than enqueuing directly: the
     * raised stack depth can only be set on the first enqueue, from outside a queueable, and it then
     * applies to every link that follows.
     */
    public static Id start(List<Id> statementIds) {
        AsyncOptions options = new AsyncOptions();
        options.MaximumQueueableStackDepth = MAX_STACK_DEPTH;
        return System.enqueueJob(new StatementDocumentQueueable(statementIds), options);
    }

    private StatementDocumentQueueable(List<Id> statementIds, String templateAssetId, Integer pollAttempts) {
        this.statementIds = statementIds;
        this.templateAssetId = templateAssetId;
        this.pollAttempts = pollAttempts;
    }

    public void execute(QueueableContext context) {
        if (statementIds.isEmpty()) {
            return;
        }

        // Groups every link of this chain under one scenario, so a run reads as a single story in the
        // log rather than as a scatter of unrelated transactions.
        Nebula.Logger.setScenario(LOG_SCENARIO);

        try {
            StatementGenerationService.Result result =   StatementGenerationService.advance(statementIds[0], templateAssetId, pollAttempts);

            // Carried forward so the next link reuses this run's template upload.
            templateAssetId = result.templateAssetId;

            switch on result.outcome {
                when SUBMITTED {
                    chain(0);
                }
                when PENDING {
                    chain(pollAttempts + 1);
                }
                when else {
                    // COMPLETED or FAILED: this statement is finished either way.
                    next();
                }
            }
        } finally {
            // Each link is its own transaction. Without this the entries buffered by the service are
            // thrown away, including the ones describing why a statement failed.
            Nebula.Logger.saveLog();
        }
    }

    /**
     * Polls the same statement again after a delay.
     * @param attempts number of attempts
     */
    private void chain(Integer attempts) {
        System.enqueueJob(
                new StatementDocumentQueueable(statementIds, templateAssetId, attempts),
                POLL_DELAY_MINUTES
        );
    }

    /**
     * Drops the finished statement and picks up the next one.
     */
    private void next() {
        List<Id> remaining = new List<Id>(statementIds);
        remaining.remove(0);
        if (!remaining.isEmpty()) {
            // No AsyncOptions here: the depth set by start() governs the whole chain, and a queueable is
            // not allowed to set it again for itself.
            System.enqueueJob(new StatementDocumentQueueable(remaining, templateAssetId, 0));
        }
    }
}