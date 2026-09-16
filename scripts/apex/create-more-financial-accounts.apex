// Anonymous Apex: adds more Financial Accounts for the existing test
// Person Accounts (Alice TestScript, Bob TestScript) created by
// create-household-test-data.apex. Does not touch the Accounts themselves.
//
// Run with:
//   sf apex run --file scripts/apex/create-more-financial-accounts.apex --target-org Bellcrest

Map<String, Id> peopleByName = new Map<String, Id>();
for (Account acc : [
    SELECT Id, Name FROM Account WHERE Name IN ('Alice TestScript', 'Bob TestScript')
]) {
    peopleByName.put(acc.Name, acc.Id);
}

Id aliceId = peopleByName.get('Alice TestScript');
Id bobId = peopleByName.get('Bob TestScript');

if (aliceId == null || bobId == null) {
    System.debug('Alice/Bob not found - run create-household-test-data.apex first.');
    return;
}

insert new List<FinServ__FinancialAccount__c>{
    new FinServ__FinancialAccount__c(
        Name = 'Alice Credit Card (Script)',
        FinServ__PrimaryOwner__c = aliceId,
        FinServ__FinancialAccountType__c = 'Credit Card',
        FinServ__Balance__c = 3200,
        FinServ__Status__c = 'Open'
    ),
    new FinServ__FinancialAccount__c(
        Name = 'Bob CD (Script)',
        FinServ__PrimaryOwner__c = bobId,
        FinServ__FinancialAccountType__c = 'CD',
        FinServ__Balance__c = 15000,
        FinServ__Status__c = 'Open'
    )
};

for (FinServ__FinancialAccount__c fa : [
    SELECT Name, FinServ__Balance__c, FinServ__PrimaryOwner__r.Name, FinServ__JointOwner__r.Name
    FROM FinServ__FinancialAccount__c
    WHERE FinServ__PrimaryOwner__c IN :new List<Id>{ aliceId, bobId }
       OR FinServ__JointOwner__c IN :new List<Id>{ aliceId, bobId }
]) {
    System.debug(fa.Name + ' | Balance=' + fa.FinServ__Balance__c
        + ' | Primary=' + fa.FinServ__PrimaryOwner__r.Name
        + ' | Joint=' + (fa.FinServ__JointOwner__r != null ? fa.FinServ__JointOwner__r.Name : 'none'));
}