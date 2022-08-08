--In a single query, perform the following operations and generate a new table named clean_weekly_sales:
/*	- Convert the week_date to a DATE format
	- Add a week_number as the second column for each week_date value, for example any value from the 1st of January to 7th of January will be 1, 8th to 14th will be 2 etc
	- Add a month_number with the calendar month for each week_date value as the 3rd column
	- Add a calendar_year column as the 4th column containing either 2018, 2019 or 2020 values
	- Add a new column called age_band after the original segment column using the following mapping on the number inside the segment value: 1 = Young Adults, 2 = Middle Aged, 3 or 4 = Retirees
	- Add a new demographic column using the following mapping for the first letter in the segment values: C = Couples, F = Families
	- Ensure all null string values with an "unknown" string value in the original segment column as well as the new age_band and demographic columns
	- Generate a new avg_transaction column as the sales value divided by transactions rounded to 2 decimal places for each record */

select 'Data Cleansing Steps' as title;
SET DATEFORMAT dmy;
DROP TABLE IF EXISTS clean_weekly_sales;
select 
	CAST(week_date as date) week_date,
	DATEPART(WEEK, CAST(week_date as date)) week_number,
	DATEPART(M, CAST(week_date as date)) month_number,
	DATEPART(YY, CAST(week_date as date)) calendar_year,
	region,
	platform,
	segment,
	case when RIGHT(segment, 1) = '1' then 'Young Adults'
		when RIGHT(segment, 1) = '2' then 'Middle Aged'
		when RIGHT(segment, 1) = '3' or RIGHT(segment, 1) = '4' then 'Retirees'
		else 'unknown' end age_band,
	case when LEFT(segment, 1) = 'C' then 'Couples'
		when LEFT(segment, 1) = 'F' then 'Families'
		else 'unknown' end demographic,
	customer_type,
	CAST(transactions as float) transactions,
	CAST(sales as float) sales,
	ROUND(CAST(sales as float)/CAST(transactions as float), 2) avg_transaction
into clean_weekly_sales
from weekly_sales;
select * from clean_weekly_sales;

--1. What day of the week is used for each week_date value?
select distinct
	DATENAME(WEEKDAY, week_date) day_name
from clean_weekly_sales;

--2. What range of week numbers are missing from the dataset?
WITH
	week_no --assume 1 year has 52 weeks
AS
	(
		SELECT top 52 
			ROW_NUMBER() OVER(ORDER BY name) week_no 
		FROM master.sys.all_columns
	)
select 
	COUNT(n.week_no) weeks_missing
from week_no n
left join clean_weekly_sales c on n.week_no = c.week_number
where c.week_number is null;

--3. How many total transactions were there for each year in the dataset?
select
	calendar_year,
	SUM(transactions) total_transactions
from clean_weekly_sales
group by calendar_year
order by calendar_year;

--4. What is the total sales for each region for each month?
select
	region,
	month_number,
	SUM(sales) total_sales
from clean_weekly_sales
group by region, month_number
order by region, month_number;

--5. What is the total count of transactions for each platform
select
	platform,
	COUNT(*) total_transactions
from clean_weekly_sales
group by platform;

--6. What is the percentage of sales for Retail vs Shopify for each month?
WITH 
	sales
AS
	(
		select
			calendar_year,
			month_number,
			platform,
			SUM(sales) total_sales
		from clean_weekly_sales
		group by calendar_year, month_number, platform
	)
select
	calendar_year,
	month_number,
	ROUND(100 * MAX(case when platform = 'Retail' 
		then total_sales else NULL end)/ SUM(total_sales), 2) retail_percentage,
	ROUND(100 * MAX(case when platform = 'Shopify' 
		then total_sales else NULL end)/ SUM(total_sales), 2) shopify_percentage
from sales
group by calendar_year, month_number
order by calendar_year, month_number;

--7. What is the percentage of sales by demographic for each year in the dataset?
WITH 
	sales
AS
	(
		select
			calendar_year,
			demographic,
			SUM(sales) total_sales
		from clean_weekly_sales
		group by calendar_year, demographic
	)
select
	calendar_year,
	ROUND(100 * MAX(case when demographic = 'Couples' 
		then total_sales else NULL end)/ SUM(total_sales), 2) couples_percentage,
	ROUND(100 * MAX(case when demographic = 'Families' 
		then total_sales else NULL end)/ SUM(total_sales), 2) families_percentage,
	ROUND(100 * MAX(case when demographic = 'unknown' 
		then total_sales else NULL end)/ SUM(total_sales), 2) unknown_percentage
from sales
group by calendar_year
order by calendar_year;

--8. Which age_band and demographic values contribute the most to Retail sales?
select
	age_band,
	demographic,
	SUM(sales) retail_sales,
	ROUND(100 * SUM(sales) / SUM(SUM(sales)) OVER(), 2) contribute_percent
from clean_weekly_sales
where platform = 'Retail'
group by age_band, demographic
order by retail_sales desc;

--9. Can we use the avg_transaction column to find the average transaction size for each year for Retail vs Shopify? If not - how would you calculate it instead?
select
	calendar_year,
	platform,
	ROUND(AVG(avg_transaction), 2) avg_transaction_row,
	ROUND(SUM(sales)/SUM(transactions), 2) avg_transaction_group
