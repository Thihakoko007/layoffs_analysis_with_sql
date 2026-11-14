/* =====================================================================
   Project : Tech Layoffs - Data Cleaning in MySQL
   Author  : Thiha
   Dataset : layoffs.csv (layoffs tracker, 4,665 rows, 2020 - 2026)
   Engine  : MySQL 8.0+ (uses CTEs and window functions)

   Goal
   ----
   Turn the raw import into an analysis-ready table by:
     0. Creating a staging copy (raw data is never modified)
     1. Converting blank strings to real NULLs
     2. Removing duplicate records
     3. Standardizing text and date values
     4. Setting proper column data types
     5. Removing rows with no usable layoff figures
     6. Dropping helper columns

   Note: the CSV was loaded with LOAD DATA LOCAL INFILE into
   `layoffs_database.layoffs`, with every column as TEXT (see README).
   Empty cells arrive as '' instead of NULL, which is why step 1
   comes first.
   ===================================================================== */

USE layoffs_database;


/* ---------------------------------------------------------------------
   0. STAGING TABLE
   Work on a copy so the raw table stays untouched and the whole script
   can be re-run from scratch.
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS layoffs_staging;

CREATE TABLE layoffs_staging LIKE layoffs;   -- copies structure only

INSERT INTO layoffs_staging
SELECT * FROM layoffs;                       -- copies the rows


-- Sanity check: both counts should match (4,665)
SELECT
    (SELECT COUNT(*) FROM layoffs)         AS raw_rows,
    (SELECT COUNT(*) FROM layoffs_staging) AS staging_rows;


/* ---------------------------------------------------------------------
   1. BLANKS -> NULL
   COUNT(col) returned the full row count for every column, so the empty
   cells are '' rather than NULL. Fix all columns in one pass:
     TRIM()    strips leading/trailing spaces (also cleans 16 company
               names such as 'WeWork ')
     NULLIF()  turns the resulting '' into NULL
   --------------------------------------------------------------------- */
UPDATE layoffs_staging
SET company             = NULLIF(TRIM(company), ''),
    location            = NULLIF(TRIM(location), ''),
    total_laid_off      = NULLIF(TRIM(total_laid_off), ''),
    `date`              = NULLIF(TRIM(`date`), ''),
    percentage_laid_off = NULLIF(TRIM(percentage_laid_off), ''),
    industry            = NULLIF(TRIM(industry), ''),
    source              = NULLIF(TRIM(source), ''),
    stage               = NULLIF(TRIM(stage), ''),
    funds_raised        = NULLIF(TRIM(funds_raised), ''),
    country             = NULLIF(TRIM(country), ''),
    date_added          = NULLIF(TRIM(date_added), '');

-- Non-null count per column (COUNT skips NULLs)
SELECT
    COUNT(*)                   AS total_rows,
    COUNT(company)             AS company,
    COUNT(location)            AS location,
    COUNT(total_laid_off)      AS total_laid_off,
    COUNT(percentage_laid_off) AS percentage_laid_off,
    COUNT(industry)            AS industry,
    COUNT(stage)               AS stage,
    COUNT(funds_raised)        AS funds_raised,
    COUNT(country)             AS country
FROM layoffs_staging;


/* ---------------------------------------------------------------------
   2. DUPLICATES
   A duplicate = the same layoff event recorded twice. `source` (article
   URL) and `date_added` are excluded from the comparison because the
   same event is often logged from two different articles on different
   days. Including them would hide real duplicates.
   --------------------------------------------------------------------- */

-- 2a. Inspect: every row in a duplicate group, side by side
WITH dup_groups AS (
    SELECT *,
           COUNT(*) OVER (
               PARTITION BY company, location, industry, total_laid_off,
                            percentage_laid_off, `date`, stage,
                            funds_raised, country
           ) AS group_size
    FROM layoffs_staging
)
SELECT *
FROM dup_groups
WHERE group_size > 1
ORDER BY company, `date`;

-- 2b. Delete: keep the earliest-loaded row (lowest date_added) of each group.
-- MySQL can't DELETE from a CTE directly, so create a new table.


WITH duplicate_cte AS(
SELECT *, 
ROW_NUMBER() OVER(PARTITION BY company, location, industry, total_laid_off,
                            percentage_laid_off, `date`, stage,
                            funds_raised, country ORDER BY date_added) as ranking 
FROM layoffs_staging)

SELECT *
FROM duplicate_cte
WHERE ranking > 1;


