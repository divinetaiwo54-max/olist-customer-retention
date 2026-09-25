# olist-customer-retention
Customer retention and RFM segmentation on Brazilian e-commerce data using SQL (SQLite).
# Olist Customer Retention & RFM Segmentation

SQL analysis of ~100,000 orders from the Brazilian e-commerce marketplace Olist.

**Business question:** Why do so few customers buy again, and who are the most valuable ones?

## Key findings
- Only **3.0%** of customers ever ordered a second time.
- One-time high spenders bring in **56%** of revenue.
- New customers grew ~9x, but the 90-day return rate stayed flat at 1–2%.
- Late orders get 1 star **46%** of the time vs 6.6% when on time.
- A bad first review does **not** reduce returning (3.0% vs 3.2%), so low retention isn't caused by bad service.
- Rio de Janeiro and Bahia are late twice as often as São Paulo.

## Tools & techniques
SQLite · joins · views · CTEs · window functions (NTILE, ROW_NUMBER) · date functions

## Files
- `olist_retention_project.sql`: all queries
- `Olist_Retention_Report.docx`: full write-up with tables and chart

## Data
[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (Kaggle)
