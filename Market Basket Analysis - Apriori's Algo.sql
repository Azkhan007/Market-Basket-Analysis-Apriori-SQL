-- DROP TABLE #TempA;
DECLARE @outputVariable INT;

-- Create a temporary table to store the result of CTE A
SELECT --19,838 non unique
    t.id
    , ITEM_SUBCLASS_NAME ITEM_DESCRIPTION
    , SUM(tp.ProductItmQty) AS Qty
INTO #TempA
FROM transactions t
JOIN TransactionProducts tp
    ON t.id = tp.TransactionId
JOIN products p
    ON tp.ProductId = p.id
JOIN Z_Product_4 zp
    ON p.sku = zp.BARCODE

WHERE CONVERT(DATE, t.[timestamp]) BETWEEN '2024-02-21' AND '2024-05-21'
    AND LocationId IN (37)
    AND t.TransactionTypeId IN (24)
    AND [Status] = 1
GROUP BY t.id
    , ITEM_SUBCLASS_NAME;

-- Calculate @outputVariable
SELECT @outputVariable = COUNT(DISTINCT id)
FROM #TempA;

-- select @outputVariable   
-- Use @outputVariable in subsequent query
WITH B
AS (
    --give row number to all items on each transaction, this means that last row num is basically the count of transactions in which the item occurs
    SELECT id
        , ITEM_DESCRIPTION
        , ROW_NUMBER() OVER (
            PARTITION BY ITEM_DESCRIPTION ORDER BY id DESC
            ) AS row_num
    FROM #TempA
    )
    , B1
AS (
    --now we find the max row number for each item , this means that we have the number of transactions in which an item exists, FOR EACH ITEM
    SELECT ITEM_DESCRIPTION
        , MAX(row_num) AS TRX_COUNT_1
    FROM B
    GROUP BY ITEM_DESCRIPTION
    )
    , B2
AS (
    --individual support of each item
    SELECT ITEM_DESCRIPTION
        , TRX_COUNT_1
        , (CAST(TRX_COUNT_1 AS DECIMAL) / @outputVariable) AS TRX_PROPORTION_1
    FROM B1
    )
    -- select *
    -- from b2 order by TRX_COUNT_1 desc
    , C
AS (
    --In how many transactions do any of these items exist together, and then we give row num to each transaction in which both co-exist
    SELECT B1.id
        , B1.ITEM_DESCRIPTION AS ITEM_DESCRIPTION1
        , B2.ITEM_DESCRIPTION AS ITEM_DESCRIPTION2
        , ROW_NUMBER() OVER (
            PARTITION BY B1.ITEM_DESCRIPTION
            , B2.ITEM_DESCRIPTION ORDER BY B1.id DESC
            ) AS row_num2
    FROM B AS B1
    JOIN B AS B2
        ON B1.id = B2.id
            AND B1.ITEM_DESCRIPTION != B2.ITEM_DESCRIPTION
    )
    -- select *
    -- from c order by ITEM_DESCRIPTION1,ITEM_DESCRIPTION2--row_num2 desc
    , D
