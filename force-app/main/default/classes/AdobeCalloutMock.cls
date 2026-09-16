/**
 * @author: Gomolemo
 * @description: Stands in for Adobe PDF Services during tests.
 *
 *               A generation run makes six different callouts, so this routes on the endpoint and
 *               returns the right shape for each. Tests never build one directly - they pick the
 *               scenario they want by name:
 *
 *                   Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobCompletes());
 *                   Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobIsStillRunning());
 *                   Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.jobFails());
 *                   Test.setMock(HttpCalloutMock.class, AdobeCalloutMock.tokenIsRejected());
 * @date: 2026/09/13
 **/

@IsTest
public class AdobeCalloutMock implements HttpCalloutMock {

    public static final String ASSET_ID = 'urn:aaid:AS:UE1:test-asset';
    public static final String JOB_PATH = '/operation/documentgeneration/TESTJOB123/status';
    public static final String DOWNLOAD_URI = 'https://storage.example.com/download/test.pdf';
    public static final String PDF_CONTENT = 'a-pretend-pdf';

    private String jobStatus = 'done';
    private Boolean tokenSucceeds = true;

    /** Adobe finishes the job, so the first poll finds it done. */
    public static AdobeCalloutMock jobCompletes() {
        return new AdobeCalloutMock();
    }

    /** Adobe has accepted the job but has not finished it yet. */
    public static AdobeCalloutMock jobIsStillRunning() {
        AdobeCalloutMock mock = new AdobeCalloutMock();
        mock.jobStatus = 'in progress';
        return mock;
    }

    /** Adobe accepted the job and then reported it as failed. */
    public static AdobeCalloutMock jobFails() {
        AdobeCalloutMock mock = new AdobeCalloutMock();
        mock.jobStatus = 'failed';
        return mock;
    }

    /** Adobe rejects the credentials, so nothing downstream is ever reached. */
    public static AdobeCalloutMock tokenIsRejected() {
        AdobeCalloutMock mock = new AdobeCalloutMock();
        mock.tokenSucceeds = false;
        return mock;
    }

    public HttpResponse respond(HttpRequest request) {
        String endpoint = request.getEndpoint();

        if (endpoint.endsWith('/token')) {
            return tokenSucceeds
                    ? jsonResponse(200, '{"access_token":"test-token","token_type":"Bearer"}')
                    : jsonResponse(401, '{"error":"invalid_client"}');
        }

        // Checked before the submit endpoint, because a status URL contains it as a prefix.
        if (endpoint.endsWith('/status')) {
            return jsonResponse(200, statusBody());
        }

        if (endpoint.endsWith('/operation/documentgeneration')) {
            HttpResponse response = jsonResponse(201, '{}');
            response.setHeader('location', 'https://pdf-services.adobe.io' + JOB_PATH);
            return response;
        }

        if (endpoint.endsWith('/assets')) {
            return jsonResponse(200,
                    '{"uploadUri":"https://storage.example.com/upload","assetID":"' + ASSET_ID + '"}');
        }

        // Anything left is presigned cloud storage: the template upload, or the finished PDF.
        HttpResponse response = new HttpResponse();
        response.setStatusCode(200);
        response.setBodyAsBlob(Blob.valueOf(PDF_CONTENT));
        return response;
    }

    private String statusBody() {
        return jobStatus == 'done'
                ? '{"status":"done","asset":{"downloadUri":"' + DOWNLOAD_URI + '"}}'
                : '{"status":"' + jobStatus + '"}';
    }

    private HttpResponse jsonResponse(Integer statusCode, String body) {
        HttpResponse response = new HttpResponse();
        response.setStatusCode(statusCode);
        response.setHeader('Content-Type', 'application/json');
        response.setBody(body);
        return response;
    }
}