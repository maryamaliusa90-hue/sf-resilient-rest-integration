/**
 * Buffers integration log entries in memory and writes them in one DML statement.
 * Callouts must happen before DML in a transaction, so callers log during the
 * callout phase and call flush() once at the end.
 */
public without sharing class IntegrationLogger {
    @TestVisible
    private static final Integer MAX_BODY = 32000;
    private static List<Integration_Log__c> buffer = new List<Integration_Log__c>();

    public static void log(
        HttpRequest req,
        HttpResponse res,
        String outcome,
        Integer attempt,
        String correlationId,
        Id recordId,
        String message
    ) {
        buffer.add(
            new Integration_Log__c(
                Endpoint__c = truncate(req?.getEndpoint(), 255),
                Http_Method__c = req?.getMethod(),
                Request_Body__c = truncate(redact(req?.getBody()), MAX_BODY),
                Response_Body__c = truncate(redact(res?.getBody()), MAX_BODY),
                Status_Code__c = res?.getStatusCode(),
                Outcome__c = outcome,
                Attempt__c = attempt,
                Correlation_Id__c = correlationId,
                Record_Id__c = recordId,
                Message__c = truncate(message, 255)
            )
        );
    }

    public static void flush() {
        if (buffer.isEmpty()) {
            return;
        }
        // Logs must persist even if the running user cannot see the object.
        Database.insert(buffer, false, AccessLevel.SYSTEM_MODE);
        buffer.clear();
    }

    @TestVisible
    private static Integer pendingCount() {
        return buffer.size();
    }

    /** Masks values of sensitive JSON keys so secrets and PII never reach the log. */
    @TestVisible
    private static String redact(String body) {
        if (String.isBlank(body)) {
            return body;
        }
        return body.replaceAll(
            '(?i)("(?:password|token|access_token|ssn|authorization|apikey|api_key)"\\s*:\\s*)"[^"]*"',
            '$1"***"'
        );
    }

    private static String truncate(String value, Integer max) {
        return value == null ? null : value.abbreviate(max);
    }
}
