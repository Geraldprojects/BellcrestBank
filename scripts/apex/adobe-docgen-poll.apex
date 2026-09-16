/**
 * Step 2 of the DocumentGenerationService smoke test: poll the job, then prove
 * the thing that came back is really a PDF.
 *
 * Paste the job URL printed by adobe-docgen-submit.apex into JOB_URL below, then:
 *   sf apex run --file scripts/apex/adobe-docgen-poll.apex --target-org Bellcrest
 *
 * pollDocument() returns either a status word ('in progress') or the presigned
 * download URI. Re-run this every few seconds until it stops saying in progress
 * - the render is usually done inside ten.
 *
 * A URI alone is not proof of a working render, so this also downloads the bytes
 * and checks the %PDF- magic number, then files the result as a Salesforce File
 * you can open to confirm the merge field actually landed in the document.
 */

final String JOB_URL = 'PASTE_JOB_URL_HERE';

if (JOB_URL == 'PASTE_JOB_URL_HERE') {
    throw new IllegalArgumentException('Set JOB_URL to the URL adobe-docgen-submit.apex printed.');
}

String result = DocumentGenerationService.pollDocument(JOB_URL);

if (!result.startsWith('http')) {
    // 'in progress' - Adobe is still rendering. Nothing is wrong; run this again.
    System.debug('Job status: ' + result + ' - run this script again in a few seconds.');
    return;
}

System.debug('DOWNLOAD URI: ' + result);

// The download host is presigned S3, so it needs the Adobe_Asset_Storage remote
// site rather than the Named Credential. If Adobe hands back a host that setting
// does not cover, the URI is still valid in a browser for ~24 hours.
HttpRequest download = new HttpRequest();
download.setEndpoint(result);
download.setMethod('GET');
download.setTimeout(120000);

Blob pdf;
try {
    HttpResponse response = new Http().send(download);
    if (response.getStatusCode() != 200) {
        System.debug('Download failed: HTTP ' + response.getStatusCode() + ' ' + response.getBody());
        return;
    }
    pdf = response.getBodyAsBlob();
} catch (CalloutException e) {
    System.debug('Download blocked from Apex (' + e.getMessage() + ').');
    System.debug('Open the DOWNLOAD URI above in a browser instead - it is presigned and needs no login.');
    return;
}

// A PDF always opens with the %PDF- header; an error page or a zero-byte asset
// would sail past a status-code-only check.
String firstBytes = pdf.size() >= 5
        ? EncodingUtil.convertToHex(pdf).substring(0, 10)
        : '';
Boolean looksLikePdf = firstBytes.equalsIgnoreCase('255044462d'); // %PDF-

System.debug('Bytes: ' + pdf.size());
System.debug('Magic number ' + (looksLikePdf ? 'OK (%PDF-)' : 'NOT A PDF - first bytes (hex): ' + firstBytes));

if (!looksLikePdf) {
    return;
}

ContentVersion file = new ContentVersion(
        Title = 'Adobe DocGen Smoke Test ' + Datetime.now().format('yyyy-MM-dd HH:mm:ss'),
        PathOnClient = 'adobe-docgen-smoke-test.pdf',
        VersionData = pdf
);
insert file;

Id contentDocumentId = [
        SELECT ContentDocumentId FROM ContentVersion WHERE Id = :file.Id
].ContentDocumentId;

System.debug('=================================================================');
System.debug('PDF saved. Open it at: ' + URL.getOrgDomainUrl().toExternalForm()
        + '/lightning/r/ContentDocument/' + contentDocumentId + '/view');
System.debug('Check the merge field rendered - the template placeholder should read');
System.debug('"HAHA MADE YOU LOOK" rather than {{test_merge_field}}.');
System.debug('=================================================================');