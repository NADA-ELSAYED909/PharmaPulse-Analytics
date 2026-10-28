/* =====================================================================
   PharmaPulse Analytics - SQL analysis (SQL Server)
   22 queries on the cleaned data: JOIN, GROUP BY, HAVING, CASE WHEN,
   CTE, LAG, RANK. Run each query on its own (select it, then Execute).
   ===================================================================== */

-- One-time setup after importing sales_cleaned.csv as "sales_cleaned 2":
--   EXEC sp_rename 'dbo.[sales_cleaned 2]', 'Sales_cleaned';
--   ALTER TABLE dbo.Sales_cleaned ALTER COLUMN is_loss INT;

-- Sanity check: expect 9900 rows, revenue ~3,158,944, profit ~1,109,265, 608 loss sales
-- SELECT COUNT(*) AS rows_n, SUM(total_amount) AS revenue, SUM(profit) AS profit, SUM(is_loss) AS loss_count FROM dbo.Sales_cleaned;

USE Pharrmacy;
GO

-- Q1: How many sales are there, and how many distinct customers bought?
select count(*) as total_sales,
       count(distinct customer_id) as distinct_customers
from dbo.sales_cleaned;

-- Q2: What are the total revenue and total profit?
select sum(total_amount) as total_revenue,
       sum(profit)       as total_profit
from dbo.Sales_cleaned;

-- Q3: What are the 10 most expensive products?
select top 10 product_id,product_name,unit_price
from dbo.[product catalog]
order by unit_price DESC;

-- Q4: How many employees are there in each position?
select position, count(*) as employee_count
from dbo.Employees
group by position
order by employee_count DESC;

-- Q5: Which stock records are below their reorder level?
SELECT st.store_name, p.product_name, s.quantity, s.reorder_level
FROM dbo.Stock_condition s
JOIN dbo.Stores st           ON s.store_id   = st.store_id
JOIN dbo.[product catalog] p ON s.product_id = p.product_id
WHERE s.quantity < s.reorder_level;

-- Q6: What are the total revenue and profit per store?
SELECT st.store_name,
       SUM(s.total_amount) AS total_revenue,
       SUM(s.profit)       AS total_profit
FROM dbo.Sales_cleaned s
JOIN dbo.Stores st ON s.store_id = st.store_id
GROUP BY st.store_name
ORDER BY total_revenue DESC;

--Q7: How many sales were made with each payment method?
SELECT payment_method, COUNT(*) AS num_sales
FROM dbo.Sales_cleaned
GROUP BY payment_method
ORDER BY num_sales DESC;
 
-- Q8: How many products are in each category?
SELECT c.category_name, COUNT(*) AS product_count
FROM dbo.[product catalog] p
JOIN dbo.Categories c ON p.category_id = c.category_id
GROUP BY c.category_name
ORDER BY product_count DESC;
 
 -- Q9: Who are the top 5 doctors by number of prescriptions?
SELECT TOP 5 doctor_name, COUNT(*) AS prescription_count
FROM dbo.Prescriptions
GROUP BY doctor_name
ORDER BY prescription_count DESC;
 
-- Q10: For each supplier, how many products do they supply and what is the average margin (unit_price - cost_price)?
SELECT sp.supplier_name,
       COUNT(*)                         AS product_count,
       AVG(p.unit_price - p.cost_price) AS avg_margin
FROM dbo.[product catalog] p
JOIN dbo.Suppliers sp ON p.supplier_id = sp.supplier_id
GROUP BY sp.supplier_name
ORDER BY avg_margin DESC;
 
 -- Q11: Who are the top 10 customers by total spending?
SELECT TOP 10 c.full_name, c.city_1, SUM(s.total_amount) AS total_spent
FROM dbo.Sales_cleaned s
JOIN dbo.Customer_master c ON s.customer_id = c.customer_id
GROUP BY c.full_name, c.city_1
ORDER BY total_spent DESC;
 
-- Q12: What is the total revenue per month? (sales without a date are skipped)
SELECT YEAR(sale_date)  AS sale_year,
       MONTH(sale_date) AS sale_month,
       SUM(total_amount) AS total_revenue
FROM dbo.Sales_cleaned
WHERE sale_date IS NOT NULL
GROUP BY YEAR(sale_date), MONTH(sale_date)
ORDER BY sale_year, sale_month;
 
-- Q13: What are the revenue and profit per product category?
SELECT c.category_name,
       SUM(s.total_amount) AS total_revenue,
       SUM(s.profit)       AS total_profit
FROM dbo.Sales_cleaned s
JOIN dbo.[product catalog] p ON s.product_id  = p.product_id
JOIN dbo.Categories c        ON p.category_id = c.category_id
GROUP BY c.category_name
ORDER BY total_revenue DESC;

