

/*

 Author: Numair Fazili
 Email: numair.fazili@transferwise.com
 Role: Regional Product Analyst (APAC)
 Description: This Table is used to identify the transfers affected by the PKR double payout incident. This table must be used in conjunction with CHANGE LOG to get the latest view

 */

/*
FINDING ALL AFFECTED TRANSFERS
*/

CREATE OR REPLACE TABLE {{params.reports}}.PKR_MASTER_TABLE AS (

WITH affected_transfers AS (SELECT cpoi.sender_id as affected_transfer
                            FROM payout.core_payout_instruction cpoi
                            WHERE cpoi.transfer_method = 'BALF'
                              and exists(select 1
                                         from fx.bank_transaction_link btl,
                                              bss.bank_transaction bt
                                         where btl.payout_instruction_id = cpoi.id
                                           and btl.bank_transaction_id = bt.id
                                           and btl.link_type = 'BOUNCE'
                                           and bt.source_file_id = 393099018)
                              and cpoi.time_created >= '2022-09-30'),

/*
FINDING PAYOUTS AND CREATING SKELETON FOR MASTER TABLE
*/

     num_payouts AS (SELECT COUNT(*)                        as pcount,
                            ats.affected_transfer           as transfer_id,
                            IFF(COUNT(*) > 1, 'DPO', 'SPO') as PAYOUT_CLASSIFICATION -- IF COUNT > 1 THEN DPO: DOUBLE PAYOUT ELSE SPO: SINGLE PAYOUT - NOTE: THIS IS NOT THE FINAL CLASSIFICATION AND FURTHER UPDATES FOLLOW
                     FROM payout.core_payout_instruction poi,
                          affected_transfers ats
                     WHERE poi.sender_id = ats.affected_transfer
                       and poi.state IN ('TRANSFERRED', 'REJECTED') -- REJECTED IS USED TO COVER CASE WHERE TRANSFER IS FAKE REJECTED AND REFUNDED
                     GROUP BY ats.affected_transfer),
     double_payout as (SELECT DISTINCT(np.transfer_id)                                                                as transfer_id
                                     , first_value(poi.id) over (partition by np.transfer_id order by poi.id)         as first_poi
                                     , first_value(poi.STATE)
                                                   over (partition by np.transfer_id order by poi.id)                 as first_poi_state -- USED IN CONJUNCTION WITH LAST_POI_STATE TO IDENTIFY FAKE REJECTS
                                     , last_value(poi.id) over (partition by np.transfer_id order by poi.id)          as last_poi
                                     , last_value(poi.STATE)
                                                  over (partition by np.transfer_id order by poi.id)                  as last_poi_state
                                     , first_value(poi.PAYOUT_TYPE)
                                                   over (partition by np.transfer_id order by poi.id)                 as FIRST_PAYOUT_TYPE  -- USED IN CONJUNCTION WITH LAST_PAYOUT_TYPE TO IDENTIFY CASES WITH EXCESS REFUND
                                     , last_value(poi.PAYOUT_TYPE)
                                                  over (partition by np.transfer_id order by poi.id)                  as LAST_PAYOUT_TYPE
                                     , PAYOUT_CLASSIFICATION
                       from payout.core_payout_instruction poi,
                            num_payouts np
                       WHERE poi.sender_id = np.transfer_id),

/*
UPDATING RECORDS WHERE FIRST AND LAST POI STATES ARE T-R OR R-R AS SPO. THE CURRENT UNDERSTANDING IS THAT THESE ARE TRUE REJECTS. IN THE EVENT THIS LOGIC IS MODIFIED, THE UPDATES WILL BE REFLECTED IN CHANGE LOG
*/

     double_payout_w_rejected as (SELECT distinct dp.transfer_id,
                                                  dp.first_poi                                as first_poi_id,
                                                  dp.first_poi_state                          as first_poi_state,
                                                  dp.last_poi                                    last_poi_id,
                                                  dp.last_poi_state                           as last_poi_state,
                                                  FIRST_PAYOUT_TYPE,
                                                  LAST_PAYOUT_TYPE,
                                                  IFF(
                                                              (dp.first_poi_state = 'TRANSFERRED' AND dp.last_poi_state = 'REJECTED') OR
                                                              (dp.first_poi_state = 'REJECTED' AND dp.last_poi_state = 'REJECTED'),
                                                              'SPO', dp.PAYOUT_CLASSIFICATION) as PAYOUT_CLASSIFICATION
                                  from double_payout dp),

/*
MARK CASES WHERE EXCESS REFUND WAS ISSUED AS SPO. FOR THESE RECORDS THE SECOND POI WAS AN EXCESS REFUND AND NOT A TOTAL REFUND
*/


     single_payout_w_excess_refund as (SELECT distinct dp.transfer_id,
                                                       dp.first_poi_id                  as first_poi_id,
                                                       dp.first_poi_state               as first_poi_state,
                                                       dp.last_poi_id                      last_poi_id,
                                                       dp.last_poi_state                as last_poi_state,
                                                       FIRST_PAYOUT_TYPE,
                                                       LAST_PAYOUT_TYPE,
                                                       IFF(FIRST_PAYOUT_TYPE = 'TARGET' and LAST_PAYOUT_TYPE = 'REFUND',
                                                           'SPO', PAYOUT_CLASSIFICATION) as PAYOUT_CLASSIFICATION
                                       from double_payout_w_rejected dp)

SELECT masterTable.*, TT.STATE as TRANSFER_STATE,TT.SOURCE_CURRENCY,TT.SOURCE_VALUE
FROM single_payout_w_excess_refund as masterTable
         LEFT JOIN TRANSFER.TRANSFER TT ON TT.ID = masterTable.transfer_id);



