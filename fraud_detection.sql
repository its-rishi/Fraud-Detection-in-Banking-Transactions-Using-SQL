/* =====================================================================
   PROJECT : Fraud Detection in Banking Transactions using SQL
   DATABASE: MySQL 8.0+
   DATASET : bank_transactions_data.csv  (2,512 transactions, 495 accounts)
   AUTHOR  : Rushikesh Avhale

   WHAT THIS SCRIPT DOES
     1. Creates the database and table (with proper data types + indexes)
     2. Loads the CSV file
     3. Runs data-quality checks (missing values, duplicate IDs, bad amounts)
     4. Explores the data (summary by type / channel)
     5. Defines 6 fraud rules as reusable VIEWS
     6. Combines all flagged records into one table: flagged_transactions
     7. Produces summary reports (flags per rule, riskiest accounts)

   HOW TO RUN
     mysql --local-infile=1 -u root -p < fraud_detection.sql
     (Edit the file path in STEP 2 if your CSV is in a different folder.)
   ===================================================================== */


/* =====================================================================
   STEP 1 : DATABASE AND TABLE SETUP
   ===================================================================== */
create database if not exists fraud_detection;
use fraud_detection;

drop table if exists bank_transactions;

create table bank_transactions (
    transaction_id            varchar(10)    primary key,
    account_id                varchar(10)    not null,
    transaction_amount        decimal(10,2)  not null,
    transaction_date          datetime       not null,
    transaction_type          varchar(10)    not null,   -- Debit / Credit
    location                  varchar(50),
    device_id                 varchar(10),
    ip_address                varchar(20),
    merchant_id               varchar(10),
    channel                   varchar(10),               -- ATM / Online / Branch
    customer_age              int,
    customer_occupation       varchar(30),
    transaction_duration      int,                       -- seconds
    login_attempts            int,
    account_balance           decimal(12,2),
    previous_transaction_date datetime
);

-- Indexes make the "same account within a time window" queries much faster
create index idx_account_date on bank_transactions (account_id, transaction_date);
create index idx_merchant     on bank_transactions (merchant_id);


/* =====================================================================
   STEP 2 : LOAD THE CSV FILE
   ===================================================================== */
load data local infile 'bank_transactions_data.csv'
into table bank_transactions
fields terminated by ',' optionally enclosed by '"'
lines terminated by '\n'
ignore 1 lines;

select count(*) as total_rows_loaded from bank_transactions;


/* =====================================================================
   STEP 3 : DATA QUALITY CHECKS
   ===================================================================== */

-- 3.1 Missing values in every important column
select
    sum(transaction_id     is null) as missing_transaction_id,
    sum(account_id         is null) as missing_account_id,
    sum(transaction_amount is null) as missing_amount,
    sum(transaction_date   is null) as missing_date,
    sum(transaction_type   is null) as missing_type,
    sum(location           is null) as missing_location,
    sum(merchant_id        is null) as missing_merchant
from bank_transactions;

-- 3.2 Duplicate transaction IDs (should return no rows)
select transaction_id, count(*) as times_seen
from bank_transactions
group by transaction_id
having count(*) > 1;

-- 3.3 Invalid amounts (zero or negative; should return no rows)
select transaction_id, transaction_amount
from bank_transactions
where transaction_amount <= 0;

-- 3.4 Date range and size of the data
select min(transaction_date)          as first_transaction,
       max(transaction_date)          as last_transaction,
       count(distinct account_id)     as unique_accounts,
       count(distinct merchant_id)    as unique_merchants,
       count(distinct location)       as unique_locations
from bank_transactions;

-- 3.5 At which hours do transactions happen? (helps us design the odd-hour rule)
select hour(transaction_date) as tx_hour, count(*) as total_transactions
from bank_transactions
group by hour(transaction_date)
order by tx_hour;


/* =====================================================================
   STEP 4 : EXPLORATORY ANALYSIS
   ===================================================================== */

-- 4.1 Transactions by type (Debit / Credit)
select transaction_type,
       count(*)                           as total_transactions,
       round(avg(transaction_amount), 2)  as avg_amount,
       max(transaction_amount)            as max_amount
from bank_transactions
group by transaction_type;

-- 4.2 Transactions by channel (ATM / Online / Branch)
select channel,
       count(*)                           as total_transactions,
       round(avg(transaction_amount), 2)  as avg_amount
from bank_transactions
group by channel
order by total_transactions desc;


/* =====================================================================
   STEP 5 : FRAUD RULES (each rule is saved as a VIEW so it can be reused)
   ===================================================================== */

/* ---------------------------------------------------------------------
   RULE 1 : HIGH-VALUE BURST
   An account makes 2 or more transactions within 24 hours AND the total
   amount in that window is 1000 or more.
   --------------------------------------------------------------------- */
create or replace view v_high_value_burst as
select t1.transaction_id,
       t1.account_id,
       t1.transaction_date,
       t1.transaction_amount,
       count(*)                   as tx_in_last_24h,
       sum(t2.transaction_amount) as total_in_last_24h
from bank_transactions t1
join bank_transactions t2
  on  t2.account_id = t1.account_id
  and t2.transaction_date between t1.transaction_date - interval 24 hour
                              and t1.transaction_date
group by t1.transaction_id, t1.account_id, t1.transaction_date, t1.transaction_amount
having count(*) >= 2
   and sum(t2.transaction_amount) >= 1000;


/* ---------------------------------------------------------------------
   RULE 2 : DUPLICATE TRANSACTIONS
   Same account + same amount + same merchant + same timestamp appearing
   more than once.
   --------------------------------------------------------------------- */
