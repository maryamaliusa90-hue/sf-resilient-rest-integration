@IsTest
private class AccountSyncQueueableTest {
    @TestSetup
    static void setup() {
        insert new List<Account>{
            new Account(Name = 'Synthetic One', Website = 'one.example', BillingCountry = 'US'),
            new Account(Name = 'Synthetic Two', Website = 'two.example', BillingCountry = 'US')
        };
    }

    private static List<Id> accountIds() {
        return new List<Id>(new Map<Id, Account>([SELECT Id FROM Account]).keySet());
    }

    @IsTest
    static void successStoresExternalIdAndLogs() {
        ErpCalloutMock mock = new ErpCalloutMock(new List<Integer>{ 201 });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new AccountSyncQueueable(accountIds()));
        Test.stopTest();

        Assert.areEqual(2, [SELECT COUNT() FROM Account WHERE AccountNumber LIKE 'ERP-%']);
        Assert.areEqual(2, [SELECT COUNT() FROM Integration_Log__c WHERE Outcome__c = 'Success']);
        Assert.areEqual('POST', mock.lastRequest.getMethod());
        Assert.isTrue(mock.lastRequest.getEndpoint().startsWith('callout:ERP_API'));
        Assert.isNotNull(mock.lastRequest.getHeader('X-Correlation-Id'));
    }

    @IsTest
    static void serverErrorIsQueuedForRetry() {
        Test.setMock(HttpCalloutMock.class, new ErpCalloutMock(new List<Integer>{ 503 }));

        Test.startTest();
        System.enqueueJob(new AccountSyncQueueable(accountIds()));
        Test.stopTest();

        Assert.areEqual(2, [SELECT COUNT() FROM Integration_Log__c WHERE Outcome__c = 'Retrying' AND Attempt__c = 1]);
        Assert.areEqual(0, [SELECT COUNT() FROM Account WHERE AccountNumber != NULL]);
    }

    @IsTest
    static void clientErrorIsNotRetried() {
        Test.setMock(HttpCalloutMock.class, new ErpCalloutMock(new List<Integer>{ 400 }));

        Test.startTest();
        System.enqueueJob(new AccountSyncQueueable(accountIds()));
        Test.stopTest();

        Assert.areEqual(2, [SELECT COUNT() FROM Integration_Log__c WHERE Outcome__c = 'Failed']);
        Assert.areEqual(400, [SELECT Status_Code__c FROM Integration_Log__c LIMIT 1].Status_Code__c);
    }

    @IsTest
    static void finalAttemptStopsRetrying() {
        Test.setMock(HttpCalloutMock.class, new ErpCalloutMock(new List<Integer>{ 500 }));

        Test.startTest();
        System.enqueueJob(new AccountSyncQueueable(accountIds(), AccountSyncQueueable.MAX_ATTEMPTS, 'corr-1'));
        Test.stopTest();

        Assert.areEqual(
            2,
            [SELECT COUNT() FROM Integration_Log__c WHERE Correlation_Id__c = 'corr-1' AND Outcome__c = 'Failed']
        );
    }

    @IsTest
    static void loggerRedactsSensitiveKeys() {
        String redacted = IntegrationLogger.redact('{"name":"x","password":"hunter2","Token" : "abc"}');
        Assert.isFalse(redacted.contains('hunter2'));
        Assert.isFalse(redacted.contains('abc'));
        Assert.isTrue(redacted.contains('"name":"x"'));
    }

    @IsTest
    static void flushWithEmptyBufferIsNoOp() {
        IntegrationLogger.flush();
        Assert.areEqual(0, IntegrationLogger.pendingCount());
        Assert.areEqual(0, [SELECT COUNT() FROM Integration_Log__c]);
    }
}
