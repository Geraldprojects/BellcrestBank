/**
 * @author: Gomolemo
 * @description: Covers DocumentGenerationService, the Adobe HTTP client.
 *
 *               This class owns transport only: minting a token, uploading, submitting, polling and
 *               downloading. It reports failures by throwing, and the layer above decides what that
 *               means for a statement.
 * @date: 2026/09/13
 **/

@IsTest
private class DocumentGenerationServiceTest {

    @IsTest
    static void mintingATokenReturnsTheAccessToken() {
        // Given Adobe accepting the credentials
        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobCompletes());

        // When a token is requested
        Test.startTest();
        String token = DocumentGenerationService.fetchAccessToken();
        Test.stopTest();

        // Then the token from the response body comes back
        Assert.areEqual('test-token', token, 'The access_token field should be returned');
    }

    @IsTest
    static void rejectedCredentialsThrowWithTheStatusAndBody() {
        // Given Adobe rejecting the credentials
        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.tokenIsRejected());

        // When a token is requested
        String message;
        Test.startTest();
        try {
            DocumentGenerationService.fetchAccessToken();
        } catch (DocumentGenerationService.CalloutException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        // Then the failure carries enough detail to diagnose it
        Assert.isNotNull(message, 'A rejected token request should throw');
        Assert.isTrue(message.contains('401'), 'The status code should be in the message: ' + message);
        Assert.isTrue(
                message.contains('invalid_client'),
                'The response body should be in the message: ' + message
        );
    }

    @IsTest
    static void uploadingTheTemplateReturnsItsAssetId() {
        // Given Adobe accepting an upload
        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobCompletes());
        DocumentGenerationService adobe = new DocumentGenerationService('test-token');

        // When the template is uploaded
        Test.startTest();
        String assetId = adobe.uploadTemplate(Blob.valueOf('template-bytes'));
        Test.stopTest();

        // Then the asset id Adobe assigned comes back
        Assert.areEqual(AdobeCalloutMock.ASSET_ID, assetId, 'The assetID field should be returned');
    }

    @IsTest
    static void submittingAJobReturnsAPathRatherThanAnAbsoluteUrl() {
        // Given Adobe accepting a job and replying with an absolute location header
        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobCompletes());
        DocumentGenerationService adobe = new DocumentGenerationService('test-token');

        // When a job is submitted
        Test.startTest();
        String jobPath = adobe.submitJob(AdobeCalloutMock.ASSET_ID, new Map<String, Object>{ 'k' => 'v' });
        Test.stopTest();

        // Then only the path is kept, so polling routes back through the named credential
        Assert.areEqual(
                AdobeCalloutMock.JOB_PATH, jobPath,
                'The host should be stripped so the poll inherits the named credential auth'
        );
    }

    @IsTest
    static void aFinishedJobReportsItsDownloadUri() {
        // Given a job Adobe has finished
        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobCompletes());
        DocumentGenerationService adobe = new DocumentGenerationService('test-token');

        // When its status is polled
        Test.startTest();
        DocumentGenerationService.JobStatus status = adobe.getJobStatus(AdobeCalloutMock.JOB_PATH);
        Test.stopTest();

        // Then it reports done and where to fetch the PDF
        Assert.isTrue(status.isDone, 'A done job should report isDone');
        Assert.isFalse(status.isFailed, 'A done job should not report isFailed');
        Assert.areEqual(AdobeCalloutMock.DOWNLOAD_URI, status.downloadUri, 'The download URI should be parsed');
    }

    @IsTest
    static void anUnfinishedJobReportsNeitherDoneNorFailed() {
        // Given a job Adobe is still working on
        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobIsStillRunning());
        DocumentGenerationService adobe = new DocumentGenerationService('test-token');

        // When its status is polled
        Test.startTest();
        DocumentGenerationService.JobStatus status = adobe.getJobStatus(AdobeCalloutMock.JOB_PATH);
        Test.stopTest();

        // Then the caller knows to keep waiting
        Assert.isFalse(status.isDone, 'An in-progress job is not done');
        Assert.isFalse(status.isFailed, 'An in-progress job has not failed');
        Assert.isNull(status.downloadUri, 'There is nothing to download yet');
    }

    @IsTest
    static void aFailedJobReportsItself() {
        // Given a job Adobe has failed
        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobFails());
        DocumentGenerationService adobe = new DocumentGenerationService('test-token');

        // When its status is polled
        Test.startTest();
        DocumentGenerationService.JobStatus status = adobe.getJobStatus(AdobeCalloutMock.JOB_PATH);
        Test.stopTest();

        // Then the caller can tell failure apart from still working
        Assert.isTrue(status.isFailed, 'A failed job should report isFailed');
        Assert.isFalse(status.isDone, 'A failed job is not done');
    }

    @IsTest
    static void downloadingReturnsTheDocumentBytes() {
        // Given a finished document sitting in cloud storage
        Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobCompletes());
        DocumentGenerationService adobe = new DocumentGenerationService('test-token');

        // When it is downloaded
        Test.startTest();
        Blob pdf = adobe.downloadDocument(AdobeCalloutMock.DOWNLOAD_URI);
        Test.stopTest();

        // Then the bytes come back intact
        Assert.areEqual(
                AdobeCalloutMock.PDF_CONTENT, pdf.toString(),
                'The downloaded bytes should be returned unchanged'
        );
    }
}