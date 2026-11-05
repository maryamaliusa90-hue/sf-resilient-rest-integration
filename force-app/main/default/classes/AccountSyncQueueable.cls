/**
 * Asynchronously syncs Accounts to the ERP, one callout per record,
 * retrying transient failures (429, 5xx, timeouts) by re-enqueueing
 * the remaining work up to MAX_ATTEMPTS.
 */
public with sharing class AccountSyncQueueable implements Queueable, Database.AllowsCallouts {
    public static final Integer MAX_ATTEMPTS = 3;
    @TestVisible
    private static Boolean chainingEnabled = !Test.isRunningTest();

    private final List<Id> accountIds;
    private final Integer attempt;
    private final String correlationId;

    public AccountSyncQueueable(List<Id> accountIds) {
        this(accountIds, 1, newCorrelationId());
    }

    @TestVisible
    private AccountSyncQueueable(List<Id> accountIds, Integer attempt, String correlationId) {
        this.accountIds = accountIds;
        this.attempt = attempt;
        this.correlationId = correlationId;
    }

    public void execute(QueueableContext ctx) {
        List<Account> accounts = [
            SELECT Id, Name, Website, BillingCountry
            FROM Account
            WHERE Id IN :accountIds
            WITH USER_MODE
        ];
        List<Id> retry = new List<Id>();
        List<Account> synced = new List<Account>();
        Integer calloutBudget = Limits.getLimitCallouts() - Limits.getCallouts();

        for (Account acc : accounts) {
            if (calloutBudget-- <= 0) {
                retry.add(acc.Id);
                continue;
            }
            AccountSyncService.SyncResult result = AccountSyncService.send(acc, attempt, correlationId);
            if (result.success) {
                synced.add(new Account(Id = acc.Id, AccountNumber = result.externalId));
            } else if (result.retryable && attempt < MAX_ATTEMPTS) {
                retry.add(acc.Id);
            }
        }

        // All callouts are done; DML is now safe.
        if (!synced.isEmpty()) {
            update as user synced;
        }
        IntegrationLogger.flush();

        if (!retry.isEmpty() && chainingEnabled) {
            System.enqueueJob(new AccountSyncQueueable(retry, attempt + 1, correlationId));
        }
    }

    private static String newCorrelationId() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 32);
    }
}
