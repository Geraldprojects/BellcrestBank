/**
 * Simulates one complete household for the statement engine: the household
 * Account, its person-account members, their memberships, financial accounts
 * (individual, joint and closed), their Charges And Fees schedules and the
 * fee transactions the engine rolls up.
 *
 * Run with:
 *   sf apex run --file scripts/apex/simulate-household.apex --target-org Bellcrest
 *
 * Re-runnable: everything it creates is tagged in Account.Site with
 * SIM_TAG and torn down at the start of the next run, so the org never
 * accumulates duplicate simulated households.
 *
 * The fee data is deliberately mixed. Alongside the fees that should roll up it
 * plants a waived fee, a fee posted outside the cycle and a non-fee transaction,
 * so a run proves StatementDataSelector.feesByAccountId is filtering rather than
 * summing everything it finds.
 */

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
final String SIM_TAG = 'STATEMENT-ENGINE-SIM';
final String HOUSEHOLD_NAME = 'The Ashworth Household (Sim)';
// 1 = the month that just closed, which is what StatementRunScheduler statements.
final Integer MONTHS_BACK = 1;

// Mirrors StatementCycle.previousMonth() without depending on the class being
// deployed, so this script also runs against an org before the engine lands.
Date cycleStart = Date.today().toStartOfMonth().addMonths(-MONTHS_BACK);
Date cycleEnd = cycleStart.addMonths(1).addDays(-1);
String cycleKey = String.valueOf(cycleStart.year()) + '-'
        + String.valueOf(cycleStart.month()).leftPad(2, '0');

System.debug('=== Simulating household for cycle ' + cycleKey
        + ' (' + cycleStart + ' .. ' + cycleEnd + ') ===');

