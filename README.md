# Fraud Detection in Banking Transactions Using SQL

A SQL-based fraud detection project that scans 2,512 banking transactions and flags suspicious activity using six rule-based checks. Built with MySQL using self-joins, window functions, views, and aggregate queries.

---

## Table of Contents
1. [Problem Statement](#problem-statement)
2. [Dataset](#dataset)
3. [Tools and Technologies](#tools-and-technologies)
4. [Project Workflow](#project-workflow)
5. [Fraud Rules](#fraud-rules)
6. [Results](#results)
7. [How to Run](#how-to-run)
8. [Repository Structure](#repository-structure)
9. [Limitations and Future Improvements](#limitations-and-future-improvements)

---

## Problem Statement

Banks process thousands of transactions every day. Fraudulent ones are hidden among normal activity, and checking them manually is slow and error-prone. This project builds a structured, repeatable SQL system that automatically flags suspicious transactions so an analyst can review a short list instead of the full dataset.

## Dataset

File: `bank_transactions_data.csv` (2,512 rows, 495 unique accounts, 100 merchants, 43 locations, covering 02 Jan 2023 to 01 Jan 2024).

| Column | Description |
|---|---|
| TransactionID | Unique ID of the transaction |
| AccountID | Customer account that made the transaction |
| TransactionAmount | Amount of money moved |
| TransactionDate | Date and time of the transaction |
| TransactionType | Debit or Credit |
| Location | City where the transaction happened |
| DeviceID / IP Address | Device and network used |
| MerchantID | Merchant involved |
| Channel | ATM, Online, or Branch |
| CustomerAge / CustomerOccupation | Customer details |
| TransactionDuration | Time taken (seconds) |
| LoginAttempts | Login attempts before the transaction |
| AccountBalance | Balance after the transaction |
| PreviousTransactionDate | Date of the account's previous transaction |

## Tools and Technologies

- MySQL 8.0
- SQL concepts: CTE-style subqueries, self-joins, window functions (`COUNT() OVER`, `AVG() OVER`), views, `GROUP BY` / `HAVING`, date arithmetic, `CREATE TABLE AS SELECT`, indexes
- Git and GitHub for version control

## Project Workflow

1. **Setup**: create the database and table with proper data types, primary key, and indexes.
2. **Load**: import the CSV with `LOAD DATA LOCAL INFILE`.
3. **Data quality checks**: missing values, duplicate IDs, invalid amounts, date range, hourly distribution.
4. **Exploration**: transaction counts and average amounts by type and channel.
5. **Fraud rules**: six rules, each saved as a reusable view.
6. **Consolidation**: all flagged records stored in one table, `flagged_transactions`.
7. **Reporting**: flags per rule, percentage flagged, riskiest accounts, and transactions caught by more than one rule.

## Fraud Rules

| # | Rule (view name) | Logic |
|---|---|---|
| 1 | High-value burst (`v_high_value_burst`) | 2 or more transactions by one account within 24 hours with a combined amount of 1,000 or more |
| 2 | Duplicate transactions (`v_duplicate_transactions`) | Same account, amount, merchant, and timestamp repeated |
| 3A | Odd-hour transactions (`v_odd_hour_transactions`) | Transactions between 10 PM and 6 AM |
| 3B | Multiple locations (`v_multi_location`) | One account used in 2 or more different locations within 24 hours |
| 4 | Excessive login attempts (`v_excessive_login_attempts`) | 3 or more login attempts before the transaction |
| 5 | Amount outlier (`v_amount_outlier`) | Amount greater than 3 times the account's own average (accounts with at least 3 transactions) |

Thresholds (24 hours, 1,000, 3 attempts, 3x average) are plain numbers in the SQL and can be tuned.

## Results

| Fraud type | Transactions flagged | Amount flagged |
|---|---|---|
| Excessive login attempts | 95 | 26,250.81 |
| Amount outlier | 62 | 66,303.55 |
| Multiple locations | 49 | 14,611.77 |
| High-value burst | 13 | 5,070.36 |
| Duplicate transactions | 0 | 0 |
| Odd-hour transactions | 0 | 0 |

- **200 unique transactions (7.96% of all)** were flagged.
- **16 transactions** were caught by more than one rule, which makes them the strongest candidates for manual review.
- Accounts `AC00150`, `AC00331`, `AC00418`, and `AC00358` each triggered 4 different rules.

Rules 2 and 3A returned zero rows because this dataset has no exact duplicates and all transactions happen between 4 PM and 7 PM. They are kept as control checks and will fire on data that contains such patterns.

## How to Run

1. Install MySQL 8.0 or later.
2. Place `bank_transactions_data.csv` in the same folder as `fraud_detection.sql`.
3. Run from the command line:
   ```bash
   mysql --local-infile=1 -u root -p < fraud_detection.sql
   ```
   If `LOAD DATA LOCAL INFILE` is blocked, run `SET GLOBAL local_infile = 1;` first, or use the MySQL Workbench Table Data Import Wizard.
4. Query the output table:
   ```sql
   USE fraud_detection;
   SELECT * FROM flagged_transactions;
   ```

## Repository Structure

```
.
├── bank_transactions_data.csv   # Input dataset
├── fraud_detection.sql          # Complete SQL script (setup, checks, rules, reports)
└── README.md                    # Project documentation
```

## Limitations and Future Improvements

- The rules are threshold-based. Thresholds were chosen by looking at this dataset's distribution, not by labelled fraud data, so there is no accuracy score.
- The dataset is a sample and has no confirmed fraud labels. With labels, precision and recall could be measured for each rule.
- Possible next steps: combine rules into a weighted risk score, add a simple Excel dashboard on top of `flagged_transactions`, and schedule the script as a daily job.

## Author

**Rushikesh Avhale**, Pune, Maharashtra
GitHub: [github.com/its-rishi](https://github.com/its-rishi)
