/**
 * @author: Gomolemo
 * @description: Drives one household statement through generation — submit, poll, store, publish — and
 *               reports what happened so the caller can decide how to come back for the next step.
 *               Sits above DocumentGenerationService, which is the Adobe HTTP client; this class holds
 *               the Salesforce-side lifecycle and owns no transport details.
 * @date: 2026/09/13
 **/

public with sharing class StatementGenerationService {

    // Sized against the queueable's poll delay rather than against a wall-clock target. With that delay
    // at zero a poll costs a few seconds, so this many attempts buys a couple of minutes of patience
    // before a statement is written off as timed out - far more headroom than Adobe has ever needed.
    private static final Integer MAX_POLL_ATTEMPTS = 30;
    private static final String LOG_TAG = 'Statement Generation';
    private static final String TEMPLATE_RESOURCE = 'Bellcrest_Statement_Template';

    public class GenerationException extends Exception {}

    /**
     * What one call to advance() accomplished.
     *
     * SUBMITTED - a job was handed to Adobe; poll next.
     * PENDING   - Adobe is still working; poll again.
     * COMPLETED - the PDF is stored and the statement is Ready.
     * FAILED    - the statement is marked Failed; there is nothing left to do for it.
     */
    public enum Outcome { SUBMITTED, PENDING, COMPLETED, FAILED }

    public class Result {
        public Outcome outcome;
        // Returned so a caller working through several statements can reuse one template upload.
        public String templateAssetId;

        private Result(Outcome outcome, String templateAssetId) {
            this.outcome = outcome;
            this.templateAssetId = templateAssetId;
        }
    }

    /**
     * Advances a statement by a single step. Callout-bearing, so callers must run in a context that
     * allows callouts. Business failures mark the statement Failed and return rather than throwing;
     * only a missing statement record propagates.
     *
     * @param statementId     the statement to advance
     * @param templateAssetId a previously uploaded template, or null to upload one now
     * @param pollAttempts    how many times this statement has already been polled
     * @return resolved Result class
     */
    public static Result advance(Id statementId, String templateAssetId, Integer pollAttempts) {
        Household_Statement__c statement = load(statementId);
        String assetId = templateAssetId;

        try {
            // Minted per transaction rather than carried between them: async job state is persisted,
            // and a bearer token does not belong at rest there. The token call is cheap.
            DocumentGenerationService adobe = new DocumentGenerationService(DocumentGenerationService.fetchAccessToken());

            // Adobe keeps an uploaded asset for 24 hours, so one upload serves a whole run.
            if (assetId == null) {
                assetId = adobe.uploadTemplate(loadTemplate());
            }

            if (String.isBlank(statement.Adobe_Job_URI__c)) {
                submit(adobe, statement, assetId);
                return new Result(Outcome.SUBMITTED, assetId);
            }

            DocumentGenerationService.JobStatus jobStatus = adobe.getJobStatus(statement.Adobe_Job_URI__c);

            if (jobStatus.isDone) {
                store(statement, adobe.downloadDocument(jobStatus.downloadUri));
                return new Result(Outcome.COMPLETED, assetId);
            }

            if (jobStatus.isFailed || pollAttempts >= MAX_POLL_ATTEMPTS) {
                fail(statement, jobStatus.isFailed ? 'Adobe reported a failed job' : 'Timed out waiting for Adobe');
                return new Result(Outcome.FAILED, assetId);
            }

            return new Result(Outcome.PENDING, assetId);
        } catch (Exception e) {
            // Only getMessage() reaches Error_Detail__c, so without this the type, line number and stack
            // trace of every generation failure would be lost the moment the transaction ended.
            Nebula.Logger.error('Statement generation failed', statement.Id, e).addTag(LOG_TAG);
            fail(statement, e.getMessage());
            return new Result(Outcome.FAILED, assetId);
        }
    }

    private static Household_Statement__c load(Id statementId) {
        List<Household_Statement__c> statements =
                new HouseholdStatementsSelector().selectByIdWithHousehold(new Set<Id>{ statementId });
        if (statements.isEmpty()) {
            // Deleted mid-run. Thrown rather than returned as null so the caller's catch cannot mark a
            // record that no longer exists as Failed.
            throw new GenerationException('Statement ' + statementId + ' no longer exists');
        }
        return statements[0];
    }

    /**
     * Announces every status transition on the event bus, so a listener can follow a statement all the
     * way through without asking for updates. Published after commit, so anyone who re-queries on
     * receipt reads the status the event describes rather than the one it replaced.
     *
     * Carries the whole outcome — document on success, reason on failure — so a consumer that only
     * wants to react, rather than render, never has to query at all.
     */
    private static void publishStatus(Household_Statement__c statement) {
        EventBus.publish(new Statement_Ready__e(
                Household_Statement_Id__c = statement.Id,
                Household_Id__c = statement.Household__c,
                Household_Name__c = statement.Household__r.Name,
                Status__c = statement.Status__c,
                Document_URL__c = statement.Document_URL__c,
                Error_Detail__c = statement.Error_Detail__c
        ));
    }

    private static void submit(
            DocumentGenerationService adobe,
            Household_Statement__c statement,
            String templateAssetId
    ) {
        statement.Adobe_Job_URI__c = adobe.submitJob(
                templateAssetId,
                StatementDocumentPayload.build(statement.Id)
        );
        statement.Status__c = 'Generating';
        update statement;
        publishStatus(statement);
        Nebula.Logger.info('Submitted to Adobe, job ' + statement.Adobe_Job_URI__c, statement.Id).addTag(LOG_TAG);
    }

    private static void store(Household_Statement__c statement, Blob pdf) {
        String documentName = statement.Household__r.Name + ' Statement ' + monthName(statement.Period_Start__c);

        ContentVersion version = new ContentVersion(
                Title = documentName,
                PathOnClient = documentName + '.pdf',
                VersionData = pdf,
                FirstPublishLocationId = statement.Id
        );
        insert version;

        statement.Document_URL__c = Url.getOrgDomainUrl().toExternalForm()
                + '/lightning/r/ContentDocument/'
                + new ContentVersionsSelector().selectById(new Set<Id>{ version.Id })[0].ContentDocumentId
                + '/view';
        statement.Status__c = 'Ready';
        statement.Error_Detail__c = null;
        update statement;
        publishStatus(statement);
        Nebula.Logger.info('Statement ready: ' + documentName, statement.Id).addTag(LOG_TAG);
    }

    private static void fail(Household_Statement__c statement, String message) {
        statement.Status__c = 'Failed';
        statement.Error_Detail__c = message;
        statement.Retry_Count__c = (statement.Retry_Count__c == null ? 0 : statement.Retry_Count__c) + 1;
        // Cleared so a retry submits a fresh job rather than polling the dead one.
        statement.Adobe_Job_URI__c = null;
        update statement;
        publishStatus(statement);
        Nebula.Logger.warn('Statement marked Failed (attempt ' + statement.Retry_Count__c + '): ' + message, statement.Id).addTag(LOG_TAG);
    }

    /**
     * The period's month as a name rather than a number, so a stored file reads as
     * "Adams Household Statement August" instead of "Adams Household Statement 8".
     * @param dateValue date
     * @return Month as string
     */
    private static String monthName(Date dateValue) {
        return Datetime.newInstance(dateValue, Time.newInstance(0, 0, 0, 0)).format('MMMM');
    }

    private static Blob loadTemplate() {
        List<StaticResource> resources =
                new StaticResourcesSelector().selectByName(new Set<String>{ TEMPLATE_RESOURCE });
        if (resources.isEmpty()) {
            throw new GenerationException('Static resource ' + TEMPLATE_RESOURCE + ' not found');
        }
        return resources[0].Body;
    }
}