from clean_weekly_sales
group by calendar_year, platform
order by calendar_year, platform;

--10. What is the total sales for the 4 weeks before and after 2020-06-15? What is the growth or reduction rate in actual values and percentage of sales?
WITH
	weeks
AS
	(
		select
			SUM(case when week_number between 21 and 24 then sales end) sales_before,
			SUM(case when week_number between 25 and 28 then sales end) sales_after
		from clean_weekly_sales
		where calendar_year = 2020
	)
select *,
	sales_after - sales_before difference,
	ROUND(100 * (sales_after - sales_before)/sales_before,2) percentage
from weeks;

--11. What about the entire 12 weeks before and after?
WITH
	weeks
AS
	(
		select
			SUM(case when week_number between 13 and 24 then sales end) sales_before,
			SUM(case when week_number between 25 and 36 then sales end) sales_after
		from clean_weekly_sales
		where calendar_year = 2020
	)
select *,
	sales_after - sales_before difference,
	ROUND(100 * (sales_after - sales_before)/sales_before,2) percentage
from weeks;

--12. How do the sale metrics for these 2 periods before and after compare with the previous years in 2018 and 2019?
WITH
	weeks
AS
	(
		select
		calendar_year,
			SUM(case when week_number between 21 and 24 then sales end) sales_before4,
			SUM(case when week_number between 25 and 28 then sales end) sales_after4,
			SUM(case when week_number between 13 and 24 then sales end) sales_before12,
			SUM(case when week_number between 25 and 36 then sales end) sales_after12
		from clean_weekly_sales
		group by calendar_year
	)
select calendar_year,
	sales_before4, sales_after4,
	sales_after4 - sales_before4 difference4,
	ROUND(100 * (sales_after4 - sales_before4)/sales_before4,2) percentage4,
	sales_before12, sales_after12,
	sales_after12 - sales_before12 difference12,
	ROUND(100 * (sales_after12 - sales_before12)/sales_before12,2) percentage12
from weeks
order by calendar_year;

--13 Which areas of the business have the highest negative impact in sales metrics performance in 2020 for the 12 week before and after period?
/*	- region
	- platform
	- age_band
	- demographic
	- customer_type */

--region
WITH
	weeks
AS
	(
		select
			region,
			SUM(case when week_number between 13 and 24 then sales end) sales_before,
			SUM(case when week_number between 25 and 36 then sales end) sales_after
		from clean_weekly_sales
		where calendar_year = 2020
		group by region
	)
select *,
	sales_after - sales_before difference,
	ROUND(100 * (sales_after - sales_before)/sales_before,2) percentage
from weeks
order by percentage;

--platform
WITH
	weeks
AS
	(
		select
			platform,
			SUM(case when week_number between 13 and 24 then sales end) sales_before,
			SUM(case when week_number between 25 and 36 then sales end) sales_after
		from clean_weekly_sales
		where calendar_year = 2020
		group by platform
	)
select *,
	sales_after - sales_before difference,
	ROUND(100 * (sales_after - sales_before)/sales_before,2) percentage
from weeks
order by percentage;

--age_band
WITH
	weeks
AS
	(
		select
			age_band,
			SUM(case when week_number between 13 and 24 then sales end) sales_before,
			SUM(case when week_number between 25 and 36 then sales end) sales_after
		from clean_weekly_sales
		where calendar_year = 2020
		group by age_band
	)
select *,
	sales_after - sales_before difference,
	ROUND(100 * (sales_after - sales_before)/sales_before,2) percentage
from weeks
order by percentage;

--demographic
WITH
	weeks
AS
	(
		select
			demographic,
			SUM(case when week_number between 13 and 24 then sales end) sales_before,
			SUM(case when week_number between 25 and 36 then sales end) sales_after
		from clean_weekly_sales
		where calendar_year = 2020
		group by demographic
	)
select *,
	sales_after - sales_before difference,
	ROUND(100 * (sales_after - sales_before)/sales_before,2) percentage
from weeks
order by percentage;

--customer_type
WITH
	weeks
AS
	(
		select
			customer_type,
			SUM(case when week_number between 13 and 24 then sales end) sales_before,
			SUM(case when week_number between 25 and 36 then sales end) sales_after
		from clean_weekly_sales
		where calendar_year = 2020
		group by customer_type
	)
select *,
	sales_after - sales_before difference,
	ROUND(100 * (sales_after - sales_before)/sales_before,2) percentage
from weeks
order by percentage;

--all of the business areas
WITH
	weeks
AS
	(
		select
			region,
			platform,
			age_band,
			demographic,
			customer_type,
			SUM(case when week_number between 13 and 24 then sales end) sales_before,
			SUM(case when week_number between 25 and 36 then sales end) sales_after
		from clean_weekly_sales
		where calendar_year = 2020
		group by region, platform, age_band, demographic, customer_type
	)
select *,
	sales_after - sales_before difference,
	ROUND(100 * (sales_after - sales_before)/sales_before,2) percentage
from weeks
order by percentage;