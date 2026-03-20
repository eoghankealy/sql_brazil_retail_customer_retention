
/* =========================================================
   BRAZILIAN RETAIL SQL PROJECT
   Dataset: Olist E-Commerce
   Phase 2: Data Quality Checks
   Author: Eoghan Kealy
   Database: PostgreSQL
   ========================================================= */


-- check for negative numbers
SELECT MIN(price), MAX(price)
FROM cleaned.order_items;

-- Count the total rows to see if it matches the amount of rows Terminal finds in the csv file
SELECT COUNT(*) FROM raw.customers;
-- Terminal comand to count the rows in the orgional csvfile
--- wc -l /path/to/olist_customers_dataset.csv
-- repeat steps  for other tables

--- descrepency over row numbers in order reviews 

TRUNCATE raw.order_reviews; -- Empty the table to try again

-- Created Python script to handle olist_orders_dataset.csv
-- Python script uses the pandas engine to "clean" the CSV by correctly identifying that multi-line review comments belong to a single record.
-- I used it because the standard SQL import and Terminal commands were miscounting those "Enter" keys as new rows, which would have corrupted the data.


---- Now ready to create cleaned tables

/* =========================================================
   TABLE: cleaned.customers
   GRAIN: One row per customer_id (Transaction ID)
   ========================================================= */


-- Check for NULL customer_id
SELECT COUNT(*)
FROM raw.customers
WHERE customer_id IS NULL;

-- Check for duplicate customer_id
SELECT customer_id, COUNT(*)
FROM raw.customers
GROUP BY customer_id
HAVING COUNT(*) > 1;



--  Verify the customer_id and  unique customer count, proves the table is behaving exactly as it should: multiple orders can belong to one person.
SELECT 
    COUNT(customer_id) AS total_order_ids, 
    COUNT(DISTINCT customer_unique_id) AS actual_human_customers
FROM cleaned.customers;

SELECT 
    customer_id, 
    COUNT(*) as occurrences
FROM cleaned.customers
GROUP BY customer_id
HAVING COUNT(*) > 1;

---- Steps are repeated for the other tables

SELECT 
    COUNT(*) AS total_rows,
    COUNT(*) - COUNT(DISTINCT (zip_code_prefix, lat, lng)) AS total_duplicate_rows
FROM cleaned.geolocation;

---- geolcation table has many duplicates so zip code will be grouped and an average of the latitude and logitude found 



-- order_items table needs a composie primary key as order_id appears multiple times due to multple order_item_ids for each order

-- make sure  composite key order_id and order_item_id is unique

SELECT order_id, order_item_id, COUNT(*)
FROM raw.order_items
GROUP BY order_id, order_item_id
HAVING COUNT(*) > 1;




SELECT review_id, COUNT(*) 
FROM raw.order_reviews
GROUP BY review_id
HAVING COUNT(*) > 1
ORDER BY COUNT(*);


-- identify why review_id appears multiple times
SELECT * FROM raw.order_reviews
WHERE review_id = 'e8f500e8052dd5fac20fee5a8c880367';

-- make sure composite primary key is unique
SELECT review_id, order_id, COUNT(*)
FROM raw.order_reviews
GROUP BY review_id, order_id
HAVING COUNT(*) > 1;

-- it appears the order_review is used for multiple orders 
-- See what these cases actually look like
SELECT review_id, order_id, review_score, review_comment_message
FROM raw.order_reviews
WHERE review_id IN (
    SELECT review_id
    FROM raw.order_reviews
    GROUP BY review_id
    HAVING COUNT(DISTINCT order_id) > 1
)
ORDER BY review_id
LIMIT 20;
-- Same review_id - different order_id - identical review_score and identical review_comment_message

-- NOTE: review_id is not unique in the source data - the same review
-- appears linked to multiple orders. Instead of  using 
-- There are 1603 rows in raw.order_reviews where: A single review_id is linked to more than one order_id.

-- check to make sure composite key works, both queries return the same number of rows
SELECT COUNT(*) 
FROM raw.order_reviews;

SELECT COUNT(DISTINCT (review_id, order_id))
FROM raw.order_reviews;


-- Before adding Foreign Keys Check data integrety and null values

-- customers table

-- Check NULLs in Primary Key
SELECT COUNT(*) AS null_customer_id
FROM cleaned.customers
WHERE customer_id IS NULL;

-- Check NULLs in natural unique identifier
SELECT COUNT(*) AS null_customer_unique_id
FROM cleaned.customers
WHERE customer_unique_id IS NULL


-- orders table

