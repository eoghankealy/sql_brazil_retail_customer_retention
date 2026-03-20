
/* ========================================================= 
   Time to Second Purchase Analysis
   
   PURPOSE:
   Measure how long it takes customers to make their
   second purchase after their first order.

   BUSINESS VALUE:
   Helps determine optimal timing for retention emails
   and repeat purchase campaigns.
   ========================================================= */

WITH customer_orders AS (

    SELECT 
        c.customer_unique_id,
        o.order_purchase_timestamp,
        
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp
        ) AS order_number,

        LAG(o.order_purchase_timestamp) OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp
        ) AS previous_order_date

    FROM cleaned.orders o
    JOIN cleaned.customers c 
        ON o.customer_id = c.customer_id

    WHERE o.order_status = 'delivered'
),

second_purchase_gap AS (

    SELECT
        customer_unique_id,
        (order_purchase_timestamp::date - previous_order_date::date) 
            AS days_between_orders
    FROM customer_orders

    WHERE order_number = 2
)

SELECT

    COUNT(*) AS customers_with_second_purchase,

    ROUND(AVG(days_between_orders),1) AS avg_days,

    PERCENTILE_CONT(0.5)
        WITHIN GROUP (ORDER BY days_between_orders) AS median_days,

    PERCENTILE_CONT(0.25)
        WITHIN GROUP (ORDER BY days_between_orders) AS p25_days,

    PERCENTILE_CONT(0.75)
        WITHIN GROUP (ORDER BY days_between_orders) AS p75_days,

    PERCENTILE_CONT(0.90)
        WITHIN GROUP (ORDER BY days_between_orders) AS p90_days,

    MIN(days_between_orders) AS min_days,
    MAX(days_between_orders) AS max_days

FROM second_purchase_gap;



/* =========================================================
   the output of the previous query is as follows:

   customers_with_second_purchase | avg_days | median_days | p25_days | p75_days | p90_days | min_days | max_days
2801                           | 81.2     | 29          | 0        | 126      | 246      | 0        | 609

 p25 = 0  Meaning 25% of repeat purchases happen on the same day.
This usually means:
Customers placed multiple orders in one shopping session.
For this reason i will run a new query that filters out same day purchases, so i get a true idea of time between shopping sessions rather
 than counting multiple purchases on the same day as separate events
   ========================================================= */


/* =========================================================
   NOTE:
   Same-day purchases are excluded because they often
   represent multiple orders within the same shopping
   session rather than a true repeat purchase behaviour.
   ========================================================= */

WITH customer_orders AS (

    SELECT 
        c.customer_unique_id,
        o.order_purchase_timestamp,
        
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp
        ) AS order_number,

        LAG(o.order_purchase_timestamp) OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp
        ) AS previous_order_date

    FROM cleaned.orders o
    JOIN cleaned.customers c
        ON o.customer_id = c.customer_id

    WHERE o.order_status = 'delivered'
),

second_purchase_gap AS (

    SELECT
        customer_unique_id,
        (order_purchase_timestamp::date - previous_order_date::date)
            AS days_between_orders
    FROM customer_orders

    WHERE order_number = 2
      AND (order_purchase_timestamp::date - previous_order_date::date) > 0
)

SELECT

    COUNT(*) AS customers_with_second_purchase,

    ROUND(AVG(days_between_orders),1) AS avg_days,

    PERCENTILE_CONT(0.5)
        WITHIN GROUP (ORDER BY days_between_orders) AS median_days,

    PERCENTILE_CONT(0.25)
        WITHIN GROUP (ORDER BY days_between_orders) AS p25_days,

    PERCENTILE_CONT(0.75)
        WITHIN GROUP (ORDER BY days_between_orders) AS p75_days,

    PERCENTILE_CONT(0.90)
        WITHIN GROUP (ORDER BY days_between_orders) AS p90_days,

    MIN(days_between_orders) AS min_days,
    MAX(days_between_orders) AS max_days

FROM second_purchase_gap;

