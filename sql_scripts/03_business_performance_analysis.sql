
/* =========================================================
   BRAZILIAN RETAIL SQL PROJECT
   Dataset: Olist E-Commerce
   Phase 3: Revenue Analysis
   Author: Eoghan Kealy
   Database: PostgreSQL
   ========================================================= */



/* =========================================================
   Q1: Total Revenue and Order Count
   
   Note: Using CTEs to pre-aggregate order_items and 
   order_payments separately before joining. This prevents 
   row multiplication that would occur from joining two 
   one-to-many relationships directly to orders. Both order_items
   and order_payments have multiple values for each order_id that 
   will need to be collapsed down. I also checked to make sure 
   that the  sum of price and freight value for each order_id adds
   up to the sum of the payment_value recieved for that order_id
   
   Used order_payments.payment_value for actual cash 
   received rather than calculating from order_items, as 
   this reflects what customers actually paid (including 
   any discounts or adjustments).
   ========================================================= */




/* =========================================================
   DIAGNOSTIC QUERIES (Used during development)
   
   These queries were used to validate the relationship between
   order_items and order_payments. They confirm that:
   - sum(price + freight_value) = sum(payment_value) for most orders
   - Discrepancies exist due to installment fees (Brazilian payment culture)
   
   Kept for documentation purposes but not part of final analysis.
   ========================================================= */
   
-- checking the the  sum of price and freight value for each order_id adds
-- up to the sum of the payment_value recieved for that order_id
SELECT * FROM cleaned.order_items
WHERE order_id = 'ab14fdcfbe524636d65ee38360e22ce8';


SELECT 
    SUM(price + freight_value) AS calculated_total,
    (SELECT SUM(payment_value) FROM cleaned.order_payments WHERE order_id = 'ab14fdcfbe524636d65ee38360e22ce8') AS actual_payment
FROM cleaned.order_items
WHERE order_id = 'ab14fdcfbe524636d65ee38360e22ce8';



-- originally used customer_id for count of total customers before switching to unique_customer_id
SELECT 
    COUNT(DISTINCT o.order_id) as total_orders,
    COUNT(DISTINCT o.customer_id) as total_customers,
    SUM(p.payment_value) as total_revenue,
    AVG(p.payment_value) as avg_order_value,
    MIN(o.order_purchase_timestamp) as first_order,
    MAX(o.order_purchase_timestamp) as last_order
FROM cleaned.orders o
JOIN cleaned.order_payments p ON o.order_id = p.order_id
WHERE o.order_status = 'delivered';

