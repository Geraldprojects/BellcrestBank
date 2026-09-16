try {
    // ---------------------------------------------------------------------------------
    // 1. FETCH RECORD TYPES (FSC & Standard)
    // ---------------------------------------------------------------------------------
    Id householdRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('IndustriesHousehold').getRecordTypeId();
    Id personAccountRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();
    Id businessRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('IndustriesBusiness').getRecordTypeId();
    Id contactRoleRtId = Schema.SObjectType.FinServ__ReciprocalRole__c.getRecordTypeInfosByDeveloperName().get('ContactRole').getRecordTypeId();

    // ---------------------------------------------------------------------------------
    // 2. CREATE HOUSEHOLDS & BUSINESSES (The Containers)
    // ---------------------------------------------------------------------------------
    List<Account> groups = new List<Account>{
            new Account(Name = 'The Maxwell Multi-Gen Household', RecordTypeId = householdRtId),
            new Account(Name = 'The Sterling Blended Family Household', RecordTypeId = householdRtId),
            new Account(Name = 'Maxwell Logistics Group Inc', RecordTypeId = businessRtId) // Business Entity
    };
    insert groups;

    Account maxwellHH = groups[0];
    Account sterlingHH = groups[1];
    Account maxwellBiz = groups[2];

    // ---------------------------------------------------------------------------------
    // 3. CREATE INDIVIDUAL CLIENTS (Person Accounts)
    // ---------------------------------------------------------------------------------
    List<Account> clients = new List<Account>{
            // Maxwell Gen 1 & 2
            new Account(FirstName = 'Charles', LastName = 'Maxwell', PersonEmail = 'charles@maxwell.mock', RecordTypeId = personAccountRtId), // Patriarch
            new Account(FirstName = 'Eleanor', LastName = 'Maxwell', PersonEmail = 'eleanor@maxwell.mock', RecordTypeId = personAccountRtId), // Matriarch
            new Account(FirstName = 'David', LastName = 'Maxwell', PersonEmail = 'david@maxwell.mock', RecordTypeId = personAccountRtId),     // Adult Son

            // Sterling Blended Family
            new Account(FirstName = 'Victoria', LastName = 'Sterling', PersonEmail = 'v.sterling@mock.com', RecordTypeId = personAccountRtId), // Primary
            new Account(FirstName = 'Richard', LastName = 'Cole', PersonEmail = 'r.cole@mock.com', RecordTypeId = personAccountRtId),       // Spouse (Different Surname)
            new Account(FirstName = 'Chloe', LastName = 'Sterling', PersonEmail = 'chloe@mock.com', RecordTypeId = personAccountRtId)          // Dependent Child
    };
    insert clients;

    // Map clients for clean reference
    Account charles = clients[0];
    Account eleanor = clients[1];
    Account david   = clients[2];
    Account victoria= clients[3];
    Account richard = clients[4];
    Account chloe   = clients[5];

    // Fetch the underlying Contact IDs created automatically by Person Accounts
    Set<Id> clientAccountIds = new Set<Id>{charles.Id, eleanor.Id, david.Id, victoria.Id, richard.Id, chloe.Id};
    Map<Id, Id> accountToContactMap = new Map<Id, Id>();
    for(Account pa : [SELECT Id, PersonContactId FROM Account WHERE Id IN :clientAccountIds]) {
        accountToContactMap.put(pa.Id, pa.PersonContactId);
    }

    // ---------------------------------------------------------------------------------
    // 4. ESTABLISH HOUSEHOLD MEMBERSHIPS (AccountContactRelation)
    // ---------------------------------------------------------------------------------
    List<AccountContactRelation> acrsToInsert = new List<AccountContactRelation>{
            // Maxwell Household Membership
            new AccountContactRelation(
                    AccountId = maxwellHH.Id,
                    ContactId = accountToContactMap.get(charles.Id),
                    Roles = 'Primary Member',
                    FinServ__PrimaryGroup__c = true,
                    FinServ__Rollups__c = 'All'
            ),
            new AccountContactRelation(
                    AccountId = maxwellHH.Id,
                    ContactId = accountToContactMap.get(eleanor.Id),
                    Roles = 'Spouse',
                    FinServ__PrimaryGroup__c = true,
                    FinServ__Rollups__c = 'All'
            ),
            new AccountContactRelation(
                    AccountId = maxwellHH.Id,
                    ContactId = accountToContactMap.get(david.Id),
                    Roles = 'Dependent Adult',
                    FinServ__PrimaryGroup__c = false,
                    FinServ__Rollups__c = 'Tasks;Events'
            ),

            // Sterling Household Membership
            new AccountContactRelation(
                    AccountId = sterlingHH.Id,
                    ContactId = accountToContactMap.get(victoria.Id),
                    Roles = 'Primary Member',
                    FinServ__PrimaryGroup__c = true,
                    FinServ__Rollups__c = 'All'
            ),
            new AccountContactRelation(
                    AccountId = sterlingHH.Id,
                    ContactId = accountToContactMap.get(richard.Id),
                    Roles = 'Spouse',
                    FinServ__PrimaryGroup__c = true,
                    FinServ__Rollups__c = 'All'
            ),
            new AccountContactRelation(
                    AccountId = sterlingHH.Id,
                    ContactId = accountToContactMap.get(chloe.Id),
                    Roles = 'Child',
                    FinServ__PrimaryGroup__c = true,
                    FinServ__Rollups__c = 'All'
            )
    };
    insert acrsToInsert;

    // ---------------------------------------------------------------------------------
    // 5. COMPLEX RELATIONSHIPS (Contact-Contact Framework fallback)
    // ---------------------------------------------------------------------------------
    Id businessPartnerRoleId;
    List<FinServ__ReciprocalRole__c> existingRoles = [SELECT Id FROM FinServ__ReciprocalRole__c WHERE Name = 'Business Partner' AND RecordTypeId = :contactRoleRtId LIMIT 1];

    if (!existingRoles.isEmpty()) {
        businessPartnerRoleId = existingRoles[0].Id;
    } else {
        FinServ__ReciprocalRole__c newRole = new FinServ__ReciprocalRole__c(
                Name = 'Business Partner',
                RecordTypeId = contactRoleRtId,
                FinServ__InverseRole__c = 'Business Partner',
                FinServ__RelationshipType__c = 'Contact Contact Relation',
                FinServ__CreateInverseRole__c = true
        );
        insert newRole;
        businessPartnerRoleId = newRole.Id;
    }

    List<FinServ__ContactContactRelation__c> peerRelationships = new List<FinServ__ContactContactRelation__c>{
            new FinServ__ContactContactRelation__c(
                    FinServ__Contact__c = accountToContactMap.get(charles.Id),
                    FinServ__RelatedContact__c = accountToContactMap.get(david.Id),
                    FinServ__Role__c = businessPartnerRoleId,
                    FinServ__Active__c = true
            )
    };
    insert peerRelationships;

    // ---------------------------------------------------------------------------------
    // 6. GENERATE FINANCIAL ACCOUNTS (Standard API Name: FinServ__FinancialAccount__c)
    // ---------------------------------------------------------------------------------
    List<FinServ__FinancialAccount__c> financialAccounts = new List<FinServ__FinancialAccount__c>();

    // --- Charles Maxwell Records ---
    financialAccounts.add(new FinServ__FinancialAccount__c(
            Name = 'Charles Maxwell - Living Trust Portfolio',
            FinServ__PrimaryOwner__c = charles.Id,
            FinServ__Household__c = maxwellHH.Id,
            FinServ__Balance__c = 4250000.00,
            FinServ__FinancialAccountType__c = 'Managed Account',
            FinServ__Status__c = 'Active',
            FinServ__Ownership__c = 'Trust'
    ));
    financialAccounts.add(new FinServ__FinancialAccount__c(
            Name = 'Charles Maxwell - Corporate Operating Acct',
            FinServ__PrimaryOwner__c = maxwellBiz.Id,
            FinServ__Household__c = maxwellHH.Id,
            FinServ__Balance__c = 850000.00,
            FinServ__FinancialAccountType__c = 'Checking',
            FinServ__Status__c = 'Active',
            FinServ__Ownership__c = 'Individual'
    ));

    // --- Eleanor Maxwell Records ---
    financialAccounts.add(new FinServ__FinancialAccount__c(
            Name = 'Eleanor Maxwell - Traditional IRA',
            FinServ__PrimaryOwner__c = eleanor.Id,
            FinServ__Household__c = maxwellHH.Id,
            FinServ__Balance__c = 620000.00,
            FinServ__FinancialAccountType__c = 'Fixed Annuity',
            FinServ__Status__c = 'Active',
            FinServ__Ownership__c = 'Individual'
    ));

    // --- David Maxwell Records ---
    financialAccounts.add(new FinServ__FinancialAccount__c(
            Name = 'David Maxwell - Active Trading Account',
            FinServ__PrimaryOwner__c = david.Id,
            FinServ__Household__c = maxwellHH.Id,
            FinServ__Balance__c = 340000.00,
            FinServ__FinancialAccountType__c = 'Brokerage',
            FinServ__Status__c = 'Active',
            FinServ__Ownership__c = 'Individual'
    ));

    // --- Victoria Sterling Records ---
    financialAccounts.add(new FinServ__FinancialAccount__c(
            Name = 'Victoria Sterling - Strategic Growth Portfolio',
            FinServ__PrimaryOwner__c = victoria.Id,
            FinServ__Household__c = sterlingHH.Id,
            FinServ__Balance__c = 1150000.00,
            FinServ__FinancialAccountType__c = 'Managed Account',
            FinServ__Status__c = 'Active',
            FinServ__Ownership__c = 'Individual'
    ));

    // --- Richard Cole Records ---
    financialAccounts.add(new FinServ__FinancialAccount__c(
            Name = 'Richard Cole - Executive 401k Rollover',
            FinServ__PrimaryOwner__c = richard.Id,
            FinServ__Household__c = sterlingHH.Id,
            FinServ__Balance__c = 430000.00,
            FinServ__FinancialAccountType__c = 'Fixed Annuity',
            FinServ__Status__c = 'Active',
            FinServ__Ownership__c = 'Individual'
    ));

    financialAccounts.add(new FinServ__FinancialAccount__c(
            Name = 'Sterling/Cole - HELOC Credit Line',
            FinServ__PrimaryOwner__c = victoria.Id,
            FinServ__JointOwner__c = richard.Id,
            FinServ__Household__c = sterlingHH.Id,
            FinServ__Balance__c = -120000.00,
            FinServ__FinancialAccountType__c = 'Credit Card',
            FinServ__Status__c = 'Active',
            FinServ__Ownership__c = 'Joint'
    ));

    // --- Chloe Sterling Records ---
    financialAccounts.add(new FinServ__FinancialAccount__c(
            Name = 'Chloe Sterling - 529 College Savings',
            FinServ__PrimaryOwner__c = chloe.Id,
            FinServ__Household__c = sterlingHH.Id,
            FinServ__Balance__c = 95000.00,
            FinServ__FinancialAccountType__c = 'Mutual Fund',
            FinServ__Status__c = 'Active',
            FinServ__Ownership__c = 'Individual'
    ));

    insert financialAccounts;

    System.debug('🚀 Complex multi-gen ecosystem successfully generated across 20+ relational intersections!');

} catch(Exception e) {
    System.debug('❌ Execution Failed: ' + e.getMessage() + ' at line ' + e.getLineNumber());
}