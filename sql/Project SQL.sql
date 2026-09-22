/*project*/
create database project1;
use project1;
SELECT customer_id,Loan_type,sanction_amount from loan;
SELECT Loan_ID,Customer_ID,Loan_Type,Sanction_Amount from loan;
/*Loan with respect to product*/
SELECT Loan_Type,SUM(Sanction_Amount) AS Loan_Exposure
from loan
GROUP BY Loan_Type

UNION ALL
SELECT 
'TOTAL' AS Loan_Type ,
SUM(Sanction_Amount) AS Loan_Exposure
from loan;

#credit-income 
select a.*,
b.Credit_score,
Case 
When b.Credit_score >= 750 Then "Low risk"
When b.Credit_score >= 651 Then "Medium risk"
Else "High Risk"
End as Credit_risk_segment
from income_data a 
join credit_data b on a.Customer_ID=b.Customer_ID
order by Customer_ID;


#Borrower risk profile
SELECT a.*,
b.Income,
b.Credit_score
from loan_updated1 a 
LEFT JOIN income_credit_score b
on a.Customer_ID =  b.Customer_ID
order by Loan_ID;

 
/* customer-level Table*/
Select a.*,
b.City
from income_credit_score a
left join customer b 
ON a.Customer_ID = b.Customer_ID
AND a.Credit_score = b.Customer_ID
order by Customer_ID;

with customer_exposure AS (
select 
Customer_ID,
Monthly_income,
round(sum(EMI),2) AS Total_Emi
from loan_risk 
group by Customer_ID, Monthly_income
)
Select 
a.*,
b.Monthly_income,
b.Total_Emi,
round((b.Total_Emi / b.Monthly_income),2) AS emi_burden_cust
From customer_level a 
LEFT JOIN customer_exposure b 
ON a.Customer_ID = b.Customer_ID
order by Customer_ID;

update customer_level
set Monthly_income = round(Income/12,2)
where Monthly_income is null or Monthly_income='';

/*Cleaning*/
select distinct Loan_status 
from loan;

update loan
set loan_status='unknown'
where loan_status is null or loan_status='';

update loan 
set loan_status=LOWER(loan_status);

#DTI and LTI
WITH Income_summary AS (
  SELECT 
  *,
  round(Income/12,2) AS Monthly_Income
  FROM borrower_risk
),
Total_exposure AS (
  SELECT
  Customer_ID,
  round(SUM(Sanction_amount),2) AS Total_loan_amount,
  round(SUM(EMI),2) AS Total_loan_payment
  FROM loan_updated1
  GROUP BY Customer_ID
)
SELECT
a.*,
round((b.Total_loan_payment / a.Monthly_income)*100,2) AS DTI,
round(b.Total_loan_amount / a.Income,2) AS LTI,
round((a.EMI * a.Tenure_Months)/a.Income,2) AS Emi_burden,
round((a.Interest_Rate * a.Sanction_Amount)/a.Income,2) AS Interest_burden,
CASE
When a.Credit_score >= 700 Then "Low Risk"
When a.Credit_score >= 600 Then "Medium Risk"
Else "High Risk"
End as Credit_risk
FROM Income_summary a 
LEFT JOIN Total_exposure b ON a.Customer_ID = b.Customer_ID
order by Customer_ID ;


#customer segment based on credit profile
WITH latest_score AS (
  SELECT 
  Customer_ID,
  Credit_score,
  From customer
  GROUP BY Customer_ID
),
branch_count AS (
  SELECT 
  Customer_ID,
  Branch,
  count(*) AS txn_count
  FROM transactn1
  GROUP BY Customer_ID,Branch
),
ranked_branch AS (
  SELECT 
  Customer_ID,
  Branch,
  txn_count,
  ROW_NUMBER() OVER (PARTITION BY Customer_ID ORDER BY txn_count DESC ) AS rn
  FROM branch_count
)
SELECT 
a.Customer_ID,
a.Credit_score,
b.Branch,
CASE
  WHEN Credit_score IS NULL then 'Unknown'
  WHEN Credit_score >= 750 then 'Low risk' 
  WHEN credit_score >= 650 then 'Medium risk'
else 'High Risk' 
END AS Risk_segment
FROM latest_score a 
LEFT JOIN ranked_branch b ON a.customer_id = b.customer_id
WHERE rn=1
ORDER BY a.customer_id;

#Credit score - transaction table
SELECT
a.customer_id,
a.risk_segment,
a.branch,
b.transaction_type,
b.transaction_date,
b.status,
b.amount_in_inr
from credit_risk_branch a 
LEFT JOIN transactn1 b 
ON a.customer_id=b.customer_id
order by customer_id;