-- CTE query , allows me to group by order_id to avoid exploding rows and then perform math on it

  WITH order_totals AS (
    SELECT 
        order_id,
        SUM(price) AS product_revenue,
        SUM(freight_value) AS freight_revenue
    FROM cleaned.order_items
    GROUP BY order_id
),
payment_totals AS (
    SELECT 
        order_id,
        SUM(payment_value) AS total_paid
    FROM cleaned.order_payments
    GROUP BY order_id
)
SELECT 
    COUNT(DISTINCT o.order_id) AS total_orders,
	COUNT(DISTINCT c.customer_unique_id) AS total_unique_customers,
    SUM(ot.product_revenue) AS total_product_revenue,
    SUM(ot.freight_revenue) AS total_freight_revenue,
    SUM(pt.total_paid) AS total_cash_received,
    ROUND(SUM(pt.total_paid) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value,ROUND(COUNT(DISTINCT o.order_id)::NUMERIC / COUNT(DISTINCT c.customer_unique_id), 2) AS orders_per_customer
FROM cleaned.orders o
LEFT JOIN cleaned.customers c ON o.customer_id = c.customer_id  -- JOIN to customers table
LEFT JOIN order_totals ot ON o.order_id = ot.order_id
LEFT JOIN payment_totals pt ON o.order_id = pt.order_id
WHERE o.order_status = 'delivered';

/* =========================================================
   IMPORTANT DATA MODEL DISCOVERY
   
   Initial Query Issue:
   When running business overview metrics, I found total_orders (count of order_id) = total_customers (count of customer_id)
   which contradicted expected repeat purchase behavior.
   
   Investigation Process:
   1. Checked order_status values for filtering issues
   2. Searched for customers with multiple delivered orders (returned 0)
   3. Compared raw vs cleaned data (both showed 1:1 relationship)
   4. Examined the customers table structure
   
   Root Cause:
   The Olist dataset uses TWO customer identifiers:
   - customer_id: Unique per ORDER (anonymization/privacy)
   - customer_unique_id: Unique per PERSON (tracking repeat behavior)
   
   This is a privacy-preserving design where each transaction gets a new
   customer_id, but links back to the same person via customer_unique_id.
   
   Resolution:
   All customer-level analysis must:
   1. JOIN orders → customers table
   2. GROUP BY customer_unique_id (not customer_id)
   3. Use customer_unique_id for repeat rate, CLV, and RFM analysis
   
   Diagnostic queries used:
   ========================================================= */
SELECT COUNT(*) 
FROM cleaned.orders
WHERE order_status = 'delivered';

SELECT COUNT(DISTINCT customer_id)
FROM cleaned.orders
WHERE order_status = 'delivered';

SELECT 
    customer_id,
    COUNT(*) as order_count
FROM cleaned.orders
WHERE order_status = 'delivered'
GROUP BY customer_id
HAVING COUNT(*) > 1
ORDER BY order_count DESC
LIMIT 20;


SELECT 
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(DISTINCT customer_id) AS total_customers,
    ROUND(COUNT(DISTINCT order_id)::NUMERIC / COUNT(DISTINCT customer_id), 2) AS orders_per_customer
FROM cleaned.orders;

--- confirms customer_unique_id should be used for customer metrics as it has multiple orders
SELECT 
    c.customer_unique_id,
    COUNT(DISTINCT o.order_id) as total_orders,
    COUNT(DISTINCT o.customer_id) as unique_customer_ids,
    ARRAY_AGG(o.order_id ORDER BY o.order_purchase_timestamp) as order_ids
FROM cleaned.orders o
JOIN cleaned.customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_unique_id
HAVING COUNT(DISTINCT o.order_id) > 1
ORDER BY total_orders DESC
LIMIT 10;

-- compare count of customer_id to customer_unique_id
SELECT 
    COUNT(DISTINCT customer_id) as transaction_ids,
    COUNT(DISTINCT customer_unique_id) as actual_people
FROM cleaned.customers;

-- get revenue metrics including unique customers
SELECT 
    COUNT(DISTINCT o.order_id) as total_orders,
    COUNT(DISTINCT c.customer_unique_id) as total_customers,
    SUM(p.payment_value) as total_revenue,
    AVG(p.payment_value) as avg_order_value,
    MIN(o.order_purchase_timestamp) as first_order,
    MAX(o.order_purchase_timestamp) as last_order
FROM cleaned.orders o
JOIN cleaned.order_payments p ON o.order_id = p.order_id
INNER JOIN cleaned.customers c ON o.customer_id = c.customer_id -- proves that every dollar of revenue is linked to a known customer.
WHERE o.order_status = 'delivered';

/* "During validation, I identified a discrepancy between AVG(payment_value) and SUM(payment_value)/COUNT(orders).
 Because the Olist dataset allows split-payments (vouchers/multiple cards), 
 the simple AVG function underreports the true Average Order Value. For the final executive report, 
 I utilized the Aggregate Ratio Method ($159.85) to accurately reflect revenue per order."
*/

/* FINAL EXECUTIVE REVENUE SUMMARY 
   Goal: Calculate core KPIs at the 'customer' and 'order' grain.
   Logic: Uses a CTE to pre-aggregate split-payments to prevent AOV deflation.
*/

WITH order_level_payments AS (
    -- Step 1: Collapse multiple payments (vouchers + credit card) into one total per order
    SELECT 
        order_id, 
        SUM(payment_value) AS total_order_value
    FROM cleaned.order_payments
    GROUP BY order_id
)
SELECT 
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(DISTINCT c.customer_unique_id) AS total_unique_customers,
    SUM(olp.total_order_value) AS total_revenue,
    
    -- Correct AOV: Total Revenue divided by Total Orders
    ROUND(SUM(olp.total_order_value) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value,
    
    -- Repeat Purchase Rate: Orders per Human
    ROUND(COUNT(DISTINCT o.order_id)::NUMERIC / COUNT(DISTINCT c.customer_unique_id), 2) AS orders_per_customer,
    
    MIN(o.order_purchase_timestamp)::DATE AS period_start,
    MAX(o.order_purchase_timestamp)::DATE AS period_end
FROM cleaned.orders o
INNER JOIN cleaned.customers c ON o.customer_id = c.customer_id
INNER JOIN order_level_payments olp ON o.order_id = olp.order_id
WHERE o.order_status = 'delivered';

/* FINAL REVENUE INSIGHTS:
   - Total Verified Revenue: $15.42M
   - Total Customer Base: 93,357 Unique Customers
   - True AOV: $159.85 (Corrected for split-payments)
   - Repeat Behavior: 1.03 orders/customer 
   - Data Period: Oct 2016 - Aug 2018
*/





--- Question 2 monthly revenue trends
 -- used widnow function OVER() to calculate month on month growth, AOV average order value, total orders, monthly revenue


/* TIME-SERIES ANALYSIS: Monthly Revenue & Velocity
   
   Technical Highlight: 
   - Utilized the LAG() window function with an OVER() clause to access 
     the previous month's data without a self-join. 
   - This allows for the calculation of 'Month-over-Month' (MoM) growth 
     directly within the result set.
   - Employed NULLIF() to handle potential 'Division by Zero' errors (not a lot of data for 2016)
*/

WITH payment_totals AS (
    SELECT 
        order_id,
        SUM(payment_value) AS total_paid
    FROM cleaned.order_payments
    GROUP BY order_id
),

monthly_metrics AS (
    SELECT 
        DATE_TRUNC('month', o.order_purchase_timestamp)::date AS purchase_month,
        COUNT(DISTINCT o.order_id) AS total_orders,
        SUM(pt.total_paid) AS monthly_revenue
    FROM cleaned.orders o
    LEFT JOIN payment_totals pt 
        ON o.order_id = pt.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY 1
)

SELECT 
    purchase_month,
    total_orders,
    monthly_revenue,
    ROUND(monthly_revenue / NULLIF(total_orders, 0), 2) AS avg_order_value,
    ROUND(
        (
            monthly_revenue 
            - LAG(monthly_revenue) OVER (ORDER BY purchase_month)
        )
        / NULLIF(
            LAG(monthly_revenue) OVER (ORDER BY purchase_month), 
            0
        ) * 100,
        2
    ) AS revenue_growth_pct
FROM monthly_metrics
ORDER BY purchase_month;

----- question 3 top 20 product categories (GMV (Gross Merchandise Value price + freight))

/* =========================================================
   NOTE: Revenue Calculation Choice
   
   This query uses order_items.price + freight_value rather than 
   order_payments.payment_value for the following reasons:
   
   1. Payments are at ORDER level, not ITEM level
   2. Product categories require item-level revenue attribution
   3. For comparing product performance, pre-fee pricing is more meaningful
 ========================================================= */
  
SELECT 
    COALESCE(t.product_category_name_english, 'Unknown') as category,
    COUNT(DISTINCT oi.order_id) as orders,
    SUM(oi.price + oi.freight_value) as item_revenue,  -- Renamed for clarity
    ROUND(AVG(oi.price + oi.freight_value), 2) as avg_item_value,
    ROUND(100.0 * SUM(oi.price + oi.freight_value) / SUM(SUM(oi.price + oi.freight_value)) OVER (), 2) as pct_of_total_gmv -- show catgeory % of total gmv
FROM cleaned.order_items oi
JOIN cleaned.products p ON oi.product_id = p.product_id
LEFT JOIN cleaned.product_category_name_translation t 
    ON p.product_category_name = t.product_category_name
GROUP BY 1
ORDER BY item_revenue DESC
LIMIT 20;
------------------------------------------------------------------------------------------------------

/* =========================================================
   Q4: What is our repeat purchase rate?
   
   Customer Behavior Overview: Repeat Purchase Analysis
   
   CRITICAL METRIC: Foundation for all retention/churn analysis
   
   This reveals what % of customers come back for a second purchase.
   Low repeat rate = retention problem = business opportunity.
   Comprehensive metrics on one-time vs repeat customers:

   - Purchase frequency distribution
   - Repeat purchase rates
   - Revenue contribution by segment
   - Time-to-return patterns
   
   KEY FINDING: 97% one-time buyers, 3% repeat rate
   ========================================================= */

WITH customer_order_counts AS (
    SELECT 
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) as total_orders,
        MIN(o.order_purchase_timestamp) as first_order_date,
        MAX(o.order_purchase_timestamp) as last_order_date,
        SUM(pt.payment_value) as lifetime_value
    FROM cleaned.orders o
    JOIN cleaned.customers c ON o.customer_id = c.customer_id
    JOIN cleaned.order_payments pt ON o.order_id = pt.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp IS NOT NULL
    GROUP BY c.customer_unique_id
)
SELECT 
    -- =====================================================
    -- CUSTOMER COUNTS
    -- =====================================================
    COUNT(*) as total_customers,
    
    -- Breakdown by purchase frequency
    SUM(CASE WHEN total_orders = 1 THEN 1 ELSE 0 END) as one_time_customers,
    SUM(CASE WHEN total_orders = 2 THEN 1 ELSE 0 END) as two_order_customers,
    SUM(CASE WHEN total_orders = 3 THEN 1 ELSE 0 END) as three_order_customers,
    SUM(CASE WHEN total_orders >= 4 THEN 1 ELSE 0 END) as four_plus_customers,
    
    -- =====================================================
    -- REPEAT RATE METRICS
    -- =====================================================
    ROUND(100.0 * SUM(CASE WHEN total_orders = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) 
        as one_time_pct,
    ROUND(100.0 * SUM(CASE WHEN total_orders > 1 THEN 1 ELSE 0 END) / COUNT(*), 2) 
        as repeat_rate_pct,
    
    -- =====================================================
    -- ORDER STATISTICS
    -- =====================================================
    ROUND(AVG(total_orders), 2) as avg_orders_per_customer,
    MAX(total_orders) as max_orders_single_customer,
    
    -- =====================================================
    -- TIME-TO-RETURN METRICS
    -- =====================================================
    -- Average span between first and last purchase (for repeat customers only)
    ROUND(AVG(EXTRACT(DAY FROM (last_order_date - first_order_date))) 
        FILTER (WHERE total_orders > 1), 1) as avg_days_between_first_last_order,
    
    -- =====================================================
    -- REVENUE METRICS
    -- =====================================================
    ROUND(SUM(lifetime_value), 2) as total_revenue,
    
    -- Revenue by segment
    ROUND(SUM(CASE WHEN total_orders = 1 THEN lifetime_value ELSE 0 END), 2) 
        as one_time_revenue,
    ROUND(SUM(CASE WHEN total_orders > 1 THEN lifetime_value ELSE 0 END), 2) 
        as repeat_customer_revenue,
    
    -- Revenue percentages
    ROUND(100.0 * SUM(CASE WHEN total_orders = 1 THEN lifetime_value ELSE 0 END) / 
          SUM(lifetime_value), 2) as one_time_revenue_pct,
    ROUND(100.0 * SUM(CASE WHEN total_orders > 1 THEN lifetime_value ELSE 0 END) / 
          SUM(lifetime_value), 2) as repeat_revenue_pct,
    
    -- Average customer value by segment
    ROUND(AVG(lifetime_value) FILTER (WHERE total_orders = 1), 2) 
        as avg_one_time_customer_value,
    ROUND(AVG(lifetime_value) FILTER (WHERE total_orders > 1), 2) 
        as avg_repeat_customer_value

FROM customer_order_counts;

/* =========================================================
   CUSTOMER BEHAVIOR & RETENTION ANALYSIS: KEY FINDINGS
   ---------------------------------------------------------
   METRIC                          | VALUE        | INTERPRETATION
   --------------------------------|--------------|----------------------------------
   Total Unique Customers          | 93,357       | Full customer base
   One-Time Shoppers               | 90,556       | Never returned (97%)
   Two-Order Customers             | 2,573        | Made it past 1st barrier
   Three-Order Customers           | 181          | Developing loyalty (0.19%)
   Four+ Order Customers           | 47           | "Power users" (0.05%)
   --------------------------------|--------------|----------------------------------
   One-Time Rate (%)               | 97.00%       | **CRITICAL: Severe churn**
   Repeat Purchase Rate (%)        | 3.00%        | **CORE KPI: Retention crisis**
   Avg Orders per Customer         | 1.03         | Platform engagement (very low)
   Max Orders (Single Customer)    | 15           | Top loyalist benchmark
   --------------------------------|--------------|----------------------------------
   Avg Days Between First & Last   | 87.8 days    | Repeat customer lifecycle span
   --------------------------------|--------------|----------------------------------
   Total Platform Revenue          | $15,422,462  | Complete revenue picture
   One-Time Customer Revenue       | $14,558,105  | 94.4% from one-timers
   Repeat Customer Revenue         | $864,357     | **Only 5.6% from repeaters**
   --------------------------------|--------------|----------------------------------
   One-Time Revenue (%)            | 94.40%       | Revenue concentration risk
   Repeat Customer Revenue (%)     | 5.60%        | Undermonetized segment
   --------------------------------|--------------|----------------------------------
   Avg One-Time Customer Value     | $160.76      | Single transaction value
   Avg Repeat Customer Value       | $308.59      | **91% higher lifetime value**
   ========================================================= 
   
   CRITICAL BUSINESS INSIGHTS:
   
   1. RETENTION CRISIS
      - 97% one-time buyer rate = severe acquisition waste
      - Only 47 customers (0.05%) achieved 4+ orders
      - True loyalty is virtually non-existent
   
   2. REVENUE CONCENTRATION PROBLEM
      - 94.4% of revenue from customers who never return
      - Only 5.6% from repeat customers despite their 91% higher value
      - Massive untapped potential in repeat segment
   
   3. THE $864K OPPORTUNITY
      - Repeat customers worth $308.59 vs $160.76 for one-timers
      - Doubling repeat rate (3% - 6%) = +$864K revenue
      - Zero customer acquisition cost for this growth
   
   4. CRITICAL INTERVENTION WINDOW
      - Avg 87.8 days between first and last purchase
      - Marketing interventions should trigger at Day 60-80
      - Captures repeat intent before typical 90-day churn
   
   5. LOYALTY BARRIERS
      - 1st to 2nd order: 97% drop (90,556 never return)
      - 2nd to 3rd order: 92.9% drop (2,573 - 181)
      - 3rd to 4th order: 74% drop (181 - 47)
      - Breaking the first barrier is THE critical challenge
   
   STRATEGIC IMPLICATION:
   Olist operates as an acquisition-heavy, transaction-focused
   marketplace. The 3% repeat rate + 87.8-day return cycle
   indicates customers are satisfied (see review analysis) but
   lack reasons to return. This is a MARKETING problem, not
   an OPERATIONS problem.
   
   RECOMMENDED ACTION SEQUENCE:
   Day 0:   First purchase complete
   Day 30:  "How was your order?" follow-up
   Day 60:  Product recommendations + 10% discount
   Day 90:  "We miss you" + 15% discount (critical window)
   Day 180: Final win-back attempt (churn threshold)
   
   NEXT ANALYSIS:
   - RFM Segmentation (04_rfm_segmentation.sql)
   - Root Cause Investigation (05_retention_root_cause_analysis.sql)
   ========================================================= */




--- question 5  - State-Level Revenue Contribution & Geographic Concentration Analysis , Pareto Analysis of Revenue Distribution Across Brazilian States

/*
Objective:
Identify whether marketplace revenue is geographically concentrated
and quantify the extent of regional dependency using Pareto analysis.
*/



WITH payment_totals AS (
    SELECT 
        order_id,
        SUM(payment_value) as total_paid
    FROM cleaned.order_payments
    GROUP BY order_id
),

state_metrics AS (
    SELECT 
        c.state,
        COUNT(DISTINCT c.customer_unique_id) as unique_customers,
        COUNT(DISTINCT o.order_id) as total_orders,
        SUM(pt.total_paid) as total_revenue,
        ROUND(AVG(pt.total_paid), 2) as avg_order_value,
        ROUND(COUNT(DISTINCT o.order_id)::NUMERIC / 
              COUNT(DISTINCT c.customer_unique_id), 2) as orders_per_customer
    FROM cleaned.orders o
    JOIN cleaned.customers c ON o.customer_id = c.customer_id
    JOIN payment_totals pt ON o.order_id = pt.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp IS NOT NULL
    GROUP BY c.state
),

final_metrics AS (
    SELECT 
        state,
        unique_customers,
        total_orders,
        total_revenue,
        avg_order_value,
        orders_per_customer,
        -- Using window functions to calculate the total denominator and running totals without collapsing rows, enabling MoM growth and Pareto calculations.
        ROUND(100.0 * total_revenue / SUM(total_revenue) OVER (), 2) 
            as pct_of_total_revenue,
        
        ROUND(100.0 * SUM(total_revenue) OVER (
            ORDER BY total_revenue DESC 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / SUM(total_revenue) OVER (), 2) 
            as cumulative_revenue_pct

    FROM state_metrics
)

SELECT *,
       CASE 
           WHEN cumulative_revenue_pct <= 80 
           THEN 'Top 80% Revenue Drivers'
           ELSE 'Long Tail'
       END AS pareto_segment
FROM final_metrics
ORDER BY total_revenue DESC;

/*
Key Findings:

- Revenue is highly concentrated geographically.
- 6 out of 27 states (22%) generate 80% of total marketplace revenue.
- São Paulo (SP) alone accounts for ~37% of total revenue.
- Orders per customer is relatively stable across states (~1.03-1.04),
  indicating that revenue concentration is driven primarily by customer volume
  rather than stronger repeat purchasing behavior.
- This suggests operational dependency on core states and potential
  expansion opportunities in underpenetrated regions.
*/

/* STRATEGIC TAKEAWAY: 
   Revenue growth is currently driven by "New User Volume" in 
   major hubs rather than "Customer Loyalty." Expansion into 
   underpenetrated states is a secondary goal compared to 
   fixing the platform-wide retention gap.
*/







