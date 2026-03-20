
------------------------- see is delviery the problem

WITH snapshot AS (
    SELECT MAX(order_purchase_timestamp)::DATE AS snapshot_date
    FROM cleaned.orders
),
repeat_customers AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS frequency,
        SUM(p.payment_value) AS monetary,
        MAX(o.order_purchase_timestamp)::DATE AS last_order_date
    FROM cleaned.orders o
    JOIN cleaned.customers c ON o.customer_id = c.customer_id
    JOIN cleaned.order_payments p ON o.order_id = p.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
    HAVING COUNT(DISTINCT o.order_id) > 1
),
rfm_base AS (
    SELECT
        r.customer_unique_id,
        r.frequency,
        r.monetary,
        (s.snapshot_date - r.last_order_date) AS recency_days
    FROM repeat_customers r
    CROSS JOIN snapshot s
),
rfm_scored AS (
    SELECT
        customer_unique_id,
        recency_days,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM rfm_base
),
customer_segments AS (
    SELECT
        customer_unique_id,
        CASE 
            WHEN frequency >= 5 
              OR (r_score >= 4 AND f_score >= 4 AND m_score >= 4)
            THEN 'VIP Elite'
            
            WHEN r_score >= 4 AND m_score >= 3
            THEN 'Active & Engaged'
            
            WHEN r_score >= 3
            THEN 'Active - Needs Nurturing'
            
            WHEN r_score = 2 AND (f_score >= 3 OR m_score >= 3)
            THEN 'Lapsed - Recovery Target'
            
            ELSE 'Churned'
        END AS segment
    FROM rfm_scored
),
delivery_analysis AS (
    SELECT
        cs.segment,
        o.order_id,
        o.customer_id,
        o.order_purchase_timestamp,
        o.order_estimated_delivery_date,
        o.order_delivered_customer_date,
        
        -- Calculate delivery metrics
        EXTRACT(DAY FROM o.order_delivered_customer_date - o.order_purchase_timestamp) AS actual_delivery_days,
        EXTRACT(DAY FROM o.order_estimated_delivery_date - o.order_purchase_timestamp) AS estimated_delivery_days,
        EXTRACT(DAY FROM o.order_delivered_customer_date - o.order_estimated_delivery_date) AS delay_days,
        
        -- Was it late?
        CASE 
            WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date 
            THEN 1 
            ELSE 0 
        END AS is_late
        
    FROM cleaned.orders o
    JOIN cleaned.customers c ON o.customer_id = c.customer_id
    JOIN customer_segments cs ON c.customer_unique_id = cs.customer_unique_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)

