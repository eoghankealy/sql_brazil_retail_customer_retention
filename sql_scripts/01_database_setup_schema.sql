/* =========================================================
   BRAZILIAN RETAIL SQL PROJECT
   Dataset: Olist E-Commerce
   Phase 1: Database Setup
   Author: Eoghan Kealy
   Database: PostgreSQL
   ========================================================= */


-- Creat a raw schema for staging the data and a cleaned schema for the data to be cleaned and transformed 
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS cleaned;


--  Create the Staging Tables 
--  use TEXT for everything here to ensure the CSV imports without errors.

DROP TABLE IF EXISTS raw.customers; 

CREATE TABLE raw.customers (
    customer_id TEXT,
    customer_unique_id TEXT,
    customer_zip_code_prefix TEXT,
    customer_city TEXT,
    customer_state TEXT
);

DROP TABLE IF EXISTS raw.geolocation;

CREATE TABLE raw.geolocation (
    geolocation_zip_code_prefix TEXT,
    geolocation_lat TEXT,
    geolocation_lng TEXT,
    geolocation_city TEXT,
    geolocation_state TEXT
);

DROP TABLE IF EXISTS raw.order_items;

CREATE TABLE raw.order_items (
    order_id TEXT,
    order_item_id TEXT,
    product_id TEXT,
    seller_id TEXT,
    shipping_limit_date TEXT,
    price TEXT,
    freight_value TEXT
);

DROP TABLE IF EXISTS raw.order_payments;

CREATE TABLE raw.order_payments (
    order_id TEXT,
    payment_sequential TEXT,
    payment_type TEXT,
    payment_installments TEXT,
    payment_value TEXT  
);

DROP TABLE IF EXISTS raw.order_reviews;

CREATE TABLE raw.order_reviews (
    review_id TEXT,
    order_id TEXT,
    review_score TEXT,
    review_comment_title TEXT,
    review_comment_message TEXT,
    review_creation_date TEXT,
    review_answer_timestamp TEXT   
);

DROP TABLE IF EXISTS raw.orders;

CREATE TABLE raw.orders (
    order_id TEXT,
    customer_id TEXT,
    order_status TEXT,
    order_purchase_timestamp TEXT,
    order_approved_at TEXT,
    order_delivered_carrier_date TEXT,
    order_delivered_customer_date TEXT,
    order_estimated_delivery_date TEXT
);

DROP TABLE IF EXISTS raw.products;

CREATE TABLE raw.products (
    product_id TEXT,
    product_category_name TEXT,
    product_name_length TEXT,
    product_description_length TEXT,
    product_photos_qty TEXT,
    product_weight_g TEXT,
    product_length_cm TEXT,
    product_height_cm TEXT,
    product_width_cm TEXT
);

DROP TABLE IF EXISTS raw.sellers;

CREATE TABLE raw.sellers (
    seller_id TEXT,
    seller_zip_code_prefix TEXT,
    seller_city TEXT,
    seller_state TEXT 
);

DROP TABLE IF EXISTS raw.product_category_name_translation;

CREATE TABLE raw.product_category_name_translation(
product_category_name TEXT,
product_category_name_english TEXT
);


-- now load in the csv to raw schema tables, use COPY command as faster for large datsets

COPY raw.customers 
FROM '/path/to/olist_customers_dataset.csv' 
DELIMITER ',' 
CSV HEADER 
ENCODING 'UTF8';


-- Count the total rows to see if it matches the amount of rows Terminal finds in the csv file
SELECT COUNT(*) FROM raw.customers;
-- Terminal comand to count the rows in the orgional csvfile
--- wc -l /path/to/olist_customers_dataset.csv


-- repeat steps  for other tables
COPY raw.geolocation 
FROM '/path/to/olist_geolocation_dataset.csv' 
DELIMITER ',' 
CSV HEADER 
ENCODING 'UTF8';

SELECT COUNT(*) FROM raw.geolocation;


COPY raw.order_items 
FROM '/path/to/olist_order_items_dataset.csv' 
DELIMITER ',' 
CSV HEADER 
ENCODING 'UTF8';

SELECT COUNT(*) FROM raw.order_items;


COPY raw.order_payments 
FROM '/path/to/olist_order_payments_dataset.csv' 
DELIMITER ',' 
CSV HEADER 
ENCODING 'UTF8';

SELECT COUNT(*) FROM raw.order_payments;

