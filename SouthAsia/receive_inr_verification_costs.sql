/*
 Author: Numair Fazili
 Last Modified: 16/11/2022
 Description: Compute verification costs for receive INR customers
 Notes: Funnel based approach starting from business profiles created > account details issued > profiles verified > CS contacts
 */



/*
 Customers who created a business profile - START DATE 1 JUNE 2022 (TBC)
 */

SELECT
COUNT(DISTINCT user_profile.USER_PROFILE_ID)
FROM
    REPORTS.REGIONAL_USER_PROFILE_CHARACTERISTICS AS user_profile
LEFT JOIN reports.verification_user_cost AS verification_user_cost
    ON verification_user_cost.USER_PROFILE_ID = user_profile.USER_PROFILE_ID
LEFT JOIN DEPOSITACCOUNT.DEPOSIT_ACCOUNT  AS DA
    ON DA.profile_id = user_profile.USER_PROFILE_ID
LEFT JOIN DEPOSITACCOUNT.BANK  AS DAB
    ON DAB.ID = DA.BANK_ID
WHERE TRUE
AND UPPER(user_profile.COUNTRY_CODE_3_CHAR) = 'IND'
AND UPPER(user_profile.CUSTOMER_CLASS) = 'BUSINESS'
AND USER_PROFILE_CREATED >= '2022-05-01';

/*
 Customers for whom account details were issued (NB: account details can be issued without verification)
 */

SELECT
COUNT(DISTINCT DA.PROFILE_ID)
FROM
    REPORTS.REGIONAL_USER_PROFILE_CHARACTERISTICS AS user_profile
LEFT JOIN reports.verification_user_cost AS verification_user_cost
    ON verification_user_cost.USER_PROFILE_ID = user_profile.USER_PROFILE_ID
LEFT JOIN DEPOSITACCOUNT.DEPOSIT_ACCOUNT  AS DA
    ON DA.profile_id = user_profile.USER_PROFILE_ID
LEFT JOIN DEPOSITACCOUNT.BANK  AS DAB
    ON DAB.ID = DA.BANK_ID
WHERE TRUE
AND UPPER(user_profile.COUNTRY_CODE_3_CHAR) = 'IND'
AND UPPER(user_profile.CUSTOMER_CLASS) = 'BUSINESS'
AND UPPER(DAB.CURRENCY) IN ('USD','EUR','GBP')
AND DA.ACCOUNT_NUMBER IS NOT NULL
AND USER_PROFILE_CREATED >= '2022-05-01';

/*
 Returns customers which have account details and are verified - receive INR pursues active verification meaning verification starts after the first payment is received.
 */

SELECT VERIFICATION_METHOD,
       COUNT(DISTINCT VUC.USER_PROFILE_ID) AS VERIFIED_PROFILES,
       SUM(COUNT(DISTINCT VUC.USER_PROFILE_ID)) OVER() AS TOTAL_VERIFIED_PROFILES,
       SUM(cost) AS COSTS,
       SUM(COALESCE(TOTAL_COST_WITH_OVERHEAD,COST)) AS COSTS_WITH_OVERHEADS, -- TOTAL_COST_WITH_OVERHEAD >= COST (can also be nULL)
       COSTS_WITH_OVERHEADS/TOTAL_VERIFIED_PROFILES AS WEIGHTED_COST
FROM
    REPORTS.REGIONAL_USER_PROFILE_CHARACTERISTICS AS user_profile
INNER JOIN reports.verification_user_cost AS VUC
    ON VUC.USER_PROFILE_ID = user_profile.USER_PROFILE_ID
INNER JOIN DEPOSITACCOUNT.DEPOSIT_ACCOUNT  AS DA
    ON DA.profile_id = user_profile.USER_PROFILE_ID
INNER JOIN DEPOSITACCOUNT.BANK  AS DAB
    ON DAB.ID = DA.BANK_ID
WHERE TRUE
AND UPPER(user_profile.COUNTRY_CODE_3_CHAR) = 'IND'
AND UPPER(user_profile.CUSTOMER_CLASS) = 'BUSINESS'
AND UPPER(DAB.CURRENCY) IN ('USD','EUR','GBP')
AND USER_PROFILE_CREATED >= '2022-05-01'
GROUP BY VERIFICATION_METHOD
ORDER BY VERIFIED_PROFILES DESC;


/*
 Identifying Customers who performed al least one successful TX
 */
SELECT
    COUNT(DISTINCT PAYMENT_REQUEST.PROFILE_ID)
FROM
REPORTS.REGIONAL_USER_PROFILE_CHARACTERISTICS AS UP
LEFT JOIN DEPOSITACCOUNT.DEPOSIT_ACCOUNT  AS DA
    ON DA.profile_id = UP.USER_PROFILE_ID