-- Summary by segment
SELECT
    segment,
    COUNT(*) AS total_orders,
    
    -- Delivery time metrics
    ROUND(AVG(actual_delivery_days), 1) AS avg_actual_delivery_days,
    ROUND(AVG(estimated_delivery_days), 1) AS avg_estimated_delivery_days,
    
    -- Late delivery metrics
    SUM(is_late) AS late_deliveries,
    ROUND(100.0 * SUM(is_late) / COUNT(*), 2) AS late_delivery_pct,
    
    -- Among late deliveries, how late?
    ROUND(AVG(CASE WHEN is_late = 1 THEN delay_days END), 1) AS avg_delay_when_late,
    
    -- Worst case scenarios
    MAX(CASE WHEN is_late = 1 THEN delay_days END) AS max_delay_days,
    
    -- On-time performance
    ROUND(100.0 * SUM(CASE WHEN is_late = 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS on_time_pct

FROM delivery_analysis
GROUP BY segment
ORDER BY 
    CASE segment
        WHEN 'Lapsed - Recovery Target' THEN 1  -- Put Lapsed first for comparison
        WHEN 'VIP Elite' THEN 2
        WHEN 'Active & Engaged' THEN 3
        WHEN 'Active - Needs Nurturing' THEN 4
        WHEN 'Churned' THEN 5
    END;





----- compare the 97% to 3% delivery delays

WITH customer_order_counts AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS frequency
    FROM cleaned.orders o
    JOIN cleaned.customers c 
        ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),

customer_type AS (
    SELECT
        customer_unique_id,
        CASE 
            WHEN frequency > 1 THEN 'Repeat (3%)'
            ELSE 'One-Time (97%)'
        END AS customer_group
    FROM customer_order_counts
),

delivery_analysis AS (
    SELECT
        ct.customer_group,
        o.order_id,
        o.order_purchase_timestamp,
        o.order_estimated_delivery_date,
        o.order_delivered_customer_date,
        
        -- Delivery time calculations
        EXTRACT(DAY FROM o.order_delivered_customer_date 
                - o.order_purchase_timestamp) AS actual_delivery_days,
        
        EXTRACT(DAY FROM o.order_estimated_delivery_date 
                - o.order_purchase_timestamp) AS estimated_delivery_days,
        
        EXTRACT(DAY FROM o.order_delivered_customer_date 
                - o.order_estimated_delivery_date) AS delay_days,
        
        CASE 
            WHEN o.order_delivered_customer_date 
                 > o.order_estimated_delivery_date 
            THEN 1 ELSE 0 
        END AS is_late

    FROM cleaned.orders o
    JOIN cleaned.customers c 
        ON o.customer_id = c.customer_id
    JOIN customer_type ct 
        ON c.customer_unique_id = ct.customer_unique_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)

SELECT
    customer_group,
    COUNT(*) AS total_orders,
    
    ROUND(AVG(actual_delivery_days), 2) AS avg_actual_delivery_days,
    ROUND(AVG(estimated_delivery_days), 2) AS avg_estimated_delivery_days,
    
    SUM(is_late) AS late_deliveries,
    ROUND(100.0 * SUM(is_late) / COUNT(*), 2) AS late_delivery_pct,
    
    ROUND(AVG(CASE WHEN is_late = 1 THEN delay_days END), 2) AS avg_delay_when_late,
    
    ROUND(100.0 * SUM(CASE WHEN is_late = 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS on_time_pct

FROM delivery_analysis
GROUP BY customer_group;


/* =========================================================
   Review Score Comparison: One-Time vs Repeat Customers
   
   HYPOTHESIS: Perhaps one-time buyers (97%) had worse experiences
   than repeat customers (3%), which explains why they never returned.
   
   We'll compare:
   - Average review scores
   - Distribution of ratings (1-5 stars)
   - Review rate (% who left reviews)
   - Negative review rates
   ========================================================= */

WITH customer_classification AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS total_orders,
        CASE 
            WHEN COUNT(DISTINCT o.order_id) = 1 THEN 'One-Time Buyer (97%)'
            ELSE 'Repeat Customer (3%)'
        END AS customer_type
    FROM cleaned.orders o
    JOIN cleaned.customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
customer_reviews AS (
    SELECT
        cc.customer_type,
        cc.customer_unique_id,
        o.order_id,
        r.review_id,
        r.review_score,
        o.order_purchase_timestamp
    FROM cleaned.orders o
    JOIN cleaned.customers c ON o.customer_id = c.customer_id
    JOIN customer_classification cc ON c.customer_unique_id = cc.customer_unique_id
    LEFT JOIN cleaned.order_reviews r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
)

SELECT
    customer_type,
    
    -- Customer and order counts
    COUNT(DISTINCT customer_unique_id) AS total_customers,
    COUNT(DISTINCT order_id) AS total_orders,
    
    -- Review engagement
    COUNT(DISTINCT CASE WHEN review_score IS NOT NULL THEN order_id END) AS orders_with_reviews,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN review_score IS NOT NULL THEN order_id END) / 
          COUNT(DISTINCT order_id), 2) AS review_rate_pct,
    
    -- Average review scores
    ROUND(AVG(review_score), 2) AS avg_review_score,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY review_score)::NUMERIC, 1) AS median_review_score,
    
    -- Score distribution
    ROUND(100.0 * SUM(CASE WHEN review_score = 5 THEN 1 ELSE 0 END) / 
          NULLIF(COUNT(review_score), 0), 2) AS pct_5_star,
    ROUND(100.0 * SUM(CASE WHEN review_score = 4 THEN 1 ELSE 0 END) / 
          NULLIF(COUNT(review_score), 0), 2) AS pct_4_star,
    ROUND(100.0 * SUM(CASE WHEN review_score = 3 THEN 1 ELSE 0 END) / 
          NULLIF(COUNT(review_score), 0), 2) AS pct_3_star,
    ROUND(100.0 * SUM(CASE WHEN review_score = 2 THEN 1 ELSE 0 END) / 
          NULLIF(COUNT(review_score), 0), 2) AS pct_2_star,
    ROUND(100.0 * SUM(CASE WHEN review_score = 1 THEN 1 ELSE 0 END) / 
          NULLIF(COUNT(review_score), 0), 2) AS pct_1_star,
    
    -- Negative review metrics (1-2 stars)
    SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) AS negative_reviews,
    ROUND(100.0 * SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) / 
          NULLIF(COUNT(review_score), 0), 2) AS negative_review_pct,
    
    -- Total reviews
    COUNT(review_score) AS total_reviews