COPY raw.order_reviews 
FROM '/path/to/olist_order_reviews_dataset.csv' 
DELIMITER ',' 
CSV HEADER 
ENCODING 'UTF8';

SELECT COUNT(*) FROM raw.order_reviews;


COPY raw.orders 
FROM '/path/to/olist_orders_dataset.csv' 
DELIMITER ',' 
CSV HEADER 
ENCODING 'UTF8';

SELECT COUNT(*) FROM raw.orders;



COPY raw.products 
FROM '/path/to/olist_products_dataset.csv' 
DELIMITER ',' 
CSV HEADER 
ENCODING 'UTF8';

SELECT COUNT(*) FROM raw.products;

COPY raw.sellers
FROM '/path/to/olist_sellers_dataset.csv' 
DELIMITER ',' 
CSV HEADER 
ENCODING 'UTF8';

SELECT COUNT(*) FROM raw.sellers;


COPY raw.product_category_name_translation
FROM '/path/to/product_category_name_translation.csv' 
DELIMITER ',' 
CSV HEADER 
ENCODING 'UTF8';

SELECT COUNT(*) FROM raw.product_category_name_translation;



----- Created Cleaned tables

DROP TABLE IF EXISTS cleaned.customers;

CREATE TABLE cleaned.customers (
    customer_id TEXT PRIMARY KEY,
    customer_unique_id TEXT NOT NULL,
    zip_code_prefix TEXT NOT NULL,
    city TEXT NOT NULL,
    state CHAR(2) NOT NULL
);

INSERT INTO cleaned.customers
SELECT
    TRIM(customer_id),
    TRIM(customer_unique_id),
    TRIM(customer_zip_code_prefix),
    INITCAP(TRIM(customer_city)),
    UPPER(TRIM(customer_state))
FROM raw.customers;




---- Steps are repeated for the other tables

SELECT 
    COUNT(*) AS total_rows,
    COUNT(*) - COUNT(DISTINCT (zip_code_prefix, lat, lng)) AS total_duplicate_rows
FROM cleaned.geolocation;

---- geolcation table has many duplicates so zip code will be grouped and an average of the latitude and logitude found 
DROP TABLE IF EXISTS cleaned.geolocation;

-- 1️⃣ Define structure explicitly
CREATE TABLE cleaned.geolocation (
    zip_code_prefix TEXT PRIMARY KEY,
    lat DOUBLE PRECISION NOT NULL,
    lng DOUBLE PRECISION NOT NULL,
    city TEXT NOT NULL,
    state CHAR(2) NOT NULL
);

-- 2️⃣ Insert transformed + aggregated data
INSERT INTO cleaned.geolocation (
    zip_code_prefix,
    lat,
    lng,
    city,
    state
)
SELECT
    TRIM(geolocation_zip_code_prefix) AS zip_code_prefix,
    AVG(geolocation_lat::DOUBLE PRECISION) AS lat, -- Averages the coordinates
    AVG(geolocation_lng::DOUBLE PRECISION) AS lng,
    MAX(INITCAP(TRIM(geolocation_city))) AS city,-- Picks one valid city name
    MAX(UPPER(TRIM(geolocation_state))) AS state -- Picks the state
FROM raw.geolocation
GROUP BY TRIM(geolocation_zip_code_prefix);


-- check count again
SELECT COUNT(*) FROM cleaned.geolocation;

-- order_items table needs a composie primary key as order_id appears multiple times due to multple order_item_ids for each order

-- make sure  composite key order_id and order_item_id are unique
SELECT order_id, order_item_id, COUNT(*)
FROM raw.order_items
GROUP BY order_id, order_item_id
HAVING COUNT(*) > 1;


DROP TABLE IF EXISTS cleaned.order_items;

-- 1️⃣ Define structure explicitly
CREATE TABLE cleaned.order_items (
    order_id TEXT NOT NULL,
    order_item_id INTEGER NOT NULL,
    product_id TEXT NOT NULL,
    seller_id TEXT NOT NULL,
    shipping_limit_date TIMESTAMP NOT NULL,
    price NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    freight_value NUMERIC(10,2) NOT NULL CHECK (freight_value >= 0),

    PRIMARY KEY (order_id, order_item_id)
);

-- 2️⃣ Insert cleaned data
INSERT INTO cleaned.order_items (
    order_id,
    order_item_id,
    product_id,
    seller_id,
    shipping_limit_date,
    price,
    freight_value
)
SELECT
    TRIM(order_id),
    TRIM(order_item_id)::INTEGER,
    TRIM(product_id),
    TRIM(seller_id),
    shipping_limit_date::TIMESTAMP,
    price::NUMERIC(10,2),
    freight_value::NUMERIC(10,2)
FROM raw.order_items;

-- Check count matches raw table
SELECT COUNT(*) FROM cleaned.order_items;

-- order_payments will also need a composite primary key
SELECT order_id, COUNT(*) 
FROM raw.order_payments
GROUP BY order_id
HAVING COUNT(*) > 1;

-- check to see why order_id is repeated
SELECT * 
FROM raw.order_payments
WHERE order_id = '53f5a7f622d498ff3eeb334b8efa7ae7';

-- check to make sure composite key is unique
SELECT order_id, payment_sequential, COUNT(*)
FROM raw.order_payments
GROUP BY order_id, payment_sequential
HAVING COUNT(*) > 1;



DROP TABLE IF EXISTS cleaned.order_payments;

-- 1️⃣ Define structure explicitly
CREATE TABLE cleaned.order_payments (
    order_id TEXT NOT NULL,
    payment_sequential INTEGER NOT NULL,
    payment_type TEXT NOT NULL,
    payment_installments INTEGER NOT NULL CHECK (payment_installments >= 0),
    payment_value NUMERIC(10,2) NOT NULL CHECK (payment_value >= 0),

    PRIMARY KEY (order_id, payment_sequential)
);

-- 2️⃣ Insert cleaned data
INSERT INTO cleaned.order_payments (
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    payment_value
)
SELECT
    TRIM(order_id),
    payment_sequential::INTEGER,
    TRIM(payment_type),
    payment_installments::INTEGER,
    payment_value::NUMERIC(10,2)
FROM raw.order_payments;



DROP TABLE IF EXISTS cleaned.order_reviews;

CREATE TABLE cleaned.order_reviews (
    review_id TEXT NOT NULL,
    order_id TEXT NOT NULL,
    review_score INTEGER CHECK (review_score BETWEEN 1 AND 5),
    review_comment_title TEXT,
    review_comment_message TEXT,
    review_creation_date TIMESTAMP,
    review_answer_timestamp TIMESTAMP,
    PRIMARY KEY (order_id, review_id)
);
/* =========================================================
   NULLIF Strategy:
   Converts empty strings ('') to proper NULL values before
   type casting. This prevents casting errors and maintains
   data quality standards (NULL vs empty string distinction).
   ========================================================= */

INSERT INTO cleaned.order_reviews
SELECT 
    TRIM(review_id),
    TRIM(order_id),
    NULLIF(review_score, '')::INTEGER,
    NULLIF(TRIM(review_comment_title), ''),
    NULLIF(TRIM(review_comment_message), ''),
    NULLIF(review_creation_date, '')::TIMESTAMP,
    NULLIF(review_answer_timestamp, '')::TIMESTAMP
FROM raw.order_reviews;




SELECT COUNT(*) FROM  cleaned.order_reviews;

--- cleaned.products table

DROP TABLE IF EXISTS cleaned.products;

CREATE TABLE cleaned.products (
    product_id TEXT PRIMARY KEY,
    product_category_name TEXT,
    product_name_length INTEGER CHECK (product_name_length >= 0),
    product_description_length INTEGER CHECK (product_description_length >= 0),
    product_photos_qty INTEGER CHECK (product_photos_qty >= 0),
    product_weight_g INTEGER CHECK (product_weight_g >= 0),
    product_length_cm INTEGER CHECK (product_length_cm >= 0),
    product_height_cm INTEGER CHECK (product_height_cm >= 0),
    product_width_cm INTEGER CHECK (product_width_cm >= 0)
);

INSERT INTO cleaned.products
SELECT 
    TRIM(product_id),
    NULLIF(TRIM(product_category_name), ''),
    NULLIF(product_name_length, '')::INTEGER,
    NULLIF(product_description_length, '')::INTEGER,
    NULLIF(product_photos_qty, '')::INTEGER,
    NULLIF(product_weight_g, '')::INTEGER,
    NULLIF(product_length_cm, '')::INTEGER,
    NULLIF(product_height_cm, '')::INTEGER,
    NULLIF(product_width_cm, '')::INTEGER
FROM raw.products;


--- cleaned.orders table


DROP TABLE IF EXISTS cleaned.orders;

CREATE TABLE cleaned.orders (
    order_id TEXT PRIMARY KEY,
    customer_id TEXT NOT NULL,
    order_status TEXT NOT NULL,
    order_purchase_timestamp TIMESTAMP,
    order_approved_at TIMESTAMP,
    order_delivered_carrier_date TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP
);

INSERT INTO cleaned.orders
SELECT 
    TRIM(order_id),
    TRIM(customer_id),
    LOWER(TRIM(order_status)),
    NULLIF(order_purchase_timestamp, '')::TIMESTAMP,
    NULLIF(order_approved_at, '')::TIMESTAMP,
    NULLIF(order_delivered_carrier_date, '')::TIMESTAMP,
    NULLIF(order_delivered_customer_date, '')::TIMESTAMP,
    NULLIF(order_estimated_delivery_date, '')::TIMESTAMP
FROM raw.orders;


-- cleaned.product_category_name_translation

DROP TABLE IF EXISTS cleaned.product_category_name_translation;

CREATE TABLE cleaned.product_category_name_translation (
    product_category_name TEXT PRIMARY KEY,
    product_category_name_english TEXT NOT NULL
);

INSERT INTO cleaned.product_category_name_translation
SELECT 
    TRIM(product_category_name),
    TRIM(product_category_name_english)
FROM raw.product_category_name_translation;


-- cleaned.sellers table

DROP TABLE IF EXISTS cleaned.sellers;

CREATE TABLE cleaned.sellers (
    seller_id TEXT PRIMARY KEY,
    zip_code_prefix TEXT NOT NULL,
    city TEXT NOT NULL,
    state CHAR(2) NOT NULL
);

INSERT INTO cleaned.sellers
SELECT
    TRIM(seller_id),
    TRIM(seller_zip_code_prefix),
    INITCAP(TRIM(seller_city)),
    UPPER(TRIM(seller_state))
FROM raw.sellers;





   -- FOREIGN KEY CONSTRAINTS - 


-- orders → customers
ALTER TABLE cleaned.orders 
ADD CONSTRAINT fk_orders_customer_id 
FOREIGN KEY (customer_id) REFERENCES cleaned.customers(customer_id);

-- order_items → orders
ALTER TABLE cleaned.order_items 
ADD CONSTRAINT fk_order_items_order_id 
FOREIGN KEY (order_id) REFERENCES cleaned.orders(order_id);

-- order_items → products
ALTER TABLE cleaned.order_items 
ADD CONSTRAINT fk_order_items_product_id 
FOREIGN KEY (product_id) REFERENCES cleaned.products(product_id);

-- order_items → sellers
ALTER TABLE cleaned.order_items 
ADD CONSTRAINT fk_order_items_seller_id 
FOREIGN KEY (seller_id) REFERENCES cleaned.sellers(seller_id);

-- order_payments → orders
ALTER TABLE cleaned.order_payments 
ADD CONSTRAINT fk_order_payments_order_id 
FOREIGN KEY (order_id) REFERENCES cleaned.orders(order_id);

-- order_reviews → orders
ALTER TABLE cleaned.order_reviews 
ADD CONSTRAINT fk_order_reviews_order_id 
FOREIGN KEY (order_id) REFERENCES cleaned.orders(order_id);



/* =========================================================
   NOTE: Reference Table Foreign Keys Intentionally Omitted
   
   Did NOT add foreign keys to incomplete lookup tables:
   - geolocation (missing zip codes for some customers/sellers)
   - product_category_name_translation (missing 13 categories)
   
   These tables are used for enrichment via LEFT JOINs in queries,
   not for enforcing hard referential integrity constraints.
   ========================================================= */


   /* =========================================================
   INDEXES FOR QUERY OPTIMIZATION
   
   Adding indexes on foreign key columns to improve JOIN performance.
   While not critical at this data size, this follows production 
   best practices for scalability.
   ========================================================= */

-- orders table
CREATE INDEX idx_orders_customer_id ON cleaned.orders(customer_id);

-- order_items table
CREATE INDEX idx_order_items_order_id ON cleaned.order_items(order_id);
CREATE INDEX idx_order_items_product_id ON cleaned.order_items(product_id);
CREATE INDEX idx_order_items_seller_id ON cleaned.order_items(seller_id);

-- order_payments table
CREATE INDEX idx_order_payments_order_id ON cleaned.order_payments(order_id);

-- order_reviews table
CREATE INDEX idx_order_reviews_order_id ON cleaned.order_reviews(order_id);