AS (
    --Transactions containing both X and Y, and get the max count that means total transactions where both exist together (BASICALLY SUPPORT OF ITEM_SET)
    --                         Transactions containing both X and Y
    -- Support((X -> Y) = ------------------------------------------------------
    --                         Total number of transactions
    SELECT ITEM_DESCRIPTION1
        , ITEM_DESCRIPTION2
        , max(row_num2) AS trx_count
    FROM C
    GROUP BY ITEM_DESCRIPTION1
        , ITEM_DESCRIPTION2
        -- ORDER BY row_num2 DESC
    )
    -- select * from D
    -- order by  trx_count desc
    , E
AS (
    --This TRX_PROPORTION = the support of the item set, this means that it will be always bwtween 0 and 1 -- alomost zero chace of 1 
    --TOTAL SUPPORT FORMULA
    SELECT ITEM_DESCRIPTION1
        , ITEM_DESCRIPTION2
        , TRX_COUNT
        , (CAST(trx_count AS DECIMAL) / @outputVariable) AS TRX_PROPORTION
    FROM D
    )
    -- select *
    -- from E order by TRX_PROPORTION desc
    -- Final query using @outputVariable and CTEs
    -- SELECT  *
    -- FROM E
    -- ORDER BY TRX_PROPORTION DESC;
    -------------------------------------------------------------------------------------------------------
    --Now working for Confidence 
    , F
AS (
    --We join E with B2 to get the denominator for the formula of confidence
    SELECT E.ITEM_DESCRIPTION1
        , B2.TRX_PROPORTION_1
        , E.ITEM_DESCRIPTION2
        , E.TRX_COUNT
        , E.TRX_PROPORTION
    FROM E
    JOIN B2
        ON E.ITEM_DESCRIPTION1 = B2.ITEM_DESCRIPTION
            -- ORDER BY TRX_PROPORTION DESC
    )
    ,
    -- select *
    -- from F
TOTAL_SUPPORT
AS (
    SELECT F.ITEM_DESCRIPTION1 AS ANTECEDENT
        , F.TRX_PROPORTION_1 AS ANTECEDENT_SUPPORT
        , F.ITEM_DESCRIPTION2 AS CONSEQUENT
        , B2.TRX_PROPORTION_1 AS CONSEQUENT_SUPPORT
        , F.TRX_COUNT AS FREQUENCY
        , F.TRX_PROPORTION AS ITEMSET_SUPPORT
    FROM F
    JOIN B2
        ON F.ITEM_DESCRIPTION2 = B2.ITEM_DESCRIPTION
            -- where TRX_PROPORTION * 100 > 0.005
            -- ORDER BY TRX_PROPORTION DESC
    )
    ,
    -- select *
    -- from TOTAL_SUPPORT
    -- order by ITEMSET_SUPPORT desc
SUPPORT_CONFIDENCE_LIFT
AS (
    SELECT ANTECEDENT
        , ANTECEDENT_SUPPORT
        , CONSEQUENT
        , CONSEQUENT_SUPPORT
        , FREQUENCY
        , ITEMSET_SUPPORT
        , COALESCE(ITEMSET_SUPPORT / NULLIF(cast(ANTECEDENT_SUPPORT AS FLOAT), 0), 0) AS CONFIDENCE_AC
        , --Confidence(x->y) =    Transactions containing both X and Y
        ----------------------------------------
        --                              Transactions containing X
        COALESCE(ITEMSET_SUPPORT / NULLIF((cast(ANTECEDENT_SUPPORT AS FLOAT) * cast(CONSEQUENT_SUPPORT AS FLOAT)), 0), 0) AS LIFT_AC
    --LIFT(x->y)   =  (Transactions containing both X and containing X)
    -----------------------------------------------------
    --                     Fraction of transactions containing Y
    FROM TOTAL_SUPPORT
        -- WHERE ANTECEDENT_SUPPORT > 0.001 AND CONSEQUENT_SUPPORT > 0.001
    )
SELECT ANTECEDENT
    , ANTECEDENT_SUPPORT ANTECEDENT_SUPPORT
    , CONSEQUENT
    , CONSEQUENT_SUPPORT AS CONSEQUENT_SUPPORT
    , FREQUENCY AS FREQUENCY
    , ITEMSET_SUPPORT AS ITEMSET_SUPPORT
    , CONFIDENCE_AC AS CONFIDENCE_AC
    , LIFT_AC AS LIFT_AC
FROM SUPPORT_CONFIDENCE_LIFT
-- where FREQUENCY > 500 
-- where
-- ITEMSET_SUPPORT between 0.001 and 0.009
-- ANTECEDENT = 'F-DAY SPICES CORIANDER 45G' 
--     and CONSEQUENT = 'RADWA FRESH BREAST FILLET 450G'
-- LIFT_AC >= 6659
ORDER BY ITEMSET_SUPPORT DESC;

-- Drop the temporary table after use
DROP TABLE #TempA;