FROM customer_reviews
GROUP BY customer_type
ORDER BY 
    CASE customer_type
        WHEN 'Repeat Customer (3%)' THEN 1
        ELSE 2
    END;



/* =========================================================
   Top 5 Categories: One-Time vs Repeat Customers (Side-by-Side)
   ========================================================= */

WITH customer_classification AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS total_orders,
        CASE 
            WHEN COUNT(DISTINCT o.order_id) = 1 THEN 'One-Time'
            ELSE 'Repeat'
        END AS customer_type
    FROM cleaned.orders o
    JOIN cleaned.customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
customer_purchases AS (
    SELECT
        cc.customer_type,
        cc.customer_unique_id,
        o.order_id,
        COALESCE(t.product_category_name_english, p.product_category_name, 'Unknown') AS category
    FROM cleaned.orders o
    JOIN cleaned.customers c ON o.customer_id = c.customer_id
    JOIN customer_classification cc ON c.customer_unique_id = cc.customer_unique_id
    JOIN cleaned.order_items oi ON o.order_id = oi.order_id
    JOIN cleaned.products p ON oi.product_id = p.product_id
    LEFT JOIN cleaned.product_category_name_translation t 
        ON p.product_category_name = t.product_category_name
    WHERE o.order_status = 'delivered'
),
category_counts AS (
    SELECT
        customer_type,
        category,
        COUNT(DISTINCT customer_unique_id) AS customer_count,
        COUNT(DISTINCT order_id) AS order_count
    FROM customer_purchases
    GROUP BY customer_type, category
),
ranked_categories AS (
    SELECT
        customer_type,
        category,
        customer_count,
        order_count,
        ROW_NUMBER() OVER (PARTITION BY customer_type ORDER BY customer_count DESC) AS rank
    FROM category_counts
)

-- Get top 5 for each type
SELECT
    MAX(CASE WHEN customer_type = 'Repeat' THEN category END) AS repeat_top_category,
    MAX(CASE WHEN customer_type = 'Repeat' THEN customer_count END) AS repeat_customers,
    MAX(CASE WHEN customer_type = 'Repeat' THEN order_count END) AS repeat_orders,
    
    MAX(CASE WHEN customer_type = 'One-Time' THEN category END) AS onetime_top_category,
    MAX(CASE WHEN customer_type = 'One-Time' THEN customer_count END) AS onetime_customers,
    MAX(CASE WHEN customer_type = 'One-Time' THEN order_count END) AS onetime_orders
    
FROM ranked_categories
WHERE rank <= 5
GROUP BY rank
ORDER BY rank;


/* =========================================================
   Category Repeat Rate Analysis
   
   Shows which categories have the highest % of repeat customers.
   This identifies "loyalty-driving" categories.
   ========================================================= */

WITH all_customers AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS total_orders
    FROM cleaned.orders o
    JOIN cleaned.customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
customer_first_purchase AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        COALESCE(t.product_category_name_english, p.product_category_name, 'Unknown') AS first_category,
        ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp ASC) AS order_num
    FROM cleaned.orders o
    JOIN cleaned.customers c ON o.customer_id = c.customer_id
    JOIN cleaned.order_items oi ON o.order_id = oi.order_id
    JOIN cleaned.products p ON oi.product_id = p.product_id
    LEFT JOIN cleaned.product_category_name_translation t 
        ON p.product_category_name = t.product_category_name
    WHERE o.order_status = 'delivered'
),
first_category_only AS (
    SELECT
        customer_unique_id,
        first_category
    FROM customer_first_purchase
    WHERE order_num = 1
),
category_repeat_rates AS (
    SELECT
        fc.first_category AS category,
        COUNT(DISTINCT fc.customer_unique_id) AS total_customers,
        SUM(CASE WHEN ac.total_orders > 1 THEN 1 ELSE 0 END) AS repeat_customers,
        ROUND(100.0 * SUM(CASE WHEN ac.total_orders > 1 THEN 1 ELSE 0 END) / 
              COUNT(DISTINCT fc.customer_unique_id), 2) AS repeat_rate_pct
    FROM first_category_only fc
    JOIN all_customers ac ON fc.customer_unique_id = ac.customer_unique_id
    GROUP BY fc.first_category
    HAVING COUNT(DISTINCT fc.customer_unique_id) >= 100  -- At least 100 customers for statistical significance
)

