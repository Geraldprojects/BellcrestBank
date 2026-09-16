/**
 * Step 1 of the DocumentGenerationService smoke test: submit a render job.
 *
 * Run with:
 *   sf apex run --file scripts/apex/adobe-docgen-submit.apex --target-org Bellcrest
 *
 * Proves, in order: the Adobe_PDF_Services External Credential authenticates,
 * Adobe hands back an upload slot, the statementsTemplate static resource
 * uploads to the presigned S3 URI (Adobe_Asset_Storage remote site), and Adobe
 * accepts a document generation job against it.
 *
 * Copy the job URL it prints into adobe-docgen-poll.apex. Apex cannot sleep,
 * so the poll has to be a second transaction a few seconds later.
 */

// Fail loudly before spending callouts if the template is not in the org.
List<StaticResource> template = [
        SELECT Name, ContentType, BodyLength
        FROM StaticResource
        WHERE Name = 'statementsTemplate'
        LIMIT 1
];
if (template.isEmpty()) {
    throw new IllegalArgumentException(
            'Static resource statementsTemplate is missing; DocumentGenerationService cannot upload a template.');
}
System.debug('Template: ' + template[0].Name + ' (' + template[0].BodyLength + ' bytes, '
        + template[0].ContentType + ')');

// Token first, on its own, so an auth problem is not mistaken for a render problem.
String token = DocumentGenerationService.getAccessToken();
System.debug(token.startsWith('failed')
        ? 'TOKEN FAILED: ' + token
        : 'Token acquired (' + token.length() + ' chars)');

String jobUrl = DocumentGenerationService.generateDocument();

System.debug('=================================================================');
System.debug('JOB URL: ' + jobUrl);
System.debug('Paste that into scripts/apex/adobe-docgen-poll.apex and run it.');
System.debug('=================================================================');