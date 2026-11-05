/**
 * Sends Account data to an external ERP over REST.
 * Endpoint and authentication come from the Named Credential "ERP_API";
 * no URLs or secrets live in code.
 */
public with sharing class AccountSyncService {
    public static final String NAMED_CREDENTIAL = 'callout:ERP_API';
    public static final Integer TIMEOUT_MS = 20000;

    public class SyncResult {
        public Boolean success;
        public Boolean retryable;
        public Integer statusCode;
        public String externalId;
        public String message;
    }

    public static SyncResult send(Account acc, Integer attempt, String correlationId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + '/v1/customers');
        req.setMethod('POST');
        req.setTimeout(TIMEOUT_MS);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-Correlation-Id', correlationId);
        req.setBody(JSON.serialize(toPayload(acc)));

        SyncResult result = new SyncResult();
        HttpResponse res;
        try {
            res = new Http().send(req);
            result.statusCode = res.getStatusCode();
            result.success = result.statusCode >= 200 && result.statusCode < 300;
            result.retryable = result.statusCode == 429 || result.statusCode >= 500;
            if (result.success) {
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                result.externalId = (String) body.get('id');
            } else {
                result.message = 'HTTP ' + result.statusCode;
            }
        } catch (CalloutException e) {
            // Timeouts and connection errors are transient.
            result.success = false;
            result.retryable = true;
            result.message = e.getMessage();
        } catch (JSONException e) {
            result.success = false;
            result.retryable = false;
            result.message = 'Unparseable response: ' + e.getMessage();
        }

        Boolean willRetry = result.retryable && attempt < AccountSyncQueueable.MAX_ATTEMPTS;
        String outcome = result.success ? 'Success' : (willRetry ? 'Retrying' : 'Failed');
        IntegrationLogger.log(req, res, outcome, attempt, correlationId, acc.Id, result.message);
        return result;
    }

    @TestVisible
    private static Map<String, Object> toPayload(Account acc) {
        return new Map<String, Object>{
            'salesforceId' => acc.Id,
            'name' => acc.Name,
            'website' => acc.Website,
            'billingCountry' => acc.BillingCountry
        };
    }
}