LEFT JOIN DEPOSITACCOUNT.BANK  AS DAB
    ON DAB.ID = DA.BANK_ID
LEFT JOIN PAYMENT_REQUEST.PAYMENT_REQUEST
    ON PAYMENT_REQUEST.PROFILE_ID = UP.USER_PROFILE_ID
WHERE TRUE
AND UPPER(UP.COUNTRY_CODE_3_CHAR) = 'IND'
AND UPPER(UP.CUSTOMER_CLASS) = 'BUSINESS'
AND DA.ACCOUNT_NUMBER IS NOT NULL
AND USER_PROFILE_CREATED >= '2022-05-01'
AND PAYMENT_REQUEST.STATUS = 'COMPLETED';


/*
 Computing cost of customer contacts - CTE returns verified customers with account details and the subsequent query returns the CS costs for these users (NB costs are defined at user level and not profile level - so this represents an upper bound over the total cost (personal + business))
 */

WITH CUSTOMERS_CS AS (
SELECT DISTINCT up.USER_ID AS UID
FROM
    REPORTS.REGIONAL_USER_PROFILE_CHARACTERISTICS AS user_profile
LEFT JOIN reports.verification_user_cost AS verification_user_cost
    ON verification_user_cost.USER_PROFILE_ID = user_profile.USER_PROFILE_ID
LEFT JOIN DEPOSITACCOUNT.DEPOSIT_ACCOUNT  AS DA
    ON DA.profile_id = user_profile.USER_PROFILE_ID
LEFT JOIN DEPOSITACCOUNT.BANK  AS DAB
    ON DAB.ID = DA.BANK_ID
LEFT JOIN PROFILE.USER_PROFILE up
    ON up.ID = user_profile.USER_PROFILE_ID
WHERE TRUE
AND UPPER(user_profile.COUNTRY_CODE_3_CHAR) = 'IND'
AND UPPER(user_profile.CUSTOMER_CLASS) = 'BUSINESS'
AND UPPER(DAB.CURRENCY) IN ('USD','EUR','GBP')
AND DA.ACCOUNT_NUMBER IS NOT NULL
AND USER_PROFILE_CREATED >= '2022-05-01')

SELECT COUNT(USER_ID),COUNT(DISTINCT USER_ID),SUM(TOTAL_CONTACT_COST_GBP)
FROM REPORTS.COST_PER_CONTACT
INNER JOIN REPORTS.lookup_contact_calls ON lookup_contact_calls.CALL_ID = COST_PER_CONTACT.contact_id
WHERE TRUE
AND lookup_contact_calls.USER_ID IN (SELECT uid FROM CUSTOMERS_CS);

/*
 Summarise costs from Customer Economics
 */


SELECT
    COUNT(DISTINCT CE.USER_PROFILE_ID),
    AVG(COGS_TOTAL) AS COGS_AVG_COST,
    AVG(SERVICING_COST_TOTAL) AS SERVICING_AVG_COST,
    SUM(COGS_TOTAL) AS COGS_TOTAL_COST,
    SUM(SERVICING_COST_TOTAL) AS SERVICING_TOTAL_COST,
    SUM(NET_REVENUE_GBP - CE.COGS_TOTAL - CE.SERVICING_COST_TOTAL) AS CONTIBUTION_MARGIN,
    AVG(NET_REVENUE_GBP - CE.COGS_TOTAL - CE.SERVICING_COST_TOTAL) AS AVG_CONTIBUTION_MARGIN,
    SUM(CE.TRANSACTION_COUNT)/COUNT(DISTINCT CE.USER_PROFILE_ID) AS AVG_TX
FROM
REPORTS.REGIONAL_USER_PROFILE_CHARACTERISTICS AS UP
LEFT JOIN REPORTS.CUSTOMER_ECON_DATASET_PUBLIC CE
    ON CE.USER_PROFILE_ID = UP.USER_PROFILE_ID
LEFT JOIN DEPOSITACCOUNT.DEPOSIT_ACCOUNT  AS DA
    ON DA.profile_id = UP.USER_PROFILE_ID
LEFT JOIN DEPOSITACCOUNT.BANK  AS DAB
    ON DAB.ID = DA.BANK_ID
WHERE TRUE
AND UPPER(UP.COUNTRY_CODE_3_CHAR) = 'IND'
AND UPPER(UP.CUSTOMER_CLASS) = 'BUSINESS'
AND DA.ACCOUNT_NUMBER IS NOT NULL
AND USER_PROFILE_CREATED >= '2022-05-01'