try {
    // -----------------------------------------------------------------------
    // 1. Tear down anything a previous run left behind
    // -----------------------------------------------------------------------
    List<Account> priorAccounts = [
            SELECT Id FROM Account WHERE Site = :SIM_TAG
    ];
    if (!priorAccounts.isEmpty()) {
        Set<Id> priorIds = new Map<Id, Account>(priorAccounts).keySet();

        List<FinServ__FinancialAccount__c> priorFas = [
                SELECT Id FROM FinServ__FinancialAccount__c
                WHERE FinServ__PrimaryOwner__c IN :priorIds
                   OR FinServ__JointOwner__c IN :priorIds
                   OR FinServ__Household__c IN :priorIds
        ];
        // Transactions and statement lines hold the child end of the graph, so
        // they go before the records they point at.
        delete [
                SELECT Id FROM FinServ__FinancialAccountTransaction__c
                WHERE FinServ__FinancialAccount__c IN :priorFas
        ];
        delete [
                SELECT Id FROM Household_Statement__c WHERE Household__c IN :priorIds
        ];
        delete priorFas;
        // Fee schedules are the parent of the accounts just removed, so they can
        // only go once nothing looks up to them.
        delete [
                SELECT Id FROM FinServ__ChargesAndFees__c
                WHERE FinServ__SourceSystemId__c = :SIM_TAG
        ];
        // Deleting a person account cascades to its contact and that contact's
        // memberships, so the AccountContactRelation rows need no explicit pass.
        delete priorAccounts;
        System.debug('Cleaned up ' + priorAccounts.size() + ' account(s) and '
                + priorFas.size() + ' financial account(s) from a previous run.');
    }

    // -----------------------------------------------------------------------
    // 2. Household container
    // -----------------------------------------------------------------------
    Id householdRtId = Account.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName().get('IndustriesHousehold').getRecordTypeId();
    Id personRtId = Account.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();

    Account household = new Account(
            Name = HOUSEHOLD_NAME,
            RecordTypeId = householdRtId,
            Site = SIM_TAG
    );
    insert household;

    // -----------------------------------------------------------------------
    // 3. Members (person accounts)
    // -----------------------------------------------------------------------
    Account marcus = new Account(FirstName = 'Marcus', LastName = 'Ashworth',
            PersonEmail = 'marcus.ashworth@sim.invalid',
            RecordTypeId = personRtId, Site = SIM_TAG);
    Account priya = new Account(FirstName = 'Priya', LastName = 'Ashworth',
            PersonEmail = 'priya.ashworth@sim.invalid',
            RecordTypeId = personRtId, Site = SIM_TAG);
    Account noah = new Account(FirstName = 'Noah', LastName = 'Ashworth',
            PersonEmail = 'noah.ashworth@sim.invalid',
            RecordTypeId = personRtId, Site = SIM_TAG);

    List<Account> members = new List<Account>{ marcus, priya, noah };
    insert members;

    Map<Id, Id> contactIdByAccountId = new Map<Id, Id>();
    for (Account pa : [
            SELECT Id, PersonContactId FROM Account WHERE Id IN :members
    ]) {
        contactIdByAccountId.put(pa.Id, pa.PersonContactId);
    }

    // -----------------------------------------------------------------------
    // 4. Memberships — this is what partyIdsByHousehold() walks
    // -----------------------------------------------------------------------
    insert new List<AccountContactRelation>{
            new AccountContactRelation(
                    AccountId = household.Id,
                    ContactId = contactIdByAccountId.get(marcus.Id),
                    Roles = 'Primary Member',
                    FinServ__PrimaryGroup__c = true,
                    FinServ__Rollups__c = 'All'
            ),
            new AccountContactRelation(
                    AccountId = household.Id,
                    ContactId = contactIdByAccountId.get(priya.Id),
                    Roles = 'Spouse',
                    FinServ__PrimaryGroup__c = true,
                    FinServ__Rollups__c = 'All'
            ),
            new AccountContactRelation(
                    AccountId = household.Id,
                    ContactId = contactIdByAccountId.get(noah.Id),
                    Roles = 'Child',
                    FinServ__PrimaryGroup__c = true,
                    FinServ__Rollups__c = 'All'
            )
    };

    // -----------------------------------------------------------------------
    // 5. Fee schedules (Charges And Fees)
    // -----------------------------------------------------------------------
    // FinServ__ChargesAndFees__c is the *parent* of a financial account: the
    // account carries FinServ__FinancialAccountChargesAndFees__c pointing up at
    // the schedule, so one schedule is shared by every account priced the same
    // way. It holds the account's standing terms — rates and standard charges —
    // not the amounts actually taken in a period. The statement engine never
    // reads it; posted fees come from FinServ__FinancialAccountTransaction__c
    // below. The two are kept consistent here so the sim reads correctly: each
    // posted fee matches a charge on the account's schedule.
    Id creditScheduleRtId = Schema.SObjectType.FinServ__ChargesAndFees__c
            .getRecordTypeInfosByDeveloperName().get('Credit').getRecordTypeId();
    Id debitScheduleRtId = Schema.SObjectType.FinServ__ChargesAndFees__c
            .getRecordTypeInfosByDeveloperName().get('Debit').getRecordTypeId();

    FinServ__ChargesAndFees__c everydaySchedule = new FinServ__ChargesAndFees__c(
            Name = 'Bellcrest Everyday Banking (Sim)',
            RecordTypeId = debitScheduleRtId,
            FinServ__SourceSystemId__c = SIM_TAG,
            FinServ__MonthlyServiceFee__c = 25.00,
            FinServ__ATMFee__c = 12.50,
            FinServ__OverdraftFees__c = 35.00,
            FinServ__InsufficientFundsFee__c = 35.00,
            FinServ__StopPaymentFee__c = 30.00,
            FinServ__StatementFee__c = 5.00,
            FinServ__InterestRate__c = 0.01
    );
    FinServ__ChargesAndFees__c cardSchedule = new FinServ__ChargesAndFees__c(
            Name = 'Bellcrest Signature Card (Sim)',
            RecordTypeId = creditScheduleRtId,
            FinServ__SourceSystemId__c = SIM_TAG,
            FinServ__APR__c = 19.99,
            FinServ__APRType__c = 'Variable',
            FinServ__CashAPR__c = 24.99,
            FinServ__CashAPRType__c = 'Variable',
            FinServ__BalanceTransferAPR__c = 21.99,
            FinServ__AnnualMembershipFee__c = 35.00,
            FinServ__CashAdvanceFee__c = 10.00,
            FinServ__ForeignTransactionFee__c = 3.00,
            FinServ__LatePaymentFee__c = 39.00,
            FinServ__ReplacementCardFee__c = 15.00
    );
    FinServ__ChargesAndFees__c managedSchedule = new FinServ__ChargesAndFees__c(
            Name = 'Bellcrest Managed Portfolio (Sim)',
            RecordTypeId = debitScheduleRtId,
            FinServ__SourceSystemId__c = SIM_TAG,
            FinServ__AnnualAccountCharge__c = 450.00,
            FinServ__MaximumTransactionFee__c = 250.00,
            FinServ__StatementFee__c = 5.00
    );

    insert new List<FinServ__ChargesAndFees__c>{
            everydaySchedule, cardSchedule, managedSchedule
    };

    // -----------------------------------------------------------------------
    // 6. Financial accounts
    // -----------------------------------------------------------------------
    FinServ__FinancialAccount__c marcusChecking = new FinServ__FinancialAccount__c(
            Name = 'Marcus Ashworth - Private Checking',
            FinServ__FinancialAccountChargesAndFees__c = everydaySchedule.Id,
            FinServ__FinancialAccountNumber__c = 'SIM-1001',
            FinServ__PrimaryOwner__c = marcus.Id,
            FinServ__Household__c = household.Id,
            FinServ__FinancialAccountType__c = 'Checking',
            FinServ__Ownership__c = 'Individual',
            FinServ__Status__c = 'Active',
            FinServ__Balance__c = 84500.00
    );
    FinServ__FinancialAccount__c marcusBrokerage = new FinServ__FinancialAccount__c(
            Name = 'Marcus Ashworth - Brokerage',
            FinServ__FinancialAccountChargesAndFees__c = managedSchedule.Id,
            FinServ__FinancialAccountNumber__c = 'SIM-1002',
            FinServ__PrimaryOwner__c = marcus.Id,
            FinServ__Household__c = household.Id,
            FinServ__FinancialAccountType__c = 'Brokerage',
            FinServ__Ownership__c = 'Individual',
            FinServ__Status__c = 'Active',
            FinServ__Balance__c = 1250000.00
    );
    FinServ__FinancialAccount__c priyaManaged = new FinServ__FinancialAccount__c(
            Name = 'Priya Ashworth - Managed Portfolio',
            FinServ__FinancialAccountChargesAndFees__c = managedSchedule.Id,
            FinServ__FinancialAccountNumber__c = 'SIM-1003',
            FinServ__PrimaryOwner__c = priya.Id,
            FinServ__Household__c = household.Id,
            FinServ__FinancialAccountType__c = 'Managed Account',
            FinServ__Ownership__c = 'Individual',
            FinServ__Status__c = 'Active',
            FinServ__Balance__c = 640000.00
    );
    // Joint account: reached through either owner, and must appear exactly once
    // on the statement even though two household members own it.
    FinServ__FinancialAccount__c jointCard = new FinServ__FinancialAccount__c(
            Name = 'Ashworth - Joint Reserve Card',
            FinServ__FinancialAccountChargesAndFees__c = cardSchedule.Id,
            FinServ__FinancialAccountNumber__c = 'SIM-1004',
            FinServ__PrimaryOwner__c = marcus.Id,
            FinServ__JointOwner__c = priya.Id,
            FinServ__Household__c = household.Id,
            FinServ__FinancialAccountType__c = 'Credit Card',
            FinServ__Ownership__c = 'Joint',
            FinServ__Status__c = 'Active',
            FinServ__Balance__c = -18750.00
    );
    FinServ__FinancialAccount__c noahSavings = new FinServ__FinancialAccount__c(
            Name = 'Noah Ashworth - 529 Savings',
            FinServ__FinancialAccountChargesAndFees__c = everydaySchedule.Id,
            FinServ__FinancialAccountNumber__c = 'SIM-1005',
            FinServ__PrimaryOwner__c = noah.Id,
            FinServ__Household__c = household.Id,
            FinServ__FinancialAccountType__c = 'Mutual Fund',
            FinServ__Ownership__c = 'Individual',
            FinServ__Status__c = 'Active',
            FinServ__Balance__c = 47000.00
    );
    // Closed before the cycle opened: accountsOwnedBy() should exclude it.
    FinServ__FinancialAccount__c closedAccount = new FinServ__FinancialAccount__c(
            Name = 'Marcus Ashworth - Closed Money Market',
            FinServ__FinancialAccountChargesAndFees__c = everydaySchedule.Id,
            FinServ__FinancialAccountNumber__c = 'SIM-1006',
            FinServ__PrimaryOwner__c = marcus.Id,
            FinServ__Household__c = household.Id,
            FinServ__FinancialAccountType__c = 'Checking',
            FinServ__Ownership__c = 'Individual',
            FinServ__Status__c = 'Closed',
            FinServ__Balance__c = 0,
            FinServ__CloseDate__c = cycleStart.addDays(-10)
    );

    List<FinServ__FinancialAccount__c> financialAccounts =
            new List<FinServ__FinancialAccount__c>{
                    marcusChecking, marcusBrokerage, priyaManaged,
                    jointCard, noahSavings, closedAccount
            };
    insert financialAccounts;

    // -----------------------------------------------------------------------
    // 7. Fee transactions
    // -----------------------------------------------------------------------
    // Anchors inside the cycle. Mid-month and the last second of the last day,
    // which is the boundary endTimeExclusive() has to keep on the near side.
    Datetime midCycle = Datetime.newInstance(cycleStart.addDays(9), Time.newInstance(10, 30, 0, 0));
    Datetime lastMoment = Datetime.newInstance(cycleEnd, Time.newInstance(23, 59, 0, 0));
    Datetime beforeCycle = Datetime.newInstance(cycleStart.addDays(-3), Time.newInstance(12, 0, 0, 0));

    List<FinServ__FinancialAccountTransaction__c> transactions =
            new List<FinServ__FinancialAccountTransaction__c>();

    // --- Counts toward the rollup ---
    transactions.add(new FinServ__FinancialAccountTransaction__c(
            FinServ__FinancialAccount__c = marcusChecking.Id,
            FinServ__Amount__c = 25.00,
            FinServ__TransactionDate__c = midCycle,
            FinServ__PostDate__c = midCycle,
            FinServ__TransactionType__c = 'Debit',
            FinServ__TransactionSubtype__c = 'Fee'
    ));
    transactions.add(new FinServ__FinancialAccountTransaction__c(
            FinServ__FinancialAccount__c = marcusChecking.Id,
            FinServ__Amount__c = 12.50,
            FinServ__TransactionDate__c = lastMoment,
            FinServ__PostDate__c = lastMoment,
            FinServ__TransactionType__c = 'Debit',
            FinServ__TransactionSubtype__c = 'Fee'
    ));
    transactions.add(new FinServ__FinancialAccountTransaction__c(
            FinServ__FinancialAccount__c = marcusBrokerage.Id,
            FinServ__Amount__c = 450.00,
            FinServ__TransactionDate__c = midCycle,
            FinServ__PostDate__c = midCycle,
            FinServ__TransactionType__c = 'Debit',
            FinServ__TransactionSubtype__c = 'Fee'
    ));
    transactions.add(new FinServ__FinancialAccountTransaction__c(
            FinServ__FinancialAccount__c = priyaManaged.Id,
            FinServ__Amount__c = 1600.00,
            FinServ__TransactionDate__c = midCycle,
            FinServ__PostDate__c = midCycle,
            FinServ__TransactionType__c = 'Debit',
            FinServ__TransactionSubtype__c = 'Fee'
    ));
    transactions.add(new FinServ__FinancialAccountTransaction__c(
            FinServ__FinancialAccount__c = jointCard.Id,
            FinServ__Amount__c = 89.99,
            FinServ__TransactionDate__c = midCycle,
            FinServ__PostDate__c = midCycle,
            FinServ__TransactionType__c = 'Debit',
            FinServ__TransactionSubtype__c = 'Merchant Charge'
    ));
    // Transacted before the cycle but posted inside it: post date decides, so
    // this belongs to the current statement.
    transactions.add(new FinServ__FinancialAccountTransaction__c(
            FinServ__FinancialAccount__c = jointCard.Id,
            FinServ__Amount__c = 35.00,
            FinServ__TransactionDate__c = beforeCycle,
            FinServ__PostDate__c = midCycle,
            FinServ__TransactionType__c = 'Debit',
            FinServ__TransactionSubtype__c = 'Fee'
    ));
    // No post date at all: the query falls back to the transaction date.
    transactions.add(new FinServ__FinancialAccountTransaction__c(
            FinServ__FinancialAccount__c = noahSavings.Id,
            FinServ__Amount__c = 5.00,
            FinServ__TransactionDate__c = midCycle,
            FinServ__TransactionType__c = 'Debit',
            FinServ__TransactionSubtype__c = 'Fee'
    ));

    Decimal expectedTotalFees = 25.00 + 12.50 + 450.00 + 1600.00 + 89.99 + 35.00 + 5.00;

    // --- Excluded, on purpose ---
    // Posted before the cycle opened.
    transactions.add(new FinServ__FinancialAccountTransaction__c(
            FinServ__FinancialAccount__c = marcusChecking.Id,
            FinServ__Amount__c = 999.00,
            FinServ__TransactionDate__c = beforeCycle,
            FinServ__PostDate__c = beforeCycle,
            FinServ__TransactionType__c = 'Debit',
            FinServ__TransactionSubtype__c = 'Fee'
    ));
    // Not a fee subtype.
    transactions.add(new FinServ__FinancialAccountTransaction__c(
            FinServ__FinancialAccount__c = marcusChecking.Id,
            FinServ__Amount__c = 3200.00,
            FinServ__TransactionDate__c = midCycle,
            FinServ__PostDate__c = midCycle,
            FinServ__TransactionType__c = 'Credit',
            FinServ__TransactionSubtype__c = 'Cash Deposit'
    ));

    // A waived fee, only if the org's waiver picklist offers a value to use.
    // Reading it from the describe keeps the script off a hardcoded label that
    // may not exist in every org.
    String waiverReason;
    for (Schema.PicklistEntry entry : Schema.SObjectType.FinServ__FinancialAccountTransaction__c
            .fields.FinServ__WaiverReason__c.getPicklistValues()) {
        if (entry.isActive()) {
            waiverReason = entry.getValue();
            break;
        }
    }
    if (waiverReason != null) {
        transactions.add(new FinServ__FinancialAccountTransaction__c(
                FinServ__FinancialAccount__c = priyaManaged.Id,
                FinServ__Amount__c = 750.00,
                FinServ__TransactionDate__c = midCycle,
                FinServ__PostDate__c = midCycle,
                FinServ__TransactionType__c = 'Debit',
                FinServ__TransactionSubtype__c = 'Fee',
                FinServ__WaiverReason__c = waiverReason
        ));
    } else {
        System.debug('No active FinServ__WaiverReason__c picklist value found; '
                + 'skipping the waived-fee case.');
    }

    insert transactions;

    // -----------------------------------------------------------------------
    // 8. Verification — the same shape the engine will read back
    // -----------------------------------------------------------------------
    Set<Id> partyIds = new Set<Id>();
    for (AccountContactRelation acr : [
            SELECT ContactId, Contact.AccountId
            FROM AccountContactRelation
            WHERE AccountId = :household.Id AND IsActive = true
    ]) {
        partyIds.add(acr.ContactId);
        if (acr.Contact.AccountId != null) {
            partyIds.add(acr.Contact.AccountId);
        }
    }

    List<FinServ__FinancialAccount__c> inScope = [
            SELECT Id, Name, FinServ__FinancialAccountType__c, FinServ__Balance__c,
                    FinServ__Ownership__c, FinServ__FinancialAccountChargesAndFees__r.Name
            FROM FinServ__FinancialAccount__c
            WHERE (FinServ__PrimaryOwner__c IN :partyIds OR FinServ__JointOwner__c IN :partyIds)
            AND (FinServ__CloseDate__c = NULL OR FinServ__CloseDate__c >= :cycleStart)
    ];

    Datetime periodStart = Datetime.newInstance(cycleStart, Time.newInstance(0, 0, 0, 0));
    Datetime periodEnd = Datetime.newInstance(cycleStart.addMonths(1), Time.newInstance(0, 0, 0, 0));
    Set<Id> inScopeIds = new Map<Id, FinServ__FinancialAccount__c>(inScope).keySet();
    Set<String> feeSubtypes = new Set<String>{ 'Fee', 'Merchant Charge' };

    Map<Id, Decimal> feesByAccountId = new Map<Id, Decimal>();
    for (AggregateResult row : [
            SELECT FinServ__FinancialAccount__c accountId, SUM(FinServ__Amount__c) total
            FROM FinServ__FinancialAccountTransaction__c
            WHERE FinServ__FinancialAccount__c IN :inScopeIds
            AND FinServ__TransactionSubtype__c IN :feeSubtypes
            AND FinServ__WaiverReason__c = NULL
            AND ((FinServ__PostDate__c >= :periodStart AND FinServ__PostDate__c < :periodEnd)
            OR (FinServ__PostDate__c = NULL
            AND FinServ__TransactionDate__c >= :periodStart
            AND FinServ__TransactionDate__c < :periodEnd))
            GROUP BY FinServ__FinancialAccount__c
    ]) {
        feesByAccountId.put((Id) row.get('accountId'),
                Math.abs((Decimal) row.get('total')));
    }

    Decimal totalBalance = 0;
    Decimal totalFees = 0;
    System.debug('--- Accounts in scope for ' + cycleKey + ' ---');
    for (FinServ__FinancialAccount__c fa : inScope) {
        Decimal fee = feesByAccountId.containsKey(fa.Id) ? feesByAccountId.get(fa.Id) : 0;
        totalBalance += fa.FinServ__Balance__c == null ? 0 : fa.FinServ__Balance__c;
        totalFees += fee;
        System.debug('  ' + fa.Name
                + ' | type=' + fa.FinServ__FinancialAccountType__c
                + ' | ownership=' + fa.FinServ__Ownership__c
                + ' | balance=' + fa.FinServ__Balance__c
                + ' | fees=' + fee
                + ' | schedule=' + (fa.FinServ__FinancialAccountChargesAndFees__r == null
                        ? 'NONE' : fa.FinServ__FinancialAccountChargesAndFees__r.Name));
    }

    System.debug('=== Simulation complete ===');
    System.debug('Household:      ' + HOUSEHOLD_NAME + ' (' + household.Id + ')');
    System.debug('Cycle key:      ' + cycleKey + '-' + household.Id);
    System.debug('Members:        ' + members.size());
    System.debug('Accounts:       ' + inScope.size() + ' in scope of '
            + financialAccounts.size() + ' created (1 closed before the cycle)');
    System.debug('Transactions:   ' + transactions.size() + ' created');
    System.debug('Total balance:  ' + totalBalance);
    System.debug('Total fees:     ' + totalFees + ' (expected ' + expectedTotalFees + ')');
    if (totalFees != expectedTotalFees) {
        System.debug('WARNING: fee total does not match the expected roll-up. '
                + 'Check Fee_Transaction_Subtypes__c on Statement_Engine_Setting__mdt.');
    }
    System.debug('Next: run the engine, e.g. '
            + 'Database.executeBatch(new StatementGenerationBatch(), 100);');

} catch (Exception e) {
    System.debug('Simulation failed: ' + e.getTypeName() + ' - ' + e.getMessage()
            + ' (line ' + e.getLineNumber() + ')');
    throw e;
}
