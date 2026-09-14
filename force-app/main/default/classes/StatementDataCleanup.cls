/**
 * @author: Gomolemo
 * @description: Clears generated statement data so the org can be retested from a clean slate. Removes
 *               household statements, their lines and the PDFs produced from them. Source data —
 *               households, financial accounts, balances, fees and parties — is deliberately left alone
 *               so StatementBatch can be re-run straight afterwards.
 * @date: 2026/09/13
 **/

public with sharing class StatementDataCleanup {

    public class Summary {
        public Integer statements = 0;
        public Integer lines = 0;
        public Integer documents = 0;

        public override String toString() {
            return 'statements=' + statements + ' lines=' + lines + ' documents=' + documents;
        }
    }

    /**
     * Counts what run() would remove, without removing anything.
     */
    public static Summary preview() {
        Map<Id, Household_Statement__c> statements = getStatements();
        Summary summary = new Summary();
        summary.statements = statements.size();
        summary.lines = new StatementLinesSelector().countAll();
        summary.documents = getDocumentIds(statements.keySet()).size();
        return summary;
    }

    /**
     * Deletes every household statement and the documents generated from it. Records go to the Recycle
     * Bin, so a run with the wrong scope can be reversed with an undelete within 15 days.
     */
    public static Summary run() {
        Map<Id, Household_Statement__c> statements = getStatements();

        Summary summary = new Summary();
        summary.statements = statements.size();
        summary.lines = new StatementLinesSelector().countAll();

        // Collected before the statements go: deleting a statement drops the ContentDocumentLink that
        // ties each PDF to it, which would orphan the file rather than delete it.
        Set<Id> documentIds = getDocumentIds(statements.keySet());
        summary.documents = documentIds.size();

        if (!statements.isEmpty()) {
            // Statement_Line__c is master-detail on the statement, so the lines go with it.
            delete statements.values();
        }

        if (!documentIds.isEmpty()) {
            delete new ContentDocumentsSelector().selectById(documentIds);
        }

        return summary;
    }

    private static Map<Id, Household_Statement__c> getStatements() {
        return new Map<Id, Household_Statement__c>(new HouseholdStatementsSelector().selectAll());
    }

    /**
     * ContentDocumentLink must be filtered by LinkedEntityId or ContentDocumentId, so the statement Ids
     * are passed in as a bind rather than reached through a semi-join.
     */
    private static Set<Id> getDocumentIds(Set<Id> statementIds) {
        return new ContentDocumentLinksSelector().selectDocumentIdsByLinkedEntity(statementIds);
    }
}