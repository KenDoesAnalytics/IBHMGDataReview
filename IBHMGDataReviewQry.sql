/*
PROJECT AUTH 
	Some Health Insurances require Approved Referrals/Authorizations for services to be received and paid through insurance. 
	Patient's are responsible for Contracted Rates should Referral/Auth be Invalid or Absent. This subsequently leads to No Payment, Delayed Payment, and Loss of Business. This is one of the many hassles when working with health insurances.
	Providers and Medical Groups operate differently. Personally I get individual Auths completed when possible. Other times, a whole 8-hour work day is required to get majority completed.
Applications Used: 
	Microsoft Excel
	Power Query Editor
	MSSQL SSMS 2019
	Clinical EHR Database.
Tasks generally include Extract and Transform, but No Load. ETL without the L.

This Query serves as a Template for Authorization Review every 1-2 months. 
	Personally, utilizing this Query makes it more simple and organized to see which Patients from which Medical Groups require New Auths.
Tebra EHR (Electronic Health Records) provides different Reports for review. 
	However, such reports are static for all subscribers and therefore further review & analysis is required for ensuring mental health services are covered. 
	Additionally there is always missing and/or inaccurate data that needs reviewed and updated.
	Note: Tebra was formerly known as Kareo, should they be used interchangeably
Some of available Reports with pertinent information for treatment of care: 
	1. Appointment Details (Provider, Patient Name, DOB) - To track upcoming appointments
	2. Auth End Date (Patient Name, Insurance Plan, Health Plan, Visits Remaining, Auth Start, Auth End, Notes) - To track Patients that require New Auths
	3. Demographics Export (All Patient Name, DOB) - To track missing Patients with health plans that generally require Authorizations
Reports are Exported (Extracted) from EHR to Excel file
	Data is Cleaned and updated into New Sheet (refer to "OG Tables" below)
	Data is Imported into Microsoft SQL Server & queried below
	Final Query Results are Saved As Excel Workbook
	Microsoft Excel Power Query Editor is used to Merge the Queried Table with Previously Edited Table for Clinical Use. 
	The Merged Query is available to review Authorizations and submit requests to insurance for New and On-going Treatment of Care.
*/

------------------------------------------------------------------------------

/*
TABLE IBHMGDataReview20230702..ScheduledAppts
From Report IBHMG_Appointment_Details...
	Table tracks Appointments from Export Date to Desired End Date.
	Unable to Query Flash-Fill / Fill-Down of DOS Appts Column with Imported Data. Would have to do it manually in Excel.
		Therefore Providers and DOS columns have been removed 
		Therefore Guide to Filling Down In SQL does not apply https://towardsdatascience.com/tips-and-tricks-how-to-fill-null-values-in-sql-4fccb249df6f    
	Name is reformatted with Patient ID # and Parentheses removed
*/
SELECT 
    DISTINCT REPLACE(REPLACE(TRANSLATE("Patient/Subject", '0123456789', '##########'), '#', ''), '()', '') AS Patient,
	DOB
INTO IBHMGDataReview20230702..ScheduledAppts
FROM 
    IBHMGDataReview20230702..ApptsDetailCleaned
WHERE
    "Patient/Subject" IS NOT NULL;



/*
TABLE IBHMGDataReview20230702..AuthStatus
From Report IPMG_Insurance_Auth_End_Date
	There may be some Patients who require Auth but none is updated into Insurance Case.
	Queries Insurance Auths by Desc Date
	Older Auths for Patients with Multiple Authorizations are removed
	Visits Remaining confirms whether Auth used up before Expiration Date.
	Name is Reformatted from "Last, First" to "First Last" with extra spacing removed
*/
WITH CTE AS (
    SELECT 
        REPLACE(REPLACE(SUBSTRING([Patient Name], CHARINDEX(', ', [Patient Name]) + 2, LEN([Patient Name])) + ' ' + SUBSTRING([Patient Name], 1, CHARINDEX(', ', [Patient Name]) - 1), '  ', ' '), '  ', ' ') AS [Patient],
        [Ins Plan Name], 
        FORMAT ([Auth_End Date], 'MM/dd/yy') AS [Auth_End Date], 
        [Visits Remaining],
        ROW_NUMBER() OVER (PARTITION BY [Patient Name] ORDER BY [Auth_End Date] DESC) AS RowNum
    FROM IBHMGDataReview20230702..AuthCleaned
    WHERE [Patient Name] IS NOT NULL
)
SELECT [Patient], [Ins Plan Name], [Auth_End Date], [Visits Remaining]
INTO IBHMGDataReview20230702..AuthStatus
FROM CTE
WHERE RowNum = 1
ORDER BY [Ins Plan Name] ASC, [Auth_End Date] DESC;



