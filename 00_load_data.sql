/* =====================================================================
   Project : Tech Layoffs - Load raw data into MySQL
   Author  : Thiha
   Output  : layoffs_database.layoffs (raw table, every column TEXT)

   Why LOAD DATA instead of the Table Data Import Wizard?
   The wizard loaded only 1,855 of 4,665 rows without raising an error.
   It skipped rows with blank numeric cells and stopped near the first
   non-ASCII value ('Førde'). LOAD DATA loads every row.

   Before running (MySQL Workbench):
     Manage Connections -> Advanced -> Others: add OPT_LOCAL_INFILE=1,
     then restart Workbench. Otherwise LOAD DATA fails with Error 2068.
   ===================================================================== */

-- Allow the server to accept local files (needs admin privileges)
SET GLOBAL local_infile = 1;

CREATE DATABASE IF NOT EXISTS layoffs_database;
USE layoffs_database;

-- Raw table: every column TEXT so no value is rejected on load.
-- Types are fixed later in 01_data_cleaning.sql.
DROP TABLE IF EXISTS layoffs;

CREATE TABLE layoffs (
    company             TEXT,
    location            TEXT,
    total_laid_off      TEXT,
    `date`              TEXT,
    percentage_laid_off TEXT,
    industry            TEXT,
    source              TEXT,
    stage               TEXT,
    funds_raised        TEXT,
    country             TEXT,
    date_added          TEXT
) DEFAULT CHARSET = utf8mb4;

-- Update the path to where layoffs.csv is saved on your machine
LOAD DATA LOCAL INFILE '/path/to/data/layoffs.csv'
INTO TABLE layoffs
CHARACTER SET utf8mb4                          -- keeps 'Førde', 'Malmö' intact
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'  -- handles "City, Non-U.S."
LINES TERMINATED BY '\n'
IGNORE 1 LINES;                                -- skip the header row

-- Verify the load against the source file
SELECT COUNT(*) AS rows_loaded             -- expect 4,665
FROM layoffs;

SELECT RIGHT(`date`, 4) AS `year`, COUNT(*) AS n
FROM layoffs
GROUP BY `year`
ORDER BY `year`;
-- expect 2020: 635 | 2021: 44 | 2022: 1,231 | 2023: 1,390
--        2024: 634 | 2025: 333 | 2026: 398