-- Q14: Which categories lose the most sales?
SELECT c.category_name,
       COUNT(*) AS total_sales,
       SUM(s.is_loss) AS loss_sales,
       ROUND(100.0 * SUM(s.is_loss) / COUNT(*), 2) AS loss_rate_pct
FROM dbo.sales_cleaned s
JOIN dbo.[product catalog] p ON s.product_id = p.product_id
JOIN dbo.Categories c ON p.category_id = c.category_id
GROUP BY c.category_name
ORDER BY loss_rate_pct DESC;

-- Q15: Which 10 products lose the most money?
SELECT TOP 10 p.product_id, p.product_name,
       COUNT(*) AS loss_sales,
       SUM(s.profit) AS total_loss
FROM dbo.Sales_cleaned s
JOIN dbo.[product catalog] p ON s.product_id = p.product_id
WHERE s.is_loss = 1
GROUP BY p.product_id, p.product_name
ORDER BY total_loss ASC;

-- Q16: Do bigger discounts reduce the margin?
SELECT discount_band,
       COUNT(*) AS sales_count,
       SUM(total_amount) AS revenue,
       ROUND(100.0 * SUM(profit) / SUM(total_amount), 2) AS margin_pct,
       ROUND(100.0 * SUM(is_loss) / COUNT(*), 2) AS loss_rate_pct
FROM dbo.Sales_cleaned
GROUP BY discount_band
ORDER BY discount_band;

-- Q17: How does revenue change month over month? (LAG)
WITH monthly AS (
    SELECT sale_month, SUM(total_amount) AS revenue
    FROM dbo.Sales_cleaned
    WHERE sale_month IS NOT NULL
    GROUP BY sale_month
)
SELECT sale_month, revenue,
       LAG(revenue) OVER (ORDER BY sale_month) AS prev_month,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY sale_month))
             / LAG(revenue) OVER (ORDER BY sale_month), 2) AS mom_growth_pct
FROM monthly
ORDER BY sale_month;

-- Q18: What are the top 3 products by profit inside each category? (RANK)
WITH product_profit AS (
    SELECT c.category_name, p.product_name, SUM(s.profit) AS total_profit
    FROM dbo.Sales_cleaned s
    JOIN dbo.[product catalog] p ON s.product_id = p.product_id
    JOIN dbo.Categories c ON p.category_id = c.category_id
    GROUP BY c.category_name, p.product_name
),
ranked AS (
    SELECT *, RANK() OVER (PARTITION BY category_name ORDER BY total_profit DESC) AS rnk
    FROM product_profit
)
SELECT * FROM ranked WHERE rnk <= 3 ORDER BY category_name, rnk;

-- Q19: Do promo codes bring revenue or just eat profit?
SELECT ISNULL(promo_code, 'No promo') AS promo_code,
       COUNT(*) AS sales_count,
       SUM(total_amount) AS revenue,
       ROUND(AVG(discount_pct), 2) AS avg_discount,
       ROUND(100.0 * SUM(profit) / SUM(total_amount), 2) AS margin_pct
FROM dbo.Sales_cleaned
GROUP BY ISNULL(promo_code, 'No promo')
ORDER BY revenue DESC;

-- Q20: Which loyalty tier brings the most revenue?
SELECT ISNULL(c.loyalty_tier, 'No tier') AS loyalty_tier,
       COUNT(DISTINCT c.customer_id) AS customers,
       SUM(s.total_amount) AS revenue,
       ROUND(SUM(s.total_amount) / COUNT(DISTINCT c.customer_id), 2) AS revenue_per_customer
FROM dbo.Sales_cleaned s
JOIN dbo.Customer_master c ON s.customer_id = c.customer_id
GROUP BY ISNULL(c.loyalty_tier, 'No tier')
ORDER BY revenue DESC;

-- Q21: Which stores have a high loss rate? (HAVING)
SELECT st.store_name,
       COUNT(*) AS sales_count,
       ROUND(100.0 * SUM(s.is_loss) / COUNT(*), 2) AS loss_rate_pct
FROM dbo.Sales_cleaned s
JOIN dbo.Stores st ON s.store_id = st.store_id
GROUP BY st.store_name
HAVING 100.0 * SUM(s.is_loss) / COUNT(*) > 6.14
ORDER BY loss_rate_pct DESC;

-- Q22: Which categories have products priced below cost? (CASE WHEN)
SELECT c.category_name,
       COUNT(*) AS products,
       SUM(CASE WHEN p.cost_price > p.unit_price THEN 1 ELSE 0 END) AS priced_below_cost
FROM dbo.[product catalog] p
JOIN dbo.Categories c ON p.category_id = c.category_id
GROUP BY c.category_name
ORDER BY priced_below_cost DESC;
