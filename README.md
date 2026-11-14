# Tech Layoffs Analysis (2020–2026) 

An end-to-end SQL project: cleaning a raw dataset of global tech layoffs and exploring it to find which companies, industries, countries and periods were hit hardest.

**Skills:** data cleaning, CTEs, window functions (`ROW_NUMBER`, `DENSE_RANK`, running totals), aggregation, date handling

---

## Dataset

|  |  |
| :---- | :---- |
| File | [`layoffs.csv`](https://www.kaggle.com/datasets/swaptr/layoffs-2022) |
| Rows | 4,665 layoff events |
| Period | March 2020 – November 2026 |
| Columns | `company`, `location`, `total_laid_off`, `date`, `percentage_laid_off`, `industry`, `source`, `stage`, `funds_raised`, `country`, `date_added` |

Each row is one layoff announcement. `funds_raised` is in USD millions and `percentage_laid_off` is a share of the workforce (0–1).

**Source:** [Layoffs Dataset on Kaggle](https://www.kaggle.com/datasets/swaptr/layoffs-2022), compiled from tech layoffs reported by Bloomberg, San Francisco Business Times, TechCrunch and The New York Times. The underlying data comes from [Layoffs.fyi](https://layoffs.fyi/) (credit: Roger Lee).

**Context:** Starting in 2022, tech firms began cutting staff as consumer spending slowed, interest rates rose and the dollar strengthened. Meta's cut of more than 11,000 employees (13% of its workforce) is one example. This project looks at how that wave unfolded, and where it hit hardest, from the COVID period to today.

---

## How to run

1. Create the schema and an all-`TEXT` raw table:

```sql
CREATE DATABASE layoffs_database;
USE layoffs_database;

CREATE TABLE layoffs (
  company TEXT, location TEXT, total_laid_off TEXT, `date` TEXT,
  percentage_laid_off TEXT, industry TEXT, source TEXT, stage TEXT,
  funds_raised TEXT, country TEXT, date_added TEXT
) DEFAULT CHARSET = utf8mb4;
```

2. Load the CSV with `LOAD DATA`:

```sql
LOAD DATA LOCAL INFILE '/path/to/data/layoffs.csv'
INTO TABLE layoffs
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

SELECT COUNT(*) FROM layoffs;   -- expect 4,665
```

   In MySQL Workbench, add `OPT_LOCAL_INFILE=1` under **Manage Connections → Advanced → Others** and restart Workbench, or you'll get Error 2068\.

   

3. Run `sql/01_data_cleaning.sql` top to bottom. It builds `layoffs_staging` and leaves the raw table untouched.  
4. Run `sql/02_eda.sql`.

>   
> **Why not the Table Data Import Wizard?** On the first attempts it loaded only 1,603 and then 1,855 of the 4,665 rows, and it didn't raise an error either time. It skipped rows with blank numeric cells, and it stopped near the first non-ASCII value (`Førde`). I caught this by comparing `COUNT(*)` against the source file and switched to `LOAD DATA`.

---

## Data cleaning

| Step | Problem found | Fix |
| :---- | :---- | :---- |
| Staging | Cleaning raw data directly is risky | Copied into `layoffs_staging`, added a temporary `row_id` key |
| Blanks | Import stored empty cells as `''`, so `IS NULL` and `COUNT()` didn't work | `NULLIF(TRIM(col), '')` on every column in a single `UPDATE` |
| Whitespace | 16 company names with trailing spaces (`'WeWork '`) | `TRIM()` in the same pass |
| Duplicates | The same event logged twice from different articles | `ROW_NUMBER()` partitioned by every column except `source` and `date_added`; deleted 2 rows |
| Location | City names carried a redundant `", Non-U.S."` suffix | Stripped the suffix; rows with no city set to `NULL` |
| Dates | `date` and `date_added` stored as text (`11/6/2026`) | `STR_TO_DATE(..., '%m/%d/%Y')`, then changed the type to `DATE` |
| Data types | Every column was `TEXT` | One `ALTER TABLE` to `INT`, `DECIMAL`, `DATE`, `VARCHAR`
| Unusable rows | 759 rows had neither `total_laid_off` nor `percentage_laid_off` | Deleted. Rows missing only one of the two were kept |

**Result:** 4,665 → **3,904** analysis-ready rows.

**Known issues (left in place on purpose):**

- 4 rows are missing `industry` or `country`. Each of these companies appears only once, so there's no other row to fill the value from.  
- A few events have conflicting values across rows. For example, FNZ on 2023-07-06 has two rows that differ only in `funds_raised`. These aren't exact duplicates, so they weren't removed automatically.

---

## Key findings

> Totals count only rows that report a headcount. Rows with only a percentage aren't included in the sums.  
> 

- **\~945,000 layoffs were recorded** across 3,904 events.  
- **2023 was the peak year** with \~266,000 layoffs. **January 2023 alone** accounted for \~90,000, the worst month in the dataset.  
- After a quiet 2021 (\~16,000), layoffs jumped tenfold in 2022 and **haven't returned to pre-2022 levels** (\~143,000 in 2026 so far).  
- **Big Tech dominates:** Amazon (\~60K), Intel (\~43K), Meta (\~36K) and Microsoft (\~35K) are the top four companies. **Intel's April 2025 cut of 22,000** is the largest single event.  
- **Post-IPO companies account for \~63%** of all layoffs, so the cuts were driven by large public companies, not struggling startups.  
- **The United States accounts for \~71%** of recorded layoffs, followed by India (\~68K).  
- **380 companies laid off 100% of staff**, i.e. shut down. The best-funded was Britishvolt, which had raised \$2.4B before collapsing in January 2023\.  
- **Industry caveat:** "Other" is the largest single industry (\~117K), ahead of Retail and Hardware. The industry labels are too broad to rank sectors reliably.

---

## SQL techniques used

- **CTEs** to break multi-step logic into readable stages  
- **`ROW_NUMBER()`** to find duplicates, deleted through a join because MySQL can't `DELETE` from a CTE  
- **`DENSE_RANK()` with `PARTITION BY`** for the top 5 companies per year  
- **Running totals:** `SUM() OVER (PARTITION BY year ORDER BY month)` resets each year  
- **`NULLIF` / `TRIM` / `COALESCE`** for null and blank handling  
- **`STR_TO_DATE`, `YEAR`, `DATE_FORMAT`** for date conversion and grouping  
- Preview `SELECT` before every destructive `UPDATE`/`DELETE`

---