SELECT
    category,
    total_customers,
    repeat_customers,
    repeat_rate_pct,
    
    -- Rank by repeat rate
    RANK() OVER (ORDER BY repeat_rate_pct DESC) AS repeat_rate_rank,
    
    -- Rank by total customers
    RANK() OVER (ORDER BY total_customers DESC) AS volume_rank

FROM category_repeat_rates
ORDER BY repeat_rate_pct DESC
LIMIT 20;


/* =========================================================
   Category Repeat Rate Analysis
   
   Shows which categories have the highest % of repeat customers.
   ========================================================= */

WITH all_customers AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS total_orders
    FROM cleaned.orders o
    JOIN cleaned.customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
customer_first_purchase AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        COALESCE(t.product_category_name_english, p.product_category_name, 'Unknown') AS first_category,
        ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp ASC) AS order_num
    FROM cleaned.orders o
    JOIN cleaned.customers c ON o.customer_id = c.customer_id
    JOIN cleaned.order_items oi ON o.order_id = oi.order_id
    JOIN cleaned.products p ON oi.product_id = p.product_id
    LEFT JOIN cleaned.product_category_name_translation t 
        ON p.product_category_name = t.product_category_name
    WHERE o.order_status = 'delivered'
),
first_category_only AS (
    SELECT
        customer_unique_id,
        first_category
    FROM customer_first_purchase
    WHERE order_num = 1
),
category_repeat_rates AS (
    SELECT
        fc.first_category AS category,
        COUNT(DISTINCT fc.customer_unique_id) AS total_customers,
        SUM(CASE WHEN ac.total_orders > 1 THEN 1 ELSE 0 END) AS repeat_customers,
        ROUND(100.0 * SUM(CASE WHEN ac.total_orders > 1 THEN 1 ELSE 0 END) / 
              COUNT(DISTINCT fc.customer_unique_id), 2) AS repeat_rate_pct
    FROM first_category_only fc
    JOIN all_customers ac ON fc.customer_unique_id = ac.customer_unique_id
    GROUP BY fc.first_category
    HAVING COUNT(DISTINCT fc.customer_unique_id) >= 100  -- At least 100 customers
)

SELECT
    category,
    total_customers,
    repeat_customers,
    repeat_rate_pct,
    
    -- Show how far above/below the 3% baseline
    ROUND(repeat_rate_pct - 3.0, 2) AS vs_baseline

FROM category_repeat_rates
ORDER BY repeat_rate_pct DESC
LIMIT 20;


/* =========================================================
   Q7: Carrier Handoff Analysis (Operational Deep-Dive)
   Using the Repeat-Customer RFM Segments as a filter.
   ========================================================= */