CREATE TABLE `layoffs_staging2` (
  `company` text,
  `location` text,
  `total_laid_off` text,
  `date` text,
  `percentage_laid_off` text,
  `industry` text,
  `source` text,
  `stage` text,
  `funds_raised` text,
  `country` text,
  `date_added` text,
  `ranking` int
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO layoffs_staging2
SELECT *, 
ROW_NUMBER() OVER(PARTITION BY company, location, industry, total_laid_off,
                            percentage_laid_off, `date`, stage,
                            funds_raised, country ORDER BY date_added) as ranking 
FROM layoffs_staging;


-- Remove duplicated records
DELETE
FROM layoffs_staging2
WHERE ranking > 1;

SELECT *
FROM layoffs_staging2
WHERE ranking > 1;

-- Remove ranking column because it is no longer needed
Alter Table layoffs_staging2
DROP COLUMN ranking;

SELECT *
FROM layoffs_staging2;

/* ---------------------------------------------------------------------
   3. STANDARDIZATION
   --------------------------------------------------------------------- */

-- 3a. Category columns: check for spelling variants
--     (e.g. 'Crypto' vs 'Crypto Currency', 'United States.').

SELECT DISTINCT country 
FROM layoffs_staging2
ORDER BY country;

SELECT DISTINCT industry
FROM layoffs_staging2;

SELECT DISTINCT stage
FROM layoffs_staging2
ORDER BY stage;


--     Update UAE as United Arab Emirates
UPDATE layoffs_staging2
SET country = 'United Arab Emirates'
WHERE country = 'UAE';

SELECT DISTINCT country 
FROM layoffs_staging2
ORDER BY country;

-- 3b. Location: non-US cities carry a ', Non-U.S.' suffix
--     ('London, Non-U.S.'). The country column already covers this,
--     so strip the suffix to keep a clean city name.
SELECT DISTINCT location
FROM layoffs_staging2;

SELECT location, REPLACE(location, ', Non-U.S.', '') AS cleaned
FROM layoffs_staging2
WHERE location LIKE '%Non-U.S.%';


UPDATE layoffs_staging2
SET location = REPLACE(location, ', Non-U.S.', '')
WHERE location LIKE '%, Non-U.S.';

UPDATE layoffs_staging2
SET location = REPLACE(location, 'New Delhi, New York City', 'New York City')
WHERE location = 'Luxembourg, Raleigh';
WHERE location LIKE 'New Delhi, New York City';

SELECT DISTINCT location
FROM layoffs_staging2
ORDER BY location;

Start Transaction;
UPDATE layoffs_staging2
SET location = CASE 
				WHEN location = 'New Delhi, New York City' THEN 'New York City'
				WHEN location = 'Luxembourg, Raleigh' THEN 'Luxembourg'
                WHEN location = 'Melbourne, Victoria' THEN 'Melbourne'
				END 
WHERE location IN ('New Delhi, New York City','Luxembourg, Raleigh','Melbourne, Victoria');

SELECT DISTINCT location
FROM layoffs_staging2
ORDER BY location;

commit;

-- A few rows hold only 'Non-U.S.' with no city -> unknown city
SELECT *
FROM layoffs_staging2
WHERE location = 'Non-U.S.';

Start Transaction;
UPDATE layoffs_staging2
SET location = NULL
WHERE location = 'Non-U.S.';

commit;

SELECT *
FROM layoffs_staging2
WHERE location is NULL;


-- 3c. Dates: text 'M/D/YYYY' -> 'YYYY-MM-DD'
--     Preview first: any row returned here would fail to parse.
SELECT `date`, date_added
FROM layoffs_staging2
WHERE (`date` IS NOT NULL AND STR_TO_DATE(`date`, '%m/%d/%Y') IS NULL)
   OR (date_added IS NOT NULL AND STR_TO_DATE(date_added, '%m/%d/%Y') IS NULL);

Start Transaction;
UPDATE layoffs_staging2
SET `date`     = STR_TO_DATE(`date`, '%m/%d/%Y'),
    date_added = STR_TO_DATE(date_added, '%m/%d/%Y');

SELECT *
FROM layoffs_Staging2;

commit;


/* ---------------------------------------------------------------------
   4. DATA TYPES
   UPDATE only changes values; the column type stays TEXT until ALTERed.
   Proper types make sorting, date functions and aggregation correct
   (TEXT sorts '9' after '10') and let MySQL index the columns.
   One ALTER statement = one table rebuild instead of several.
   --------------------------------------------------------------------- */
ALTER TABLE layoffs_staging2
    MODIFY company             VARCHAR(255),
    MODIFY location            VARCHAR(255),
    MODIFY total_laid_off      INT,
    MODIFY `date`              DATE,
    MODIFY percentage_laid_off DECIMAL(3,2),    -- 0.00 to 1.00
    MODIFY industry            VARCHAR(100),
    MODIFY stage               VARCHAR(50),
    MODIFY funds_raised        DECIMAL(12,2),   -- USD millions
    MODIFY country             VARCHAR(100),
    MODIFY date_added          DATE;

/* ---------------------------------------------------------------------
   5. UNUSABLE ROWS
   Rows missing BOTH total_laid_off and percentage_laid_off say nothing
   about the size of a layoff, so they are removed.
   Rows missing only ONE of the two are kept: they still count toward
   totals or percentage analysis. (Using OR here would wrongly delete
   over half the dataset.)
   --------------------------------------------------------------------- */
SELECT COUNT(*) AS rows_to_delete
FROM layoffs_staging2
WHERE total_laid_off IS NULL
  AND percentage_laid_off IS NULL;

DELETE FROM layoffs_staging2
WHERE total_laid_off IS NULL
  AND percentage_laid_off IS NULL;

-- Remaining nulls that can't be filled reliably:
--   industry (Eyeo, Appsmith) and country (Fit Analytics, Ludia) are
--   missing, and each company appears only once, so there is no other
--   row of the same company to copy the value from. Left as NULL.
SELECT *
FROM layoffs_staging
WHERE industry IS NULL OR country IS NULL;
   --------------------------------------------------------------------- */
