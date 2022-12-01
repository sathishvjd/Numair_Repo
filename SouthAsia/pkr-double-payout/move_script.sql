/*

 Author: Numair Fazili
 Email: numair.fazili@transferwise.com
 Role: Regional Product Analyst (APAC)
 Description: This script is used to move tables pertaining to PKR Double Payouts from local to sandbox all since tables in the latter are purged every 6 weeks
 Schedule: Every month

 */

CREATE OR REPLACE TABLE SANDBOX_DB.SANDBOX_ALL.PKR_MASTER_TABLE AS
    (SELECT * FROM SANDBOX_DB.SANDBOX_NUMAIR_FAZILI.PKR_MASTER_TABLE);

CREATE OR REPLACE TABLE SANDBOX_DB.SANDBOX_ALL.PKR_CHANGE_LOG AS
    (SELECT * FROM SANDBOX_DB.SANDBOX_NUMAIR_FAZILI.PKR_CHANGE_LOG);

CREATE OR REPLACE TABLE SANDBOX_DB.SANDBOX_ALL.PKR_CLASSIFICATION AS
    (SELECT * FROM SANDBOX_DB.SANDBOX_NUMAIR_FAZILI.PKR_CLASSIFICATION);