WITH snapshot AS (
    SELECT MAX(order_purchase_timestamp)::DATE AS snapshot_date
    FROM cleaned.orders
),
repeat_customers AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS frequency,
        SUM(p.payment_value) AS monetary,
        MAX(o.order_purchase_timestamp)::DATE AS last_order_date
    FROM cleaned.orders o
    JOIN cleaned.customers c ON o.customer_id = c.customer_id
    JOIN cleaned.order_payments p ON o.order_id = p.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
    HAVING COUNT(DISTINCT o.order_id) > 1
),
rfm_base AS (
    SELECT
        r.customer_unique_id,
        r.frequency,
        r.monetary,
        (s.snapshot_date - r.last_order_date) AS recency_days
    FROM repeat_customers r
    CROSS JOIN snapshot s
),
rfm_scored AS (
    SELECT
        customer_unique_id,
        recency_days,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM rfm_base
),
customer_segments AS (
    SELECT
        customer_unique_id,
        CASE 
            WHEN frequency >= 5 
              OR (r_score >= 4 AND f_score >= 4 AND m_score >= 4)
            THEN 'VIP Elite'
            WHEN r_score >= 4 AND m_score >= 3
            THEN 'Active & Engaged'
            WHEN r_score >= 3
            THEN 'Active - Needs Nurturing'
            WHEN r_score = 2 AND (f_score >= 3 OR m_score >= 3)
            THEN 'Lapsed - Recovery Target'
            ELSE 'Churned'
        END AS segment
    FROM rfm_scored
),
handoff_metrics AS (
    SELECT 
        cs.segment,
        o.order_id,
        o.order_purchase_timestamp,
        o.order_delivered_carrier_date,
        -- Calculate the processing time (handoff) in days
        EXTRACT(EPOCH FROM (o.order_delivered_carrier_date - o.order_purchase_timestamp)) / 86400 AS handoff_days
    FROM cleaned.orders o
    JOIN cleaned.customers c ON o.customer_id = c.customer_id
    JOIN customer_segments cs ON c.customer_unique_id = cs.customer_unique_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_carrier_date IS NOT NULL
)

-- Final Summary: Correlating Segments to Seller Performance
SELECT 
    segment,
    COUNT(*) AS total_orders,
    ROUND(AVG(handoff_days), 2) AS avg_handoff_days,
    -- Calculate % meeting the "3-Day Gold Standard"
    ROUND(100.0 * SUM(CASE WHEN handoff_days <= 3 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_within_3_days,
    -- Calculate % of extreme delays (over 1 week to just ship)
    ROUND(100.0 * SUM(CASE WHEN handoff_days > 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_extreme_delay,
    ROUND(MAX(handoff_days), 1) AS worst_case_handoff
FROM handoff_metrics
GROUP BY 1
ORDER BY avg_handoff_days DESC;


/* =========================================================
   Q8: Survival Analysis - Handoff Time Comparison
   Comparing the 3% (Repeaters) vs. 97% (One-Timers)
   ========================================================= */

WITH customer_groups AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS total_orders,
        CASE 
            WHEN COUNT(DISTINCT o.order_id) > 1 THEN '3% Repeaters'
            ELSE '97% One-Timers'
        END AS group_type
    FROM cleaned.orders o
    JOIN cleaned.customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
handoff_data AS (
    SELECT 
        cg.group_type,
        o.order_id,
        -- Calculate processing time (handoff)
        EXTRACT(EPOCH FROM (o.order_delivered_carrier_date - o.order_purchase_timestamp)) / 86400 AS handoff_days
    FROM cleaned.orders o
    JOIN cleaned.customers c ON o.customer_id = c.customer_id
    JOIN customer_groups cg ON c.customer_unique_id = cg.customer_unique_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_carrier_date IS NOT NULL
)
SELECT 
    group_type,
    COUNT(*) AS total_orders,
    ROUND(AVG(handoff_days), 2) AS avg_handoff_days,
    -- % meeting the 3-day Gold Standard
    ROUND(100.0 * SUM(CASE WHEN handoff_days <= 3 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_within_3_days,
    -- % of extreme delays
    ROUND(100.0 * SUM(CASE WHEN handoff_days > 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_extreme_delay
FROM handoff_data
GROUP BY 1;



--q9 s it the freight tax?? no

SELECT
    CASE 
        WHEN c_counts.total_orders > 1 THEN '3% Repeaters'
        ELSE '97% One-Timers'
    END AS group_type,
    COUNT(*) AS total_orders,
    ROUND(AVG(oi.price), 2) AS avg_item_price,
    ROUND(AVG(oi.freight_value), 2) AS avg_freight_value,
    
    ROUND(AVG(oi.freight_value / NULLIF(oi.price, 0)) * 100, 2) AS freight_as_pct_of_price
FROM cleaned.order_items oi
JOIN cleaned.orders o ON oi.order_id = o.order_id
JOIN cleaned.customers c ON o.customer_id = c.customer_id
JOIN (
    SELECT customer_unique_id, COUNT(order_id) as total_orders
    FROM cleaned.orders o
    JOIN cleaned.customers c ON o.customer_id = c.customer_id
    GROUP BY 1
) c_counts ON c.customer_unique_id = c_counts.customer_unique_id
WHERE o.order_status = 'delivered'
GROUP BY 1;