-- Primary Key
SELECT COUNT(*) AS null_order_id
FROM cleaned.orders
WHERE order_id IS NULL;

-- Foreign Key to customers
SELECT COUNT(*) AS null_customer_id
FROM cleaned.orders
WHERE customer_id IS NULL;

-- Important timestamp
SELECT COUNT(*) AS null_order_purchase_timestamp
FROM cleaned.orders
WHERE order_purchase_timestamp IS NULL;

-- order_items table


-- Composite Primary Key
SELECT COUNT(*) AS null_order_id
FROM cleaned.order_items
WHERE order_id IS NULL;

SELECT COUNT(*) AS null_order_item_id
FROM cleaned.order_items
WHERE order_item_id IS NULL;

-- Foreign Keys
SELECT COUNT(*) AS null_product_id
FROM cleaned.order_items
WHERE product_id IS NULL;

SELECT COUNT(*) AS null_seller_id
FROM cleaned.order_items
WHERE seller_id IS NULL;

-- Financial fields
SELECT COUNT(*) AS null_price
FROM cleaned.order_items
WHERE price IS NULL;

SELECT COUNT(*) AS null_freight_value
FROM cleaned.order_items
WHERE freight_value IS NULL;

-- order_payments table

-- Composite Primary Key
SELECT COUNT(*) AS null_order_id
FROM cleaned.order_payments
WHERE order_id IS NULL;

SELECT COUNT(*) AS null_payment_sequential
FROM cleaned.order_payments
WHERE payment_sequential IS NULL;

-- Financial field
SELECT COUNT(*) AS null_payment_value
FROM cleaned.order_payments
WHERE payment_value IS NULL;


-- order_reviews table

-- Primary Key
SELECT COUNT(*) AS null_review_id
FROM cleaned.order_reviews
WHERE review_id IS NULL;

-- Foreign Key
SELECT COUNT(*) AS null_order_id
FROM cleaned.order_reviews
WHERE order_id IS NULL;

-- Business rule field
SELECT COUNT(*) AS null_review_score
FROM cleaned.order_reviews
WHERE review_score IS NULL;


-- products table

-- Primary Key
SELECT COUNT(*) AS null_product_id
FROM cleaned.products
WHERE product_id IS NULL;

-- Category (may legitimately contain NULLs)
SELECT COUNT(*) AS null_product_category_name
FROM cleaned.products
WHERE product_category_name IS NULL;


-- sellers table

-- Primary Key
SELECT COUNT(*) AS null_seller_id
FROM cleaned.sellers
WHERE seller_id IS NULL;


-- geolocation table 

-- Primary Key
SELECT COUNT(*) AS null_zip_code_prefix
FROM cleaned.geolocation
WHERE zip_code_prefix IS NULL;

-- Coordinates
SELECT COUNT(*) AS null_lat
FROM cleaned.geolocation
WHERE lat IS NULL;

SELECT COUNT(*) AS null_lng
FROM cleaned.geolocation
WHERE lng IS NULL;


-- Check for orphans. Logic: Utilizing LEFT JOINs to detect 'orphaned' records (records in child tables with no corresponding parent).
SELECT COUNT(*) AS orphan_orders
FROM cleaned.orders o
LEFT JOIN cleaned.customers c
    ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

SELECT COUNT(*) AS orphan_order_items
FROM cleaned.order_items oi
LEFT JOIN cleaned.orders o
    ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;


SELECT COUNT(*) AS orphan_products
FROM cleaned.order_items oi
LEFT JOIN cleaned.products p
    ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;

SELECT COUNT(*) AS orphan_sellers
FROM cleaned.order_items oi
LEFT JOIN cleaned.sellers s
    ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL;

SELECT COUNT(*) AS orphan_payments
FROM cleaned.order_payments op
LEFT JOIN cleaned.orders o
    ON op.order_id = o.order_id
WHERE o.order_id IS NULL;

SELECT COUNT(*) AS orphan_reviews
FROM cleaned.order_reviews r
LEFT JOIN cleaned.orders o
    ON r.order_id = o.order_id
WHERE o.order_id IS NULL;




--- check for ghost orders, rows with no order_id

SELECT 
    o.order_id, 
    o.order_status
FROM cleaned.orders o
LEFT JOIN cleaned.order_items oi ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL 
AND o.order_status = 'delivered'; 




--- payment versus price reconcilliation 
WITH item_totals AS (
    SELECT order_id, SUM(price + freight_value) as item_sum
    FROM cleaned.order_items GROUP BY 1
),
pay_totals AS (
    SELECT order_id, SUM(payment_value) as pay_sum
    FROM cleaned.order_payments GROUP BY 1
)
SELECT 
    i.order_id, 
    i.item_sum, 
    p.pay_sum,
    ABS(i.item_sum - p.pay_sum) as discrepancy
