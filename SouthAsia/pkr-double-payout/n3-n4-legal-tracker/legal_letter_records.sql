
/*
 Author: Numair Fazili
 Description: The following query is used to extract open transfers in N3/N4 category with amounts exceeding 800GBP to whom legal letters are to be sent to initiate recoveries
 Note!!: This query must only be used as a reference and cannot be used after the legal letters are sent out - This is because the underlying data is subject to changes (balance records, work item states etc)


 */


WITH CTE AS (
    SELECT DISTINCT PMT.TRANSFER_ID,COALESCE(PCL.PAYOUT_CLASSIFICATION,PMT.PAYOUT_CLASSIFICATION) AS TRANSFER_STATE
    FROM SANDBOX_DB.SANDBOX_ALL.PKR_MASTER_TABLE PMT
    LEFT JOIN  SANDBOX_DB.SANDBOX_ALL.PKR_CHANGE_LOG PCL ON PCL.TRANSFER_ID = PMT.TRANSFER_ID

),

MAIN_TABLE AS (SELECT
DISTINCT CTE.TRANSFER_ID AS TRANSFER_ID,
LAST_VALUE(CTE.TRANSFER_STATE) OVER (PARTITION BY CTE.TRANSFER_ID ORDER BY LAST_UPDATED) AS TRANSFER_STATE,
LAST_VALUE(WI.STATE) OVER (PARTITION BY CTE.TRANSFER_ID ORDER BY LAST_UPDATED) AS WORK_ITEM_STATE,
LAST_VALUE(SOURCE_CURRENCY) OVER (PARTITION BY CTE.TRANSFER_ID ORDER BY LAST_UPDATED) AS SOURCE_CURRENCY,
LAST_VALUE(TARGET_CURRENCY) OVER (PARTITION BY CTE.TRANSFER_ID ORDER BY LAST_UPDATED) AS TARGET_CURRENCY,
LAST_VALUE(INVOICE_VALUE_LOCAL) OVER (PARTITION BY CTE.TRANSFER_ID ORDER BY LAST_UPDATED) AS AMOUNT_IN_SOURCE_CCY,
LAST_VALUE(FEE_VALUE_LOCAL) OVER (PARTITION BY CTE.TRANSFER_ID ORDER BY LAST_UPDATED) AS FEES_IN_SOURCE_CCY,
LAST_VALUE(INVOICE_VALUE_GBP) OVER (PARTITION BY CTE.TRANSFER_ID ORDER BY LAST_UPDATED) AS AMOUNT_IN_GBP,
LAST_VALUE(WI.LAST_UPDATED ) OVER (PARTITION BY CTE.TRANSFER_ID ORDER BY LAST_UPDATED) AS LAST_UPDATED,
LAST_VALUE(PKRC.CATEGORY) OVER (PARTITION BY CTE.TRANSFER_ID ORDER BY LAST_UPDATED) AS CATEGORY,
LAST_VALUE(PKRC.NOTIFICATION_CATEGORY) OVER (PARTITION BY CTE.TRANSFER_ID ORDER BY LAST_UPDATED) AS NOTIFICATION_CATEGORY,
LAST_VALUE(PKRC.PAYIN_CHANNEL) OVER (PARTITION BY CTE.TRANSFER_ID ORDER BY LAST_UPDATED) AS PAYIN_CHANNEL,
LAST_VALUE(RAS.USER_PROFILE_ID) OVER (PARTITION BY CTE.TRANSFER_ID ORDER BY LAST_UPDATED) AS USER_PROFILE_ID,
LAST_VALUE(RAS.USER_ID) OVER (PARTITION BY CTE.TRANSFER_ID ORDER BY LAST_UPDATED) AS USER_ID,
LAST_VALUE(IFF(WI.STATE = 'CLOSED',WI.LAST_UPDATED,NULL) ) OVER (PARTITION BY CTE.TRANSFER_ID ORDER BY LAST_UPDATED) AS DATE_CLOSED
FROM CTE
         INNER JOIN FX.WORK_ITEM WI ON WI.REQUEST_ID = CTE.TRANSFER_ID
         INNER JOIN REPORTS.REPORT_ACTION_STEP RAS ON RAS.REQUEST_ID = CTE.TRANSFER_ID
         LEFT JOIN  SANDBOX_DB.SANDBOX_ALL.PKR_CLASSIFICATION PKRC ON PKRC.TRANSFER_ID = CTE.TRANSFER_ID

WHERE TRUE
 AND RAS.NOT_DUPLICATE = 1
 AND WI.TYPE = 'PROBLEMATIC_OOPS'
 AND CTE.TRANSFER_STATE = 'DPO')


-- CHECK IF USER HAS PERFORMED AT LEAST ONE TX AND IS ACTIVE
,BALANCE_CHECK AS (
    SELECT DISTINCT PROFILE_ID
        FROM MAIN_TABLE
        INNER JOIN BALANCE.ACCOUNT
            ON MAIN_TABLE.USER_PROFILE_ID = ACCOUNT.PROFILE_ID
        INNER JOIN BALANCE.BALANCE
            ON balance.account_id = account.id
        INNER JOIN BALANCE.TRANSACTION
            ON transaction.account_id = account.id
        WHERE TRUE
        and BALANCE.TYPE = 'STANDARD'
        AND ACCOUNT.ACTIVE = 1
    GROUP BY 1
    )


SELECT
TRANSFER_ID,
SOURCE_CURRENCY,
TARGET_CURRENCY,
AMOUNT_IN_SOURCE_CCY,
FEES_IN_SOURCE_CCY,
AMOUNT_IN_GBP,
LAST_UPDATED,
CATEGORY,
PAYIN_CHANNEL,
USER_PROFILE_ID,
USER_ID,
IFF(BV.PROFILE_ID IS NOT NULL,TRUE,FALSE) AS HAS_ACTIVE_BALANCE
FROM MAIN_TABLE
    LEFT JOIN BALANCE_CHECK BV ON BV.PROFILE_ID = MAIN_TABLE.USER_PROFILE_ID
WHERE TRUE
AND CATEGORY IN ('N4','N3')
AND WORK_ITEM_STATE != 'CLOSED'
AND AMOUNT_IN_GBP > 800