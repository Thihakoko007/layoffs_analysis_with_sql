/* =====================================================================
   Project : Tech Layoffs - Exploratory Data Analysis in MySQL
   Questions explored
   ------------------
     1. Overview: date range, biggest single layoffs, full shutdowns
     2. Who: which companies cut the most jobs
     3. Where & what: by industry, country and funding stage
     4. When: layoffs by year, by month, and a yearly running total
     5. Top 5 companies by layoffs in each year

   Notes
   -----
   - total_laid_off is NULL for rows that only report a percentage.
     SUM() ignores NULLs, so totals reflect reported headcounts only.
   - Category NULLs (industry, country, stage) are labelled 'Unknown'
     with COALESCE so they show up as a group instead of a blank row.
   ===================================================================== */

USE layoffs_database;

/* ---------------------------------------------------------------------
   1. OVERVIEW
   --------------------------------------------------------------------- */

-- Preview the data (LIMIT avoids pulling the whole table)
SELECT *
FROM layoffs_staging2
LIMIT 20;

-- Time span covered by the dataset
SELECT MIN(`date`) AS first_layoff,
       MAX(`date`) AS last_layoff
FROM layoffs_staging2;

-- Largest single layoff event and highest share of staff cut
SELECT MAX(total_laid_off)      AS max_laid_off,
       MAX(percentage_laid_off) AS max_pct_laid_off
FROM layoffs_staging2;

-- Which event(s) had the largest single layoff?
-- A subquery (not LIMIT 1) so ties are all returned.
SELECT *
FROM layoffs_staging2
WHERE total_laid_off = (SELECT MAX(total_laid_off) FROM layoffs_staging2);


-- Companies that laid off 100% of staff (i.e. shut down),
-- largest first, then by how much funding they had raised
SELECT company, location, country, industry, stage,
       `date`, total_laid_off, funds_raised
FROM layoffs_staging2
WHERE percentage_laid_off = 1
ORDER BY total_laid_off DESC, funds_raised DESC;

/* ---------------------------------------------------------------------
   2. COMPANIES
   --------------------------------------------------------------------- */

-- Top 10 companies by total layoffs across all years
SELECT company,
       SUM(total_laid_off) AS total_laid_off_sum,
       COUNT(*)            AS layoff_events
FROM layoffs_staging2
GROUP BY company
ORDER BY total_laid_off_sum DESC
LIMIT 10;


/* ---------------------------------------------------------------------
   3. INDUSTRY, COUNTRY, STAGE
   --------------------------------------------------------------------- */

-- By industry
SELECT COALESCE(industry, 'Unknown') AS industry,
       SUM(total_laid_off)           AS total_laid_off_sum
FROM layoffs_staging2
GROUP BY COALESCE(industry, 'Unknown')
ORDER BY total_laid_off_sum DESC;

-- By country (top 10)
SELECT COALESCE(country, 'Unknown') AS country,
       SUM(total_laid_off)          AS total_laid_off_sum
FROM layoffs_staging2
GROUP BY COALESCE(country, 'Unknown')
ORDER BY total_laid_off_sum DESC
LIMIT 10;

-- By company funding stage
SELECT COALESCE(stage, 'Unknown') AS stage,
       SUM(total_laid_off)        AS total_laid_off_sum
FROM layoffs_staging2
GROUP BY COALESCE(stage, 'Unknown')
ORDER BY total_laid_off_sum DESC;


/* ---------------------------------------------------------------------
   4. TRENDS OVER TIME
   `date` is a DATE column, so date functions (YEAR, DATE_FORMAT) are
   used instead of SUBSTRING on text.
   --------------------------------------------------------------------- */

-- By year
SELECT YEAR(`date`)        AS `year`,
       SUM(total_laid_off) AS total_laid_off_sum
FROM layoffs_staging2
WHERE `date` IS NOT NULL
GROUP BY YEAR(`date`) 
ORDER BY `year` DESC;

-- By month, with a running total that restarts every year
--   PARTITION BY year  -> resets the total each January
--   ORDER BY month     -> accumulates month by month within the year
WITH monthly AS (
    SELECT YEAR(`date`)                 AS `year`,
           DATE_FORMAT(`date`, '%Y-%m') AS `month`,
           SUM(total_laid_off)          AS total_laid_off_sum
    FROM layoffs_staging2
    WHERE `date` IS NOT NULL
    GROUP BY YEAR(`date`), DATE_FORMAT(`date`, '%Y-%m')
)
SELECT `year`,
       `month`,
       total_laid_off_sum,
       SUM(total_laid_off_sum) OVER (
           PARTITION BY `year`
           ORDER BY `month`
       ) AS running_total_ytd
FROM monthly
ORDER BY `year`, `month`;

/* ---------------------------------------------------------------------
   5. TOP 5 COMPANIES PER YEAR
   Window results can't be filtered in the same SELECT (WHERE runs
   before window functions), so the rank is computed in a second CTE
   and filtered in the outer query.
   DENSE_RANK: tied companies share a rank, so a year may show more
   than 5 rows. Swap to ROW_NUMBER() for exactly 5.
   --------------------------------------------------------------------- */
WITH year_company AS (
    SELECT YEAR(`date`) AS `year`,
           company,
           SUM(total_laid_off) AS total_laid_off_sum
    FROM layoffs_staging2
    WHERE `date` IS NOT NULL
    GROUP BY YEAR(`date`), company
),
year_company_rank AS (
    SELECT *,
           DENSE_RANK() OVER (
               PARTITION BY `year`
               ORDER BY total_laid_off_sum DESC
           ) AS ranking
    FROM year_company
    WHERE total_laid_off_sum IS NOT NULL
)
SELECT `year`, ranking, company, total_laid_off_sum
FROM year_company_rank
WHERE ranking <= 5
ORDER BY `year` DESC, ranking;