/*
TABLE IBHMGDataReview20230702..Demographics
From IBHMGDataReview20230702..DemographicsExportCleaned
	Unable to change DOB format to MO/DA/YEAR therefore changed DOB to MO/DA/YR
		FORMAT is not used as ChatGPT recommendation came out invalid d/t vnarchar
	Removed Null/Empty Patient Names. 
*/
SELECT 
    TRIM(REPLACE(REPLACE(REPLACE(CONCAT([Patient First Name], ' ', [Patient Middle Name], ' ', [Patient Last Name]), '  ', ' '), '  ', ' '), '  ', ' ')) AS Patient,
    RIGHT('00' + CAST(DATEPART(MONTH, [Patient DOB]) AS VARCHAR(2)), 2) + '/' + RIGHT('00' + CAST(DATEPART(DAY, [Patient DOB]) AS VARCHAR(2)), 2) + '/' + RIGHT(CAST(YEAR([Patient DOB]) AS VARCHAR(4)), 2) AS DOB,
	[Default Case Name],
	[Auth End Date1]
INTO IBHMGDataReview20230702..Demographics
FROM
    IBHMGDataReview20230702..DemographicsExportCleaned
WHERE 
    TRIM(REPLACE(REPLACE(REPLACE(CONCAT([Patient First Name], ' ', [Patient Middle Name], ' ', [Patient Last Name]), '  ', ' '), '  ', ' '), '  ', ' ')) IS NOT NULL
    AND TRIM(REPLACE(REPLACE(REPLACE(CONCAT([Patient First Name], ' ', [Patient Middle Name], ' ', [Patient Last Name]), '  ', ' '), '  ', ' '), '  ', ' ')) <> ''
ORDER BY 
	[Default Case Name] ASC, 
	[Patient] ASC;


/*
TABLE IBHMGDataReview20230702..IBHMGAuthsForReview202307
JOIN TABLES
Here we Join tables and update properly. Despite having created New Table quiried from OG Tables, we find there are still some issues
	Initially "Patient" was renamed for all tables. However, this became inconvenient because we want all Patient Names, but distinguish names for those with Scheduled Appt
	Therefore, we kept Patients from Demographics > LEFT JOIN the other 2 tables > Marked X for Scheduled Patients that match ones from Demographics, as not all patients in system are active.
	Ideally "Auth End Date" should be updated and most current. Unfortunately Auth Report and Demographics Report contain different dates. Therefore Most Recent Auth Date is merged into 1 column. 
	Default Case Name is Primary ASC in order to track Authorizations and complete Auth Requests in an organized manner, grouped by Insurance Plan 
At times, it is important to SELECT * however in this case some columns are omitted.
Default Case Name has a lot of NULL despite having updated some into the system.
Auth H/o is quick check for relatively confirmation of whether Auth is required.
*/
SELECT 
	ROW_NUMBER() OVER (ORDER BY demo.Patient) AS [Patient #],
	demo.Patient,
	demo.DOB,
	demo.[Default Case Name],
	auth.[Ins Plan Name],
	CASE WHEN sch.Patient = demo.Patient THEN 'X' ELSE sch.Patient END AS [Scheduled],
	CASE WHEN auth.Patient = demo.Patient THEN 'X' ELSE auth.Patient END AS [Auth H/o],
    COALESCE(GREATEST(demo.[Auth End Date1], auth.[Auth_End Date]), demo.[Auth End Date1], auth.[Auth_End Date]) AS [Auth End Date],
	auth.[Visits Remaining]
INTO IBHMGDataReview20230702..IBHMGAuthsForReview202307
FROM IBHMGDataReview20230702..Demographics demo 
LEFT JOIN IBHMGDataReview20230702..AuthStatus auth 
	ON demo.Patient = auth.Patient 
LEFT JOIN IBHMGDataReview20230702..ScheduledAppts sch 
	ON sch.Patient = demo.Patient 
	AND sch.DOB = demo.DOB
ORDER BY [Default Case Name] ASC, Patient ASC;

------------------------------------------------------------------------------

--OG Tables 
Select * 
From IBHMGDataReview20230702..ApptsDetailCleaned

Select * 
From IBHMGDataReview20230702..AuthCleaned

Select * 
From IBHMGDataReview20230702..DemographicsExportCleaned

--Qry1 Tables
Select * 
From IBHMGDataReview20230702..ScheduledAppts

Select * 
From IBHMGDataReview20230702..AuthStatus

Select * 
From IBHMGDataReview20230702..Demographics

--Qry2 Table Final
Select * 
From IBHMGDataReview20230702..IBHMGAuthsForReview202307