create or replace view v_duplicate_transactions as
select transaction_id, account_id, transaction_date, transaction_amount,
       merchant_id, duplicate_count
from (
    select transaction_id, account_id, transaction_date, transaction_amount,
           merchant_id,
           count(*) over (partition by account_id, transaction_amount,
                                       merchant_id, transaction_date) as duplicate_count
    from bank_transactions
) d
where duplicate_count > 1;


/* ---------------------------------------------------------------------
   RULE 3A : ODD-HOUR TRANSACTIONS
   Transactions made late at night or very early morning
   (10 PM to 6 AM).
   --------------------------------------------------------------------- */
create or replace view v_odd_hour_transactions as
select transaction_id, account_id, transaction_date, transaction_amount,
       hour(transaction_date) as tx_hour
from bank_transactions
where hour(transaction_date) < 6
   or hour(transaction_date) >= 22;


/* ---------------------------------------------------------------------
   RULE 3B : MULTIPLE LOCATIONS IN 24 HOURS
   The same account is used from 2 or more different locations within
   24 hours (a person cannot normally be in two cities that fast).
   --------------------------------------------------------------------- */
create or replace view v_multi_location as
select t1.transaction_id,
       t1.account_id,
       t1.transaction_date,
       t1.transaction_amount,
       count(distinct t2.location) as locations_in_last_24h
from bank_transactions t1
join bank_transactions t2
  on  t2.account_id = t1.account_id
  and t2.transaction_date between t1.transaction_date - interval 24 hour
                              and t1.transaction_date
group by t1.transaction_id, t1.account_id, t1.transaction_date, t1.transaction_amount
having count(distinct t2.location) >= 2;


/* ---------------------------------------------------------------------
   RULE 4 : EXCESSIVE LOGIN ATTEMPTS
   3 or more login attempts before the transaction can indicate
   password guessing.
   --------------------------------------------------------------------- */
create or replace view v_excessive_login_attempts as
select transaction_id, account_id, transaction_date, transaction_amount,
       login_attempts
from bank_transactions
where login_attempts >= 3;


/* ---------------------------------------------------------------------
   RULE 5 : AMOUNT OUTLIER
   A transaction that is more than 3 times the account's own average
   amount (only for accounts with at least 3 transactions).
   --------------------------------------------------------------------- */
create or replace view v_amount_outlier as
select transaction_id, account_id, transaction_date, transaction_amount,
       round(account_avg_amount, 2) as account_avg_amount
from (
    select transaction_id, account_id, transaction_date, transaction_amount,
           avg(transaction_amount) over (partition by account_id) as account_avg_amount,
           count(*)                over (partition by account_id) as account_tx_count
    from bank_transactions
) a
where account_tx_count >= 3
  and transaction_amount > 3 * account_avg_amount;


/* Look at the result of each rule */
select 'high_value_burst'         as rule_name, count(*) as flagged_rows from v_high_value_burst
union all
select 'duplicate',               count(*) from v_duplicate_transactions
union all
select 'odd_hour',                count(*) from v_odd_hour_transactions
union all
select 'multi_location',          count(*) from v_multi_location
union all
select 'excessive_login_attempts', count(*) from v_excessive_login_attempts
union all
select 'amount_outlier',          count(*) from v_amount_outlier;


/* =====================================================================
   STEP 6 : STORE ALL FLAGGED TRANSACTIONS IN ONE TABLE
   ===================================================================== */
drop table if exists flagged_transactions;

create table flagged_transactions as
select transaction_id, account_id, transaction_date, transaction_amount,
       'high_value_burst' as fraud_type
from v_high_value_burst
union all
select transaction_id, account_id, transaction_date, transaction_amount,
       'duplicate'
from v_duplicate_transactions
union all
select transaction_id, account_id, transaction_date, transaction_amount,
       'odd_hour'
from v_odd_hour_transactions
union all
select transaction_id, account_id, transaction_date, transaction_amount,
       'multi_location'
from v_multi_location
union all
select transaction_id, account_id, transaction_date, transaction_amount,
       'excessive_login_attempts'
from v_excessive_login_attempts
union all
select transaction_id, account_id, transaction_date, transaction_amount,
       'amount_outlier'
from v_amount_outlier;

select * from flagged_transactions order by transaction_date;


/* =====================================================================
   STEP 7 : SUMMARY REPORTS
   ===================================================================== */

-- 7.1 How many flags and how much money per fraud type?
select fraud_type,
       count(*)                  as flagged_transactions,
       round(sum(transaction_amount), 2) as total_amount_flagged
from flagged_transactions
group by fraud_type
order by flagged_transactions desc;

-- 7.2 What percentage of all transactions were flagged?
select count(distinct f.transaction_id)                                  as unique_flagged,
       (select count(*) from bank_transactions)                          as total_transactions,
       round(100 * count(distinct f.transaction_id)
             / (select count(*) from bank_transactions), 2)              as flagged_percentage
from flagged_transactions f;

-- 7.3 Riskiest accounts: accounts that triggered the MOST DIFFERENT rules
select account_id,
       count(distinct fraud_type)        as different_rules_triggered,
       count(*)                          as total_flags,
       round(sum(transaction_amount), 2) as total_amount_involved
from flagged_transactions
group by account_id
order by different_rules_triggered desc, total_flags desc
limit 10;

-- 7.4 Transactions caught by MORE THAN ONE rule (strongest suspects)
select transaction_id, account_id, transaction_amount,
       count(distinct fraud_type)                   as rules_triggered,
       group_concat(distinct fraud_type order by fraud_type) as which_rules
from flagged_transactions
group by transaction_id, account_id, transaction_amount
having count(distinct fraud_type) > 1
order by rules_triggered desc, transaction_amount desc;
