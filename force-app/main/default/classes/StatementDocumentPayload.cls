/**
 * @author: Gomolemo
 * @description: Builds the merge JSON for one household statement, matching the tags in the Word template.
 * @date: 2026/09/12
 **/

public with sharing class StatementDocumentPayload {

    public class PayloadException extends Exception {}

    public static Map<String, Object> build(Id statementId) {
        List<Household_Statement__c> statements =
                new HouseholdStatementsSelector().selectByIdWithLines(new Set<Id>{ statementId });
        if (statements.isEmpty()) {
            throw new PayloadException('Statement ' + statementId + ' no longer exists');
        }
        Household_Statement__c statement = statements[0];


        List<Map<String, Object>> lines = new List<Map<String, Object>>();
        for (Statement_Line__c line : statement.Statement_Lines__r) {
            lines.add(new Map<String, Object>{
                    'accountNumber' => maskNumber(line.Financial_Account_Number__c),
                    'accountType' => line.Financial_Account_Type__c,
                    // Adobe repeats a table row from {{lines.property}} tags and has no loop or if/else
                    // construct, so the Held column is resolved here rather than branched in the template.
                    'held' => line.Is_Joint__c ? 'Joint' : 'Individual',
                    // Kept alongside 'held' for any tag that wants the raw flag via {{expr(...)}}.
                    'joint' => line.Is_Joint__c,
                    // Adobe renders a null as an empty cell, which is the right treatment for a missing snapshot.
                    'balance' => format(line.Closing_Balance__c),
                    'fees' => format(line.Total_Fees__c)
            });
        }

        return new Map<String, Object>{
                'cycleKey' => formatDate(statement.Period_Start__c) + ' – ' + formatDate(statement.Period_End__c),
                // The day the document is produced, not the day the period closed.
                'statementDate' => formatDate(Date.today()),
                'accountCount' => lines.size(),
                'lines' => lines,
                'totalBalance' => format(statement.Total_Balance__c),
                'totalFees' => format(statement.Total_Fees__c)
        };
    }

    private static String format(Decimal amount) {
        return amount == null ? null : 'R ' + amount.setScale(2).format();
    }

    /**
     * Formatted explicitly rather than through Date.format(), which follows the running user's locale and
     * would render the same statement differently depending on who generated it.
     */
    private static String formatDate(Date value) {
        return value == null ? null : DateTime.newInstance(value, Time.newInstance(0, 0, 0, 0)).format('dd MMM yyyy');
    }

    private static String maskNumber(String account) {
        return account.length() <= 4 ? '****' : '****' + account.right(4);
    }
}