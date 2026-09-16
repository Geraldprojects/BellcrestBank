/**
 * @author: Gomolemo
 * @description: Covers FinancialAccountPartiesSelector, above all the ownership rule that decides whether a
 *               statement line reads as Joint or Individual.
 * @date: 2026/09/13
 **/

@IsTest
private class FinancialAccountPartiesSelectorTest {

    @IsTest
    static void selectByAccountIdReturnsPartiesForThatHolder() {
        Account holder = StatementTestDataFactory.createHousehold('Party Holder');
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Party FA', '5555', 'Savings');
        StatementTestDataFactory.createParty(financialAccount.Id, holder.Id, 'Owner');

        List<FinancialAccountParty> results =
                new FinancialAccountPartiesSelector().selectByAccountId(new Set<Id>{ holder.Id });

        Assert.areEqual(1, results.size(), 'The party for that holder should be returned');
        Assert.areEqual(financialAccount.Id, results[0].FinancialAccountId, 'It should point at the account');
    }

    @IsTest
    static void aSingleOwnerIsNotJoint() {
        Account owner = StatementTestDataFactory.createHousehold('Sole Owner');
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Solo FA', '6666', 'Savings');
        StatementTestDataFactory.createParty(financialAccount.Id, owner.Id, 'Owner');

        Set<Id> joint = new FinancialAccountPartiesSelector()
                .selectJointFinancialAccountIds(new Set<Id>{ financialAccount.Id });

        Assert.isFalse(joint.contains(financialAccount.Id), 'One owner is an individual account');
    }

    @IsTest
    static void anOwnerAndACoOwnerIsJoint() {
        Account first = StatementTestDataFactory.createHousehold('First Owner');
        Account second = StatementTestDataFactory.createHousehold('Second Owner');
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Joint FA', '7777', 'Investment Account');
        StatementTestDataFactory.createParty(financialAccount.Id, first.Id, 'Owner');
        StatementTestDataFactory.createParty(financialAccount.Id, second.Id, 'Co-Owner');

        Set<Id> joint = new FinancialAccountPartiesSelector()
                .selectJointFinancialAccountIds(new Set<Id>{ financialAccount.Id });

        Assert.isTrue(joint.contains(financialAccount.Id), 'Owner plus Co-Owner is a joint account');
    }

    @IsTest
    static void anOwnerAndANonOwningPartyIsNotJoint() {
        Account owner = StatementTestDataFactory.createHousehold('Loan Owner');
        Account leasee = StatementTestDataFactory.createHousehold('Leasee Party');
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Loan FA', '8888', 'Loan');
        StatementTestDataFactory.createParty(financialAccount.Id, owner.Id, 'Owner');
        StatementTestDataFactory.createParty(financialAccount.Id, leasee.Id, 'Leasee');

        Set<Id> joint = new FinancialAccountPartiesSelector()
                .selectJointFinancialAccountIds(new Set<Id>{ financialAccount.Id });

        Assert.isFalse(
                joint.contains(financialAccount.Id),
                'A leasee is a party to the account without owning it, so it stays individual'
        );
    }

    @IsTest
    static void anInactiveOwnerDoesNotMakeAnAccountJoint() {
        Account active = StatementTestDataFactory.createHousehold('Active Owner');
        Account ended = StatementTestDataFactory.createHousehold('Former Owner');
        FinancialAccount financialAccount =
                StatementTestDataFactory.createFinancialAccount('Ended FA', '9999', 'Savings');
        StatementTestDataFactory.createParty(financialAccount.Id, active.Id, 'Owner');
        StatementTestDataFactory.createEndedParty(financialAccount.Id, ended.Id, 'Co-Owner');

        Set<Id> joint = new FinancialAccountPartiesSelector()
                .selectJointFinancialAccountIds(new Set<Id>{ financialAccount.Id });

        Assert.isFalse(joint.contains(financialAccount.Id), 'An owner whose role has ended no longer counts');
    }
}