#DTI Bucket
SELECT *,
CASE
WHEN DTI >100 THEN 'Very High'
WHEN DTI >60 THEN 'High'
WHEN DTI >30 THEN 'Moderate'
ELSE 'Low'
END AS DTI_Risk
FROM dti 
order by customer_id;

#txn counts per credit risk segments
SELECT 
risk_segment,
DATE_FORMAT(transaction_date,'%Y-%m') AS month,
COUNT(*) AS txn_count,
SUM(CASE WHEN status='SUCCESS' THEN 1 ELSE 0 END) AS success_txn,
SUM(CASE WHEN status='FAILED' THEN 1 ELSE 0 END) AS failed_txn,
SUM(CASE WHEN status='PENDING' THEN 1 ELSE 0 END) AS pending_txn
FROM credit_transactn
GROUP BY risk_segment,month
ORDER BY month;

#loan_txn table
SELECT a.*,
b.transaction_type,
b.transaction_date,
b.amount_in_inr,
b.status
FROM loan_updated1 a 
LEFT JOIN transactn1 b ON a.customer_id=b.customer_id
order by a.customer_id;

#High risk flag
Select 
a.Customer_ID,
a.Credit_score,
a.Branch,
b.DTI,
b.LTI
FROM credit_risk_branch a 
left join dti b on a.Customer_ID = b.Customer_ID
order by Customer_ID;

update risk_segment
set DTI = 'Unknown'
where DTI is null or DTI='';

update risk_segment
set LTI = 'Unknown'
where LTI is null or LTI='';

select a.*,
b.Loan_status
from risk_segment a
left join loan_updated1 b 
on a.Customer_ID = b.Customer_ID
order by Customer_ID;

#customer data split based on data available
with borrower_knwn AS (
SELECT
a.*,
b.Clusters
From income_credit_score a 
LEFT join loan_risk b 
ON a.Customer_ID = b.Customer_ID
order by Customer_ID
),
cust_with_loan as (
SELECT Distinct *
From borrower_knwn 
where Clusters is not null
),
cust_with_loan_txn as (
select a.*,
b.Transaction_id
from cust_with_loan a
left join transactn1 b
on a.customer_id = b.customer_id
order by customer_id
)
select Distinct Customer_ID,
Income,
Credit_score,
Clusters,
Credit_risk_segment
from cust_with_loan_txn
where transaction_id is null;
with cust_txn_dt as (
select a.*,
b.transaction_id
from cust_no_loan a
left join transactn1 b 
on a.customer_id = b.customer_id
order by customer_id
)
select *
from cust_txn_dt
where transaction_id is not null
order by customer_id;
 
# Transaction quality metrics
Delimiter $$

Create Procedure Txn_quality()
Begin
  With txn_metric As (
    Select Customer_ID,
    round(Sum(Case when Status='SUCCESS' then Amount_in_INR END),2) AS Total_success_amnt,
    round(Sum(Case when Status='FAILED' then Amount_in_INR END),2) AS Total_failed_amnt,
    round(Sum(Case when Status='PENDING' then Amount_in_INR END),2) AS Total_pending_amnt,
    round(Sum(Case when Status='UNKNOWN' then Amount_in_INR END),2) AS Total_unknown_amnt,
    count(transaction_id) AS txn_count,
    count(Case when Status='SUCCESS' then transaction_id END) AS Success_txn,
    count(Case when Status='FAILED' then transaction_id END) AS Failed_txn,
    count(Case when Status='PENDING' then transaction_id END) AS Pending_txn,
    count(Case when Status='UNKNOWN' then transaction_id END) AS Unk_txn,
    round(sum(Amount_in_INR),2) AS Total_txn_amnt
    From transactn1
    group by Customer_ID
    order by Customer_ID
    )
    Select Distinct Customer_ID, txn_count, Total_txn_amnt, Total_success_amnt, Total_failed_amnt,
    Total_pending_amnt, Total_unknown_amnt, Success_txn, Failed_txn, Pending_txn, Unk_txn,
    (Success_txn / txn_count) AS Success_rate,
    (Failed_txn / txn_count) AS Failed_rate,
    (pending_txn / txn_count) AS Pending_rate,
    (unk_txn / txn_count) AS Unknown_rate
    From txn_metric;
END$$

Delimiter ;

Select * from txn_quality;
update txn_quality
Set Total_failed_amnt=0
Where Total_failed_amnt is null or '';

Drop Procedure IF Exists Txn_quality ;    
Call Txn_quality();    
    
Alter Table loan_risk add column risk_segment VARCHAR(20);

update loan_risk
set risk_segment = Case
	when clusters = 0 then 'Low risk'
    when clusters = 1 then 'Medium risk'
    when clusters = 2 then 'High risk'
END;

with default_cust as (
select a.Customer_ID,
b.*,
from loan_risk a 
left join transactn1 b
on a.Customer_ID = b.Customer_ID
where a.Loan_status = 'default'
order by Customer_ID
),
with txn_metric as (
Select Customer_ID,
    round(Sum(Case when Status='SUCCESS' then Amount_in_INR END),2) AS Total_success_amnt,
    round(Sum(Case when Status='FAILED' then Amount_in_INR END),2) AS Total_failed_amnt,
    round(Sum(Case when Status='PENDING' then Amount_in_INR END),2) AS Total_pending_amnt,
    round(Sum(Case when Status='UNKNOWN' then Amount_in_INR END),2) AS Total_unknown_amnt,
    count(transaction_id) AS txn_count,
    count(Case when Status='SUCCESS' then transaction_id END) AS Success_txn,
    count(Case when Status='FAILED' then transaction_id END) AS Failed_txn,
    count(Case when Status='PENDING' then transaction_id END) AS Pending_txn,
    count(Case when Status='UNKNOWN' then transaction_id END) AS Unk_txn,
    round(sum(Amount_in_INR),2) AS Total_txn_amnt
    From default_cust
    group by Customer_ID
    order by Customer_ID
)
Select Distinct Customer_ID, txn_count, Total_txn_amnt, Total_success_amnt, Total_failed_amnt,
    Total_pending_amnt, Total_unknown_amnt, Success_txn, Failed_txn, Pending_txn, Unk_txn,
    (Success_txn / txn_count) AS Success_rate,
    (Failed_txn / txn_count) AS Failed_rate,
    (pending_txn / txn_count) AS Pending_rate,
    (unk_txn / txn_count) AS Unknown_rate
    From txn_metric
    order by Customer_ID;
    
# default transaction behaviour
WITH default_cust AS (
  SELECT
    b.*
  FROM loan_risk a
  LEFT JOIN transactn1 b
    ON a.Customer_ID = b.Customer_ID
  WHERE a.Loan_status = 'default'
),
txn_metric AS (
  SELECT
    Customer_ID,
    ROUND(SUM(CASE WHEN Status = 'SUCCESS' THEN Amount_in_INR ELSE 0 END), 2) AS Total_success_amnt,
    ROUND(SUM(CASE WHEN Status = 'FAILED'  THEN Amount_in_INR ELSE 0 END), 2) AS Total_failed_amnt,
    ROUND(SUM(CASE WHEN Status = 'PENDING' THEN Amount_in_INR ELSE 0 END), 2) AS Total_pending_amnt,
    ROUND(SUM(CASE WHEN Status = 'UNKNOWN' THEN Amount_in_INR ELSE 0 END), 2) AS Total_unknown_amnt,
    COUNT(transaction_id) AS txn_count,
    COUNT(CASE WHEN Status = 'SUCCESS' THEN transaction_id END) AS Success_txn,
    COUNT(CASE WHEN Status = 'FAILED'  THEN transaction_id END) AS Failed_txn,
    COUNT(CASE WHEN Status = 'PENDING' THEN transaction_id END) AS Pending_txn,
    COUNT(CASE WHEN Status = 'UNKNOWN' THEN transaction_id END) AS Unk_txn,
    ROUND(SUM(Amount_in_INR), 2) AS Total_txn_amnt
  FROM default_cust
  GROUP BY Customer_ID
)
SELECT
  Customer_ID,
  txn_count,
  Total_txn_amnt,
  Total_success_amnt,
  Total_failed_amnt,
  Total_pending_amnt,
  Total_unknown_amnt,
  Success_txn,
  Failed_txn,
  Pending_txn,
  Unk_txn,
  ROUND(Success_txn / NULLIF(txn_count, 0), 4) AS Success_rate,
  ROUND(Failed_txn  / NULLIF(txn_count, 0), 4) AS Failed_rate,
  ROUND(Pending_txn / NULLIF(txn_count, 0), 4) AS Pending_rate,
  ROUND(Unk_txn     / NULLIF(txn_count, 0), 4) AS Unknown_rate
FROM txn_metric
ORDER BY Customer_ID;