FROM item_totals i
JOIN pay_totals p ON i.order_id = p.order_id
WHERE ABS(i.item_sum - p.pay_sum) > 1.00; -- Find gaps larger than $1


--- Found 249 rows with a descrepency 

Check if they paid with vouchers

WITH item_totals AS (
    SELECT order_id, SUM(price + freight_value) as item_sum
    FROM cleaned.order_items GROUP BY 1
),
pay_totals AS (
    SELECT 
        order_id, 
        SUM(payment_value) as pay_sum,
        -- Count how many times 'voucher' appears for this order
        COUNT(CASE WHEN payment_type = 'voucher' THEN 1 END) AS voucher_count
    FROM cleaned.order_payments 
    GROUP BY 1
)
SELECT 
    i.order_id, 
    i.item_sum, 
    p.pay_sum,
    p.voucher_count,
    ABS(i.item_sum - p.pay_sum) as discrepancy
FROM item_totals i
JOIN pay_totals p ON i.order_id = p.order_id
WHERE ABS(i.item_sum - p.pay_sum) > 1.00
ORDER BY discrepancy DESC;

-- only a handfull of 249 rows paid with voucher

-- check to see if paying by installments is this cause

SELECT 
    p.payment_installments, 
    COUNT(*) as order_count,
    ROUND(AVG(ABS(i.item_sum - p.pay_sum))::numeric, 2) as avg_discrepancy
FROM (SELECT order_id, SUM(price + freight_value) as item_sum FROM cleaned.order_items GROUP BY 1) i
JOIN (SELECT order_id, SUM(payment_value) as pay_sum, MAX(payment_installments) as payment_installments 
      FROM cleaned.order_payments GROUP BY 1) p ON i.order_id = p.order_id
WHERE ABS(i.item_sum - p.pay_sum) > 1.00
GROUP BY 1
ORDER BY 1 DESC;

/* Results:
24	1	61.69
21	1	61.01
20	1	111.89
15	2	33.30
13	1	25.12
12	14	24.83
11	4	17.14
10	34	30.97
9	7	15.49
8	15	15.98
7	18	10.05
6	30	10.18
5	31	8.44
4	35	4.32
3	34	3.77
2	8	1.47
1	13	6.15
*/

---trend shows more installments the  bigger the discrepency 

-- could be due to interest fees being charged on installments that isnt taken into account in the order_items table. Paying in installments is very common in brazil

/* DATA QUALITY INSIGHT: 
Discrepancy analysis confirms that orders with higher installment counts (5-7) 
exhibit a higher variance between Item Price and Payment Value (Avg ~$10). 
This suggests that the order_payments table captures financing fees or 
interest not present in the order_items table. 

DECISION: All revenue KPIs will be derived from order_payments.payment_value 
to ensure we are reporting on the total gross cash flow, including fees.
*/



-- 99441 orders count of order_id
-- 98666 order_items count of order_id

SELECT 
    o.order_status, 
    COUNT(o.order_id) AS total_orders
FROM cleaned.orders o
LEFT JOIN cleaned.order_items i ON o.order_id = i.order_id
WHERE i.order_id IS NULL 
GROUP BY 1;
 
 /* results:

"canceled"	164
"created"	5
"invoiced"	2
"shipped"	1
"unavailable"	603
*/

/* VALIDATION: Order vs. Order_Items Row Count Mismatch
Finding: 775 orders have no associated items. 
Reasoning: Most are 'unavailable' or 'canceled'. 
Action: Use order_payments as the source of truth for revenue to capture actual money processed.
*/
-- order_payments has orders that actually that were actually paid for, i will use this for calculating revenue


-- used subquery to find orders that used multiple payment methods to pay for the same order
SELECT 
    order_id, 
    payment_sequential, 
    payment_type, 
    payment_value
FROM cleaned.order_payments
WHERE order_id IN (
    -- This inner part finds the IDs with multiple types
    SELECT order_id 
    FROM cleaned.order_payments 
    GROUP BY order_id 
    HAVING COUNT(DISTINCT payment_type) > 1
)
ORDER BY order_id, payment_sequential;

--Behavioral Validation. It proves that  data model correctly handles "One-to-Many" relationships (one order having many payment rows).Import to avoid duplication



-- Check for logically impossible dates
SELECT COUNT(*) 
FROM cleaned.orders 
WHERE order_purchase_timestamp > NOW() 
   OR order_purchase_timestamp < '2016-01-01';