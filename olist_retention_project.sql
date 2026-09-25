-- ============================================
-- Olist Customer Retention & RFM Segmentation
-- ============================================
-- Business question: Why do so few Olist customers buy again,
-- and who are the most valuable ones?
-- Tool: SQLite (DB Browser for SQLite)
-- Data: Brazilian E-Commerce Public Dataset by Olist (Kaggle)

-- Indexes to speed up joins
CREATE INDEX IF NOT EXISTS idx_orders_id ON orders(order_id);
CREATE INDEX IF NOT EXISTS idx_orders_cust ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_items_order ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_cust_id ON customers(customer_id);
CREATE INDEX IF NOT EXISTS idx_reviews_order ON reviews(order_id);

-- Step 3: explore the data
SELECT order_status, COUNT(*) AS orders
FROM orders
GROUP BY order_status
ORDER BY orders DESC;

SELECT COUNT(DISTINCT customer_id) AS customer_ids,
       COUNT(DISTINCT customer_unique_id) AS real_customers
FROM customers;

-- Step 5: one clean row per delivered order
DROP VIEW IF EXISTS delivered_orders;
CREATE VIEW delivered_orders AS
SELECT o.order_id,
       c.customer_unique_id,
       c.customer_state,
       DATE(o.order_purchase_timestamp) AS order_date,
       SUM(oi.price + oi.freight_value) AS order_value,
       CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN 1 ELSE 0 END AS is_late
FROM orders o
JOIN customers c    ON o.customer_id = c.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY o.order_id;

SELECT COUNT(*) FROM delivered_orders;  -- 96,470

-- Step 6: how many customers ever came back?
SELECT COUNT(*) AS customers,
       SUM(n > 1) AS repeat_customers,
       ROUND(100.0 * SUM(n > 1) / COUNT(*), 2) AS repeat_pct
FROM (SELECT customer_unique_id, COUNT(*) AS n
      FROM delivered_orders
      GROUP BY customer_unique_id);

-- Step 7: RFM segmentation
DROP TABLE IF EXISTS rfm;
CREATE TABLE rfm AS
WITH base AS (
  SELECT customer_unique_id,
         CAST(julianday((SELECT MAX(order_date) FROM delivered_orders))
              - julianday(MAX(order_date)) AS INT) AS recency,
         COUNT(*) AS frequency,
         ROUND(SUM(order_value), 2) AS monetary
  FROM delivered_orders
  GROUP BY customer_unique_id
), scored AS (
  SELECT *,
         NTILE(5) OVER (ORDER BY recency DESC) AS r,
         CASE WHEN frequency >= 3 THEN 5
              WHEN frequency = 2 THEN 4
              ELSE 1 END AS f,  -- scored by hand: 97% have one order
         NTILE(5) OVER (ORDER BY monetary) AS m
  FROM base
)
SELECT *,
  CASE
    WHEN f >= 4 AND r >= 4 THEN 'Champions'
    WHEN f >= 4            THEN 'Loyal, drifting'
    WHEN r >= 4 AND m >= 4 THEN 'New big spenders'
    WHEN r >= 4            THEN 'New customers'
    WHEN r <= 2 AND m >= 4 THEN 'At risk (high value)'
    WHEN r <= 2            THEN 'Lost'
    ELSE 'Need attention'
  END AS segment
FROM scored;

-- Step 7b: segment summary
SELECT segment,
       COUNT(*) AS customers,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM rfm), 1) AS pct,
       ROUND(AVG(monetary), 2) AS avg_spend,
       ROUND(100.0 * SUM(monetary) / (SELECT SUM(monetary) FROM rfm), 1) AS revenue_pct
FROM rfm
GROUP BY segment
ORDER BY revenue_pct DESC;

-- Step 8: cohort retention (returned within 90 days)
WITH firsts AS (
  SELECT customer_unique_id,
         MIN(order_date) AS first_date,
         strftime('%Y-%m', MIN(order_date)) AS cohort
  FROM delivered_orders
  GROUP BY customer_unique_id
)
SELECT f.cohort,
       COUNT(DISTINCT f.customer_unique_id) AS cohort_size,
       ROUND(100.0 * COUNT(DISTINCT CASE
             WHEN d.order_date > f.first_date
              AND julianday(d.order_date) - julianday(f.first_date) <= 90
             THEN f.customer_unique_id END)
             / COUNT(DISTINCT f.customer_unique_id), 2) AS returned_90d_pct
FROM firsts f
JOIN delivered_orders d ON d.customer_unique_id = f.customer_unique_id
WHERE f.cohort BETWEEN '2017-01' AND '2018-05'
GROUP BY f.cohort
ORDER BY f.cohort;

-- Step 9a: late vs on-time delivery and review scores
SELECT CASE d.is_late WHEN 1 THEN 'Late' ELSE 'On time' END AS delivery,
       COUNT(*) AS orders,
       ROUND(AVG(r.review_score), 2) AS avg_score,
       ROUND(100.0 * SUM(r.review_score = 1) / COUNT(*), 1) AS one_star_pct
FROM delivered_orders d
JOIN reviews r ON r.order_id = d.order_id
GROUP BY delivery;

-- Step 9b: does the first order's review predict returning?
WITH ranked AS (
  SELECT d.customer_unique_id, r.review_score,
         ROW_NUMBER() OVER (PARTITION BY d.customer_unique_id
                            ORDER BY d.order_date) AS rn,
         COUNT(*) OVER (PARTITION BY d.customer_unique_id) AS total_orders
  FROM delivered_orders d
  LEFT JOIN reviews r ON r.order_id = d.order_id
)
SELECT review_score AS first_order_score,
       COUNT(*) AS customers,
       ROUND(100.0 * SUM(total_orders > 1) / COUNT(*), 2) AS came_back_pct
FROM ranked
WHERE rn = 1 AND review_score IS NOT NULL
GROUP BY review_score
ORDER BY review_score;

-- Step 9c: late delivery by state
SELECT customer_state,
       COUNT(DISTINCT customer_unique_id) AS customers,
       ROUND(SUM(order_value)) AS revenue,
       ROUND(100.0 * SUM(is_late) / COUNT(*), 1) AS late_pct
FROM delivered_orders
GROUP BY customer_state
ORDER BY revenue DESC
LIMIT 8;

-- ============================================
-- KEY FINDINGS
-- ============================================
-- 1. Only 3.0% of customers (2,801 of 93,350) ever ordered again.
-- 2. One-time high spenders drive 56% of revenue; loyal customers
--    (Champions + Loyal) are 3% of customers and 5.6% of revenue.
-- 3. Monthly new customers grew ~9x in 2017-2018, but the 90-day
--    return rate stayed flat at 1-2%. Black Friday (Nov 2017)
--    brought record signups but no extra loyalty.
-- 4. Late orders get 1 star 46% of the time vs 6.6% on time.
-- 5. A bad first review does NOT reduce returning: 1-star and
--    5-star first-time customers return at the same ~3% rate.
-- 6. RJ (13.5%) and BA (14.0%) are late twice as often as SP (5.9%).
--
-- RECOMMENDATIONS
-- - Target "New big spenders" with a second-purchase incentive.
-- - Fix delivery to RJ and BA to protect ratings in big markets.
-- - Don't expect better delivery alone to fix retention.