#non defeault txn behaviour
WITH nondefault_cust AS (
  SELECT
    b.*
  FROM loan_risk a
  LEFT JOIN transactn1 b
    ON a.Customer_ID = b.Customer_ID
  WHERE a.Loan_status <> 'default'   -- or = 'non-default' if that's your label
),
txn_metric AS (
  SELECT
    Customer_ID,
    ROUND(SUM(CASE WHEN Status = 'SUCCESS' THEN Amount_in_INR ELSE 0 END), 2) AS Total_success_amnt,
    ROUND(SUM(CASE WHEN Status = 'FAILED'  THEN Amount_in_INR ELSE 0 END), 2) AS Total_failed_amnt,
    ROUND(SUM(CASE WHEN Status = 'PENDING' THEN Amount_in_INR ELSE 0 END), 2) AS Total_pending_amnt,
    ROUND(SUM(CASE WHEN Status = 'UNKNOWN' THEN Amount_in_INR ELSE 0 END), 2) AS Total_unknown_amnt,
    COUNT(transaction_id) AS txn_count,
    COUNT(CASE WHEN Status = 'SUCCESS' THEN transaction_id END) AS Success_txn,
    COUNT(CASE WHEN Status = 'FAILED'  THEN transaction_id END) AS Failed_txn,
    COUNT(CASE WHEN Status = 'PENDING' THEN transaction_id END) AS Pending_txn,
    COUNT(CASE WHEN Status = 'UNKNOWN' THEN transaction_id END) AS Unk_txn,
    ROUND(SUM(Amount_in_INR), 2) AS Total_txn_amnt
  FROM nondefault_cust
  GROUP BY Customer_ID
)
SELECT
  Customer_ID,
  txn_count,
  Total_txn_amnt,
  Total_success_amnt,
  Total_failed_amnt,
  Total_pending_amnt,
  Total_unknown_amnt,
  Success_txn,
  Failed_txn,
  Pending_txn,
  Unk_txn,
  ROUND(Success_txn / NULLIF(txn_count, 0), 4) AS Success_rate,
  ROUND(Failed_txn  / NULLIF(txn_count, 0), 4) AS Failed_rate,
  ROUND(Pending_txn / NULLIF(txn_count, 0), 4) AS Pending_rate,
  ROUND(Unk_txn     / NULLIF(txn_count, 0), 4) AS Unknown_rate
FROM txn_metric
ORDER BY Customer_ID;

select
sum(Success_rate)/count(Success_rate) as avg_s_rate, 
sum(Failed_rate)/count(Failed_rate) as avg_f_rate
from default_txn ;

select
sum(Success_rate)/count(Success_rate) as avg_s_rate, 
sum(Failed_rate)/count(Failed_rate) as avg_f_rate
from non_default_txn ;

#transaction quality
 With txn_metric as (   
    Select Customer_ID,Branch,
    round(Sum(Case when Status='SUCCESS' then Amount_in_INR END),2) AS Total_success_amnt,
    round(Sum(Case when Status='FAILED' then Amount_in_INR END),2) AS Total_failed_amnt,
    round(Sum(Case when Status='PENDING' then Amount_in_INR END),2) AS Total_pending_amnt,
    round(Sum(Case when Status='UNKNOWN' then Amount_in_INR END),2) AS Total_unknown_amnt,
    count(transaction_id) AS txn_count,
    count(Case when Status='SUCCESS' then transaction_id END) AS Success_txn,
    count(Case when Status='FAILED' then transaction_id END) AS Failed_txn,
    count(Case when Status='PENDING' then transaction_id END) AS Pending_txn,
    count(Case when Status='UNKNOWN' then transaction_id END) AS Unk_txn,
    round(sum(Amount_in_INR),2) AS Total_txn_amnt
    From transactn1
    group by Customer_ID,Branch
    order by Customer_ID
    )
    Select Distinct Customer_ID, Branch, txn_count, Total_txn_amnt, Total_success_amnt, Total_failed_amnt,
    Total_pending_amnt, Total_unknown_amnt, Success_txn, Failed_txn, Pending_txn, Unk_txn,
    ROUND(Success_txn / NULLIF(txn_count, 0), 4) AS Success_rate,
    ROUND(Failed_txn  / NULLIF(txn_count, 0), 4) AS Failed_rate,
    ROUND(Pending_txn / NULLIF(txn_count, 0), 4) AS Pending_rate,
    ROUND(Unk_txn     / NULLIF(txn_count, 0), 4) AS Unknown_rate
    From txn_metric;
