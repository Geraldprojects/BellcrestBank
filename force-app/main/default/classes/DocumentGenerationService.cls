/**
 * @author: Gomolemo
 * @description: Adobe PDF Services client — mints an access token, uploads the Word template,
 *               submits document generation jobs, polls and downloads.
 * @date: 2026/09/12
 **/

public with sharing class DocumentGenerationService {

    private static final String NAMED_CREDENTIAL = 'callout:Adobe_PDF_Services';
    private static final String DOCX_MEDIA_TYPE = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    // Resolved by the named credential at callout time, so the key never appears in Apex or in debug logs.
    private static final String API_KEY_MERGE_FIELD = '{!$Credential.Adobe_external.client_id}';

    private final String accessToken;

    public DocumentGenerationService(String accessToken) {
        this.accessToken = accessToken;
    }

    public class JobStatus {
        public String status;
        public String downloadUri;
        public Boolean isDone { get { return status == 'done'; } }
        public Boolean isFailed { get { return status == 'failed'; } }
    }

    public class CalloutException extends Exception {}

    /**
     * Mints an Adobe access token. The client id and secret are resolved from the external credential by
     * the named credential, so neither is ever held in Apex.
     */
    public static String fetchAccessToken() {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(NAMED_CREDENTIAL + '/token');
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        request.setBody('client_id={!$Credential.Adobe_external.client_id}'
                + '&client_secret={!$Credential.Adobe_external.client_secret}');
        request.setTimeout(60000);

        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() != 200) {
            throw new CalloutException('Token request failed: ' + response.getStatusCode() + ' ' + response.getBody());
        }

        String token = (String) ((Map<String, Object>) JSON.deserializeUntyped(response.getBody())).get('access_token');
        if (String.isBlank(token)) {
            throw new CalloutException('Token request returned no access_token');
        }
        return token;
    }

    /**
     * Uploads the template and returns its asset Id. Adobe keeps an uploaded asset for 24 hours,
     * so one upload serves every statement in a run.
     */
    public String uploadTemplate(Blob template) {
        HttpRequest presignRequest = adobeRequest('/assets', 'POST');
        presignRequest.setHeader('Content-Type', 'application/json');
        presignRequest.setBody(JSON.serialize(new Map<String, Object>{ 'mediaType' => DOCX_MEDIA_TYPE }));
        Map<String, Object> presign = send(presignRequest, 200, 'Template presign');

        // The upload URI is a presigned cloud-storage URL on a non-Adobe host, so it bypasses the named
        // credential. The query-string signature is the authorisation — adding Adobe headers would break it.
        HttpRequest uploadRequest = new HttpRequest();
        uploadRequest.setEndpoint((String) presign.get('uploadUri'));
        uploadRequest.setMethod('PUT');
        uploadRequest.setHeader('Content-Type', DOCX_MEDIA_TYPE);
        uploadRequest.setBodyAsBlob(template);
        uploadRequest.setTimeout(120000);
        HttpResponse uploadResponse = new Http().send(uploadRequest);
        if (uploadResponse.getStatusCode() != 200) {
            throw new CalloutException('Template upload failed: ' + uploadResponse.getStatusCode());
        }

        return (String) presign.get('assetID');
    }

    /**
     * Submits a generation job and returns the status path to poll.
     */
    public String submitJob(String templateAssetId, Map<String, Object> mergeData) {
        HttpRequest request = adobeRequest('/operation/documentgeneration', 'POST');
        request.setHeader('Content-Type', 'application/json');
        request.setBody(JSON.serialize(new Map<String, Object>{
                'assetID' => templateAssetId,
                'outputFormat' => 'pdf',
                'jsonDataForMerge' => mergeData
        }));

        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() != 201) {
            throw new CalloutException('Job submit failed: ' + response.getStatusCode() + ' ' + response.getBody());
        }

        String location = response.getHeader('location');
        if (String.isBlank(location)) {
            throw new CalloutException('Job submit returned no location header');
        }
        // Kept as a path so the poll routes back through the named credential and inherits its auth.
        return toPath(location);
    }

    public JobStatus getJobStatus(String statusPath) {
        Map<String, Object> body = send(adobeRequest(toPath(statusPath), 'GET'), 200, 'Job status');

        JobStatus jobStatus = new JobStatus();
        jobStatus.status = (String) body.get('status');
        Map<String, Object> asset = (Map<String, Object>) body.get('asset');
        if (asset != null) {
            jobStatus.downloadUri = (String) asset.get('downloadUri');
        }
        return jobStatus;
    }

    public Blob downloadDocument(String downloadUri) {
        // Presigned cloud-storage URL again: no named credential, no Adobe auth headers.
        HttpRequest request = new HttpRequest();
        request.setEndpoint(downloadUri);
        request.setMethod('GET');
        request.setTimeout(120000);
        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() != 200) {
            throw new CalloutException('Document download failed: ' + response.getStatusCode());
        }
        return response.getBodyAsBlob();
    }

    private HttpRequest adobeRequest(String path, String method) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(NAMED_CREDENTIAL + path);
        request.setMethod(method);
        request.setHeader('Authorization', 'Bearer ' + accessToken);
        request.setHeader('x-api-key', API_KEY_MERGE_FIELD);
        request.setTimeout(120000);
        return request;
    }

    /**
     * Adobe hands back an absolute job URL; we persist the path. Accepts either form so statements
     * submitted before this change still poll correctly.
     */
    private static String toPath(String uri) {
        if (String.isBlank(uri)) {
            throw new CalloutException('No Adobe job URI to poll');
        }
        if (!uri.startsWithIgnoreCase('http')) {
            return uri;
        }
        Url parsed = new Url(uri);
        return String.isBlank(parsed.getQuery()) ? parsed.getPath() : parsed.getPath() + '?' + parsed.getQuery();
    }

    private static Map<String, Object> send(HttpRequest request, Integer expectedStatus, String context) {
        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() != expectedStatus) {
            throw new CalloutException(context + ' failed: ' + response.getStatusCode() + ' ' + response.getBody());
        }
        return (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
    }
}