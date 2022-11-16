/*
 Author: Numair Fazili
 Last Modified: 16/11/2022
 Description: Compute verification costs for receive INR customers
 Notes: Funnel based approach starting from business profiles created > account details issued > profiles verified > CS contacts
 */



/*
 Customers who created a business profile)
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
AND UPPER(user_profile.CUSTOMER_CLASS) = 'BUSINESS';

/*
 Customers for whom account details are issued (NB: account details can be issued without verification)
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
AND DA.ACCOUNT_NUMBER IS NOT NULL;

/*
 Returns customers which have account details and are verified - receive INR pursues active verification meaning verification starts after the first payment is received. CTE is used since there is a one to many mapping between user profile and verification_user_cost so we only extract the final verification cost and ignore the intermediaries.
 */


WITH VERIFIED_CUSTOMERS AS(SELECT VERIFICATION_METHOD,
       (verification_user_cost.USER_PROFILE_ID) AS VERIFIED_PROFILES,
       SUM(COUNT(DISTINCT verification_user_cost.USER_PROFILE_ID)) OVER() AS TOTAL_VERIFIED_PROFILES,
       MAX(cost) AS COSTS,
       MAX(COALESCE(TOTAL_COST_WITH_OVERHEAD,COST)) AS COSTS_WITH_OVERHEADS -- TOTAL_COST_WITH_OVERHEAD >= COST (can also be nULL)
FROM
    REPORTS.REGIONAL_USER_PROFILE_CHARACTERISTICS AS user_profile
INNER JOIN reports.verification_user_cost AS verification_user_cost
    ON verification_user_cost.USER_PROFILE_ID = user_profile.USER_PROFILE_ID
INNER JOIN DEPOSITACCOUNT.DEPOSIT_ACCOUNT  AS DA
    ON DA.profile_id = user_profile.USER_PROFILE_ID
INNER JOIN DEPOSITACCOUNT.BANK  AS DAB
    ON DAB.ID = DA.BANK_ID
WHERE TRUE
AND UPPER(user_profile.COUNTRY_CODE_3_CHAR) = 'IND'
AND UPPER(user_profile.CUSTOMER_CLASS) = 'BUSINESS'
AND UPPER(DAB.CURRENCY) IN ('USD','EUR','GBP')
GROUP BY VERIFICATION_METHOD,verification_user_cost.USER_PROFILE_ID
ORDER BY VERIFIED_PROFILES DESC)

SELECT
    VERIFICATION_METHOD,
    COUNT(VERIFIED_PROFILES) AS A_VERIFIED_PROFILES,
    MAX(TOTAL_VERIFIED_PROFILES) AS A_TOTAL_VERIFIED_PROFILES,
    SUM(COSTS_WITH_OVERHEADS) AS A_COSTS_WITH_OVERHEADS,
    (A_COSTS_WITH_OVERHEADS / A_TOTAL_VERIFIED_PROFILES) AS WEIGHTED_COST
FROM VERIFIED_CUSTOMERS
GROUP BY VERIFICATION_METHOD;

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
AND DA.ACCOUNT_NUMBER IS NOT NULL)

SELECT COUNT(USER_ID),COUNT(DISTINCT USER_ID),SUM(TOTAL_CONTACT_COST_GBP)
FROM REPORTS.COST_PER_CONTACT
INNER JOIN REPORTS.lookup_contact_calls ON lookup_contact_calls.CALL_ID = COST_PER_CONTACT.contact_id
WHERE TRUE
AND lookup_contact_calls.USER_ID IN (SELECT uid FROM CUSTOMERS_CS)


-- DEPRECATED --
-- SELECT VERIFICATION_METHOD,
--        COUNT(DISTINCT verification_user_cost.USER_PROFILE_ID) AS TOTAL_PROFILES,
--        sum(cost) AS COSTS,
--        SUM(COALESCE(TOTAL_COST_WITH_OVERHEAD,COST)) AS COSTS_WITH_OVERHEADS -- TOTAL_COST_WITH_OVERHEAD >= COST (can also be nULL)
-- FROM
--     REPORTS.REGIONAL_USER_PROFILE_CHARACTERISTICS AS user_profile
-- INNER JOIN reports.verification_user_cost AS verification_user_cost
--     ON verification_user_cost.USER_PROFILE_ID = user_profile.USER_PROFILE_ID
-- INNER JOIN DEPOSITACCOUNT.DEPOSIT_ACCOUNT  AS DA
--     ON DA.profile_id = user_profile.USER_PROFILE_ID
-- INNER JOIN DEPOSITACCOUNT.BANK  AS DAB
--     ON DAB.ID = DA.BANK_ID
-- WHERE TRUE
-- AND UPPER(user_profile.COUNTRY_CODE_3_CHAR) = 'IND'
-- AND UPPER(user_profile.CUSTOMER_CLASS) = 'BUSINESS'
-- AND UPPER(DAB.CURRENCY) IN ('USD','EUR','GBP')
-- GROUP BY VERIFICATION_METHOD
-- ORDER BY TOTAL_PROFILES DESC;