/*
Output : 
customers_with_second_purchase | avg_days | median_days | p25_days | p75_days | p90_days | min_days | max_days
1972                           | 115.3    | 75          | 23       | 177      | 290.8    | 1        | 609

Comparing the first query and this query , 2801 - 1972 = 829 customers, 829 repeat purchases were the same day


| Percentile       | Meaning                      |
| ---------------- | ---------------------------- |
| P25 = 23 days    | 25% return within ~3 weeks   |
| Median = 75 days | typical repeat purchase      |
| P75 = 177 days   | 75% return within ~6 months  |
| P90 = 291 days   | 90% return within ~10 months |

*/

-- Distribution table also filtering for same day purchases

WITH customer_orders AS (

    SELECT 
        c.customer_unique_id,
        o.order_purchase_timestamp,
        
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp
        ) AS order_number,

        LAG(o.order_purchase_timestamp) OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp
        ) AS previous_order_date

    FROM cleaned.orders o
    JOIN cleaned.customers c
        ON o.customer_id = c.customer_id

    WHERE o.order_status = 'delivered'
),

second_purchase_gap AS (

    SELECT
        customer_unique_id,
        (order_purchase_timestamp::date - previous_order_date::date)
            AS days_between_orders
    FROM customer_orders

    WHERE order_number = 2
      AND (order_purchase_timestamp::date - previous_order_date::date) > 0
)

SELECT
    CASE
        WHEN days_between_orders <= 7 THEN '0–7 days'
        WHEN days_between_orders <= 30 THEN '8–30 days'
        WHEN days_between_orders <= 90 THEN '31–90 days'
        WHEN days_between_orders <= 180 THEN '91–180 days'
        ELSE '180+ days'
    END AS purchase_window,

    COUNT(*) AS customers

FROM second_purchase_gap

GROUP BY purchase_window
ORDER BY customers DESC;


/*

| Purchase Window | Customers |
| --------------- | --------- |
| 31-90 days      | 492       |
| 180+ days       | 480       |
| 91-180 days     | 413       |
| 8-30 days       | 388       |
| 0-7 days        | 199       |

*/





/* =========================================================
   Customer Churn Risk Analysis
   
   PURPOSE:
   Identify customers who have not purchased within
   the expected repurchase window.

   BUSINESS VALUE:
   Creates a target list for retention and win-back
   marketing campaigns.
   ========================================================= */

WITH customer_last_purchase AS (

    SELECT
        c.customer_unique_id,
        MAX(o.order_purchase_timestamp)::date AS last_purchase_date,
        COUNT(o.order_id) AS total_orders
    FROM cleaned.orders o
    JOIN cleaned.customers c
        ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),

dataset_date AS (

    SELECT 
        MAX(order_purchase_timestamp)::date AS dataset_last_date
    FROM cleaned.orders
),

customer_inactivity AS (

    SELECT
        clp.customer_unique_id,
        clp.total_orders,
        clp.last_purchase_date,
        d.dataset_last_date,

        (d.dataset_last_date - clp.last_purchase_date) AS days_since_last_purchase

    FROM customer_last_purchase clp
    CROSS JOIN dataset_date d
)

SELECT

    CASE
        WHEN days_since_last_purchase <= 75 THEN 'Active'
        WHEN days_since_last_purchase <= 150 THEN 'At Risk'
        ELSE 'Likely Churned'
    END AS customer_status,

    COUNT(*) AS customers

FROM customer_inactivity

GROUP BY customer_status
ORDER BY customers DESC;


/* 

Results: 

| Customer Status | Customers |
| --------------- | --------- |
| Likely Churned  | 73,333    |
| At Risk         | 14,309    |
| Active          | 5,716     |

Customer churn risk was estimated using inactivity thresholds derived from the repeat purchase analysis. 
The median time between a customer's first and second purchase was approximately 75 days, which was used as the expected repurchase cycle.
 Customers who purchased within the last 75 days were classified as Active, as they remain within the typical purchasing window. 
 Customers inactive for 75-150 days were labelled At Risk, having exceeded one expected repurchase cycle but still within a plausible return period. 
 Customers inactive for more than 150 days (two purchase cycles) were classified as Likely Churned, 
 as the probability of returning declines significantly beyond this point. 
 This segmentation creates a practical framework for retention marketing, allowing businesses to target At Risk customers with reminder campaigns and
  Likely Churned customers with stronger win-back incentives.
*/