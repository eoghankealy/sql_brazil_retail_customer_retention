
/* =========================================================
   BRAZILIAN RETAIL SQL PROJECT
   Dataset: Olist E-Commerce  
   Phase 4: RFM Customer Segmentation
   Author: Eoghan Kealy
   Database: PostgreSQL
   
   PURPOSE:
   Segment repeat customers (3% of base) using RFM methodology
   to identify retention opportunities and prioritize interventions.
   
   APPROACH:
   Two RFM implementations:
   1. Traditional 5-5-5 scoring (all customers)
   2. Hybrid 5-segment model (repeat customers only)
   
*/





/* =========================================================
   QUERY 1: TRADITIONAL RFM (ALL CUSTOMERS)
   
   Standard RFM quintile scoring across entire customer base.
   
   LIMITATION DISCOVERED:
   With 97% one-time buyers, this creates a massive undifferentiated
   segment of customers with identical scores,
   making segmentation meaningless for the bulk of the customer base.

   This led to the development of Query 2, which focuses on the
   3% who have demonstrated repeat behavior.
   ========================================================= */


--  Query 1  RFM analysis


-- Step 1: Snapshot date (defines "today" for recency)
WITH snapshot AS (
    SELECT 
        MAX(order_purchase_timestamp)::DATE AS snapshot_date
    FROM cleaned.orders
),

-- Step 2: Aggregate RFM metrics per customer
customer_rfm AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS frequency, -- F
        SUM(p.payment_value) AS monetary, -- M
        MAX(o.order_purchase_timestamp)::DATE AS last_order_date
    FROM cleaned.orders o
    JOIN cleaned.customers c 
        ON o.customer_id = c.customer_id
    JOIN cleaned.order_payments p 
        ON o.order_id = p.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),

-- Step 3: Calculate recency  
customer_rfm_recency AS (
    SELECT
        r.customer_unique_id,
        r.frequency,
        r.monetary,
        (s.snapshot_date - r.last_order_date) AS recency_days
    FROM customer_rfm r
    CROSS JOIN snapshot s
),

-- Step 4: Assign RFM quintile scores (5 = BEST)
rfm_scored AS (
    SELECT
        customer_unique_id,
        frequency,
        monetary,
        recency_days,
        
        -- FIXED: Recency - lower days = better = higher score
        -- Large recency (old) - bucket 1 - score 1 
        -- Small recency (recent) - bucket 5 - score 5 
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        
        -- Frequency: higher = better - order DESC
        NTILE(5) OVER (ORDER BY frequency DESC) AS f_score,
        
        -- Monetary: higher = better - order DESC
        NTILE(5) OVER (ORDER BY monetary DESC) AS m_score
    FROM customer_rfm_recency
)

-- Final Output: Best customers first
SELECT
    customer_unique_id,
    r_score,
    f_score,
    m_score,
    CONCAT(r_score, '-', f_score, '-', m_score) AS rfm_segment,
    frequency,
    ROUND(monetary, 2) as monetary,
    recency_days
FROM rfm_scored
ORDER BY
    r_score DESC,
    f_score DESC,
    m_score DESC,
    monetary DESC
LIMIT 50;



-- Break RFM into 5 buckets to see whats happening


-- Step 1: Snapshot date
WITH snapshot AS (
    SELECT 
        MAX(order_purchase_timestamp)::DATE AS snapshot_date
    FROM cleaned.orders
),

-- Step 2: Aggregate RFM metrics per customer
customer_rfm AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS frequency,
        SUM(p.payment_value) AS monetary,
        MAX(o.order_purchase_timestamp)::DATE AS last_order_date
    FROM cleaned.orders o
    JOIN cleaned.customers c 
        ON o.customer_id = c.customer_id
    JOIN cleaned.order_payments p 
        ON o.order_id = p.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),

-- Step 3: Calculate recency
customer_rfm_recency AS (
    SELECT
        r.customer_unique_id,
        r.frequency,
        r.monetary,
        (s.snapshot_date - r.last_order_date) AS recency_days
    FROM customer_rfm r
    CROSS JOIN snapshot s
),

-- Step 4: Assign RFM scores
rfm_scored AS (
    SELECT
        customer_unique_id,
        frequency,
        monetary,
        recency_days,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency DESC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary DESC) AS m_score
    FROM customer_rfm_recency
),

-- Step 5: Create RFM segment codes
rfm_with_segments AS (
    SELECT
        customer_unique_id,
        frequency,
        monetary,
        recency_days,
        r_score,
        f_score,
        m_score,
        CONCAT(r_score, '-', f_score, '-', m_score) AS rfm_segment
    FROM rfm_scored
)

-- Final analysis: Distribution of key RFM segments
SELECT 
    rfm_segment,
    COUNT(*) as customer_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) as pct_of_total,
    ROUND(AVG(frequency), 2) as avg_frequency,
    ROUND(AVG(monetary), 2) as avg_monetary,
    ROUND(AVG(recency_days), 1) as avg_recency,
    MIN(frequency) as min_frequency,
    MAX(frequency) as max_frequency
FROM rfm_with_segments
WHERE rfm_segment IN ('5-5-5', '4-4-4', '3-3-3', '2-2-2', '1-1-1')
GROUP BY rfm_segment
ORDER BY rfm_segment DESC;




/* Results:

RFM      | Customers | % of Total | Avg Freq | Avg $   | Avg Recency | Min | Max
---------|-----------|------------|----------|---------|-------------|-----|-----
5-5-5    | 3,697     | 22.55%     | 1.00     | $39.44  | 93 days     | 1   | 1
4-4-4    | 3,044     | 18.56%     | 1.00     | $68.12  | 184 days    | 1   | 1
3-3-3    | 3,250     | 19.82%     | 1.00     | $105.66 | 270 days    | 1   | 1
2-2-2    | 3,246     | 19.80%     | 1.00     | $161.81 | 363 days    | 1   | 1
1-1-1    | 3,161     | 19.28%     | 1.07     | $324.36 | 523 days    | 1   | 4
*/




/* =========================================================
   Query 1 RFM RESULTS: Why Traditional RFM Fails Here
   
   PROBLEM DISCOVERED:
   With 97% one-time buyers (frequency = 1), NTILE(5) cannot
   create meaningful differentiation. The quintile buckets
   contain mostly identical customers.
   
   Example: "Champions" (5-5-5) segment contains:
   - Recent purchasers (good) 
   - BUT frequency = 1 (one-timers) 
   - AND low monetary value ($54) 
   
   ROOT CAUSE:
   NTILE divides 93,357 customers into 5 equal buckets of
   ~18,671 each. Since 90,556 have frequency = 1, all five
   buckets are dominated by one-time buyers.
   
   BUSINESS IMPLICATION:
   Cannot create actionable segments when 97% of customers
   have identical behavior (bought once, never returned).
   
   SOLUTION:
   Query 2 focuses exclusively on the 2,801 repeat customers
   (3%) where behavioral variation exists and segmentation
   becomes meaningful.

   ========================================================= */


/* =========================================================
   QUERY 1 RESULTS: Traditional RFM Failure Analysis
   
   Diagonal RFM segments (5-5-5, 4-4-4, etc.) show:
   
   RFM Code | Customers | Avg Freq | Avg Value | Interpretation
   ---------|-----------|----------|-----------|----------------
   5-5-5    | 3,697     | 1.00     | $39.44    | Recent, low-value one-timers
   4-4-4    | 3,044     | 1.00     | $68.12    | Slightly older one-timers
   3-3-3    | 3,250     | 1.00     | $105.66   | Mid-age one-timers
   2-2-2    | 3,246     | 1.00     | $161.81   | Older one-timers
   1-1-1    | 3,161     | 1.07     | $324.36   | Ancient, but higher-value!
   
   CRITICAL FINDING:
   All segments have avg_frequency = 1.00, proving that NTILE
   cannot create meaningful differentiation when 97% of customers
   have identical behavior (bought once, never returned).
   
   PARADOX IDENTIFIED:
   "Champions" (5-5-5) have LOWER monetary value ($39.44) than
   "Worst Customers" (1-1-1: $324.36) because the 1-1-1 bucket
   captures the few repeat customers who are now churned.
   
   BUSINESS IMPLICATION:
   Traditional RFM creates 125 possible segments (5x5x5) but
   cannot differentiate 90,556 one-time buyers. This makes
   segmentation meaningless and retention strategies impossible.
   
   CONCLUSION:
   This analysis justifies our pivot to repeat-customer-only
   RFM (Query 2), where behavioral variation actually exists
   and segmentation becomes actionable.
   ========================================================= */













/* =========================================================
   QUERY 2: HYBRID RFM (REPEAT CUSTOMERS ONLY)
   
   Focus: 2,801 repeat customers (3% of base)
   
   WHY REPEAT-ONLY:
   - 97% of customers never return (1-1-1 segment not actionable)
   - Repeat customers show actual behavioral variation
   - These 2,801 represent $864K in lifetime value
   - Highest ROI for retention efforts (zero acquisition cost)
   
   HYBRID APPROACH:
   Combines traditional RFM scoring (1-5) with evidence-based
   business rules derived from time-between-purchases analysis:
   - Frequency threshold: 5+ orders = VIP (top 0.05%)
   - Recency threshold: Based on 240-day churn window (P90)
   - Monetary threshold: $250+ for high-value classification
   
   SEGMENTS CREATED:
   1. Champions (388, 13.8%) - Protect at all costs
   2. Active & Engaged (319, 11.4%) - Maintain momentum  
   3. Active - Needs Nurturing (974, 34.8%) - Highest leverage
   4. Lapsed - Recovery Target (364, 13.0%) - Win-back campaign
   5. Churned (756, 27.0%) - Minimal investment
   ========================================================= */

--improved rfm  with 4 segments focusing on just the 3% who actually made 2 or more orders

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
        -- Traditional RFM scoring (1-5)
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM rfm_base
),
with_segments AS (
    SELECT
        *,
        CONCAT(r_score, '-', f_score, '-', m_score) AS rfm_code,
        -- Simplified 4-segment mapping from RFM scores
        CASE 
            -- Champions: High on all dimensions OR exceptional frequency 
            -- (ensures that anyone with exceptionally high frequency is promoted to Champion status regardless of their NTILE score.)
            WHEN frequency >= 5 
              OR (r_score >= 4 AND f_score >= 4 AND m_score >= 4)
            THEN 'Champions'
            
            -- Active & Engaged: Recent (R=4-5) + decent value (M=3-5)
            WHEN r_score >= 4 AND m_score >= 3
            THEN 'Active & Engaged'
            
            -- Active - Needs Nurturing: Recent (R=3-4) but lower F or M
            WHEN r_score >= 3
            THEN 'Active - Needs Nurturing'
            
            -- Lapsed: Old recency (R=2) but decent F or M (worth recovery)
            WHEN r_score = 2 AND (f_score >= 3 OR m_score >= 3)
            THEN 'Lapsed - Recovery Target'
            
            -- Churned: Very old (R=1) or low on all dimensions
            ELSE 'Churned'
        END AS segment
    FROM rfm_scored
)
SELECT
    customer_unique_id,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    rfm_code,
    segment,
    CASE 
        WHEN segment = 'Champions' THEN 1
        WHEN segment = 'Active & Engaged' THEN 2
        WHEN segment = 'Lapsed - Recovery Target' THEN 3
        WHEN segment = 'Active - Needs Nurturing' THEN 4
        ELSE 5
    END as action_priority
FROM with_segments
ORDER BY action_priority, monetary DESC;



