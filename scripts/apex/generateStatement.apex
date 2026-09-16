Date periodStart = Date.today().toStartOfMonth().addMonths(-1);
Database.executeBatch(new StatementBatch(periodStart, periodStart.addMonths(1).addDays(-1)));