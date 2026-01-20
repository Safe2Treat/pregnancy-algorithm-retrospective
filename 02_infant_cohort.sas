
/********************************************************************************************************************************************
Program Name: 02_infant_cohort.sas
Goal: To create a cohort of infants for Liz Suarez adaptation of the Ailes et al. 2023 pregnancy identification algorithm.

Input:	raw.enrdet files
		covref.delivery
		covref.ga
		covref.preg_markers

Macros: 	

Output: out.infant_suarez_deliverycodes
		out.infant_suarez

Programmer: Chase Latour (CDL)
Date: May 2024 

Modifications:
- 05.29.2024 -- Incorporated modifications by Kim - Liz Suarez analyst after CDL QC.
- 04.01.2025 -- Updated to include MS year 2023

********************************************************************************************************************************************/








/***************************************************************************************************************

TABLE OF CONTENTS:
	- 00 - SET LIBRARIES
	- 01 - IDENTIFY ENROLLMENT INFORMATION
	- 02 - IDENTIFY CONTINUOUS ENROLLMENT
	- 03 - CREATE OTHER VARIABLES
	- 04 - IDENTIFY DOB MIN AND MAX
	- 05 - GET FIRST CLAIM FOR INFANTS
	- 06 - OUTPUT INFANT DATASET

***************************************************************************************************************/








/***************************************************************************************************************

											00 - SET LIBRARIES

***************************************************************************************************************/


/*run this locally if you need to log onto the N2 server.*/
/*SIGNOFF;*/
/*%LET server=n2.schsr.unc.edu 1234; */
/*options comamid=tcp remote=server; */
/*signon username=_prompt_;*/

*Run setup macro and define libnames;
options sasautos=(SASAUTOS "/local/projects/marketscan_preg/raw_data/programs/macros");
/*change "saveLog=" to "Y" when program is closer to complete*/
%setup(sample=random1pct, programname=ailes_suarez_modification/02_infant_cohort, savelog=Y)

options mprint minoperator;

/*/*Create local mirrors of the server libraries*/*/
/*libname lout slibref=out server=server;*/
/*libname lwork slibref = work server = server;*/
/*libname lcovref slibref = covref server = server;*/
/*libname lder slibref = der server=server;*/
/*libname lraw slibref = raw server=server;*/










/***************************************************************************************************************

									01 - IDENTIFY ENROLLMENT INFORMATION

We want to get the enrollment information for everyone enrolled in MarketScan at age 0.
***************************************************************************************************************/

*Identify all the years that you are looking through - WE CAN ADD IN MORE YEARS LATER;
%let years = 2000 2001 2002 2003 2004 2005 2006 2007 2008 2009 2010 2011 2012 2013 2014 2015 2016 2017 2018 2019 2020 2021 2022 2023;



*Identify all IDs in the enrollment files who have at least 1 period with age=0 and non-missing enrolid
Did NOT consider type of plan (e.g., FFS versus other). Stack all of the IDs on top of each other.;
%macro stack_infant_id();
	/*Calculate the number of years*/
	%let numYr = %sysfunc(countw(&years));

	/*Apply this loop for each year-s file*/
	%do d=1 %to &numYr;
		%let loop&d = %scan(&years, &d);

		/*If the first year, create the starting file. Identify distinct enrolids for individuals with
		at least 1 year where they are enrolled at age 0*/
		%if &d = 1 %then %do;
			proc sql;
				create table infant_ids as
				select distinct enrolid
				from raw.enrdet&&loop&d
				where age=0 and enrolid ne .;
				quit; 
		%end;
		
		/*Going to stack on all the IDs meeting the above criteria for subsequent years*/
		%else %if &d ne 1 %then %do;

			proc sql;
				insert into infant_ids
				select distinct enrolid
				from raw.enrdet&&loop&d
				where age=0 and enrolid ne .;
				;
				quit;
		%end;

	%end;

%mend;

%stack_infant_id();



/*Now select the distinct infant IDs*/
proc sql;
	create table infant_ids_distinct as
	select distinct enrolid
	from infant_ids
	;
	quit;
***1pct: 88,324 -- 10.28.2024;




/*Now, grab all the relevant enrollment information
We want all monthly enrollment records for individuals enrolled as infants*/
%macro get_infant_enrol();

	/*Calculate the number of years*/
	%let numYr = %sysfunc(countw(&years));

	/*Run analyses over each year-s enrollment file*/
	%DO d=1 %TO &numYr;

		%let loop&d = %scan(&years, &d);

		/*Create the base file for the first year*/
		%if &d = 1 %then %do;
			proc sql;
				create table infant_enroll as
					select b.enrolid, b.dobyr, b.age, b.dtstart, b.dtend
					from infant_ids_distinct as a
					inner join raw.enrdet&&loop&d (where  = (enrolid ne . and 0 <= age <= 1)) as b
					on a.enrolid = b.enrolid
					;
					quit;
		%end;
		
		/*Stack in subsequent year-s enrollment information*/
		%else %if &d ne 1 %then %do;
			proc sql;
				insert into infant_enroll
				select b.enrolid, b.dobyr, b.age, b.dtstart, b.dtend
				from infant_ids_distinct as a
				inner join raw.enrdet&&loop&d (where  = (enrolid ne . /*and 0 <= age <= 1*/)) as b
				on a.enrolid = b.enrolid
				;
				quit;
		%end;

	%END;

%mend;
%get_infant_enrol();

*Check counts;
/*proc sql;*/
/*	select count(distinct enrolid) as distinct_n from infant_enroll;*/
/*	quit; ***1pct: 88324 -- CDL, 10.28.2024;*/

/*proc contents data = infant_enroll; run;*/












/***************************************************************************************************************

									02 - IDENTIFY CONTINUOUS ENROLLMENT

***************************************************************************************************************/

/*NOTE: We SKIP the step where we identify someone-s first continuous enrollment period here.
Instead, we derive that information from the final continuous enrollment file.**/


/*Sort data for identifying necessary variables.*/
proc sort data=infant_enroll;
	by enrolid dtstart;
run;


/*Identify continuous enrollment periods - Create CESEG variable
	CESEG(flag): Each gap in continuous eligibility greater than 31 days � 
	Increasing count for each new continuous enrollment period (i.e., the 
	same value for each month within a continuous enrollment period).
*/
%let gap = 31; *CDL: 10.28.2024 -- Updated to 31 from 30;
data infant_enroll2;
set infant_enroll;
	by enrolid dtstart;
	retain CESEG .;

	*Calculate time elapsed between most recent and previous;
	days_elapsed = dtstart - lag(dtend);

	if first.enrolid then days_elapsed = .;

	if first.enrolid then CESEG = 1;
		else if days_elapsed <= &gap then CESEG = CESEG;
		else if days_elapsed >  &gap then CESEG = CESEG + 1;

	drop days_elapsed;

run;




*Get the start and end dates for an infants first continuous
enrollment period;
proc sql;
	create table first_cont_enrl as
	select enrolid, min(dtstart) as ce_start /*dtstart*/ format yymmddd10., 
			max(dtend) as ce_end /*dtend*/ format yymmddd10.,
			min(age) as min_age
	from infant_enroll2
	where ceseg = 1
	group by enrolid
	;
	quit; **1pct: 88,324 -- CDL, 10.28.2024;

*Everyone included in this dataset should have their first continuous 
enrollment period starting at age 0 per the above criteria.
However, confirm here;
/*proc freq data=first_cont_enrl;*/
/*	table min_age;*/
/*run;*/
*all start at age 0 -- 1pct: 88,324, CDL - 10.28.2024;












/***************************************************************************************************************

									03 - CREATE OTHER VARIABLES

***************************************************************************************************************/

*Additional variables to create -- 

- ENRSEG - a counter for each month of enrollment
- AGESEG - a counter for each month of enrollment at the same age - age 0 would get a flag of 1, age 1 a flag of 2, etc.
- ENRSEG_N - sum of the number of enrollment months for that infant
- AGESEG_N - a counter for each month within 1 age;


/*Explicit sort again for identifying variables (unnecessary)*/
proc sort data=infant_enroll2;
	by enrolid dtstart; 
run;

*Create enrseg;
data infant_enroll3;
set infant_enroll2;
	by enrolid dtstart; 
	retain ENRSEG . ;

	if first.enrolid then ENRSEG = 1;
		else ENRSEG = ENRSEG + 1;

run;

*Create AGESEG;
proc sort data=infant_enroll3;
	by enrolid age;
run;
data infant_enroll3b;
set infant_enroll3;
	by enrolid age;
	retain AGESEG;

	if first.enrolid then AGESEG = 1;
		else if first.age then AGESEG = AGESEG + 1;
		else AGESEG = AGESEG;
run;


*Create AGESEG_N;
proc sort data=infant_enroll3b;
	by enrolid ageseg dtstart;
run;
data infant_enroll3c;
set infant_enroll3b;
	retain AGESEG_N;
	by enrolid AGESEG dtstart;

	if first.ageseg then AGESEG_N = 1;
		else AGESEG_N = AGESEG_N + 1;

run;

*Create ENRLSEG_N ;
proc sql;
	create table infant_enroll4 as 
	select a.*, b.ENRSEG_N
	from infant_enroll3c as a
	left join (select enrolid, count(enrolid) as ENRSEG_N
				from infant_enroll3c
				group by enrolid) as b
	on a.enrolid = b.enrolid
	;
	quit;

*Sort it back for easier viewing;
proc sort data=infant_enroll4;
	by enrolid dtstart;
run;
















/***************************************************************************************************************

									04 - IDENTIFY DOB MIN AND MAX

***************************************************************************************************************/

*Flag those with insufficient data (LOGIC GROUP = 0) - NOW MOVED TO THE END.
***********************************************************************************;

*Create the dataset of enrolids that dont have enough information 
for us to estimate a DOB;
/*%PUT IDENTIFY LOGICGROUP = 0;*/
/**/
/*data LG0 (keep=enrolid logicgroup dobyr dob_min dob_max);*/
/*set infant_enroll4; *elig5; *Changed input to match my above;*/
/*	if day(dtstart)=1 and dobyr=year(dtstart) and EnrSeg=1 and EnrSeg_n<12 then LogicGroup=0; *Modifies the first enrollment segment;*/
/*	if logicgroup=0 then dob_min=.;*/
/*	if logicgroup=0 then dob_max=.;*/
/*	if logicgroup=. then delete; *Only retains the first enrollment segment because we only need their ID values;*/
/*run;*/
/**/
/*%PUT COUNT OF DISTINCT IDS WITH LOGICGROUP = 0;*/
/*proc sql;*/
/*	select count(distinct ENROLID) as COUNT_IDS from LG0 where logicgroup=0; 		***125,890 (13.7% of rec);*/
/*	*select count(*) as COUNT_IDS from LG0 where logicgroup=0; 						***125,890;*/
/*	quit;*/
/**/
/**Create the datset of individuals that are going to go on for the rest of logic group assessment.;*/
/*proc sql;*/
/*	create table LG1_input*/
/*	as select * from infant_enroll4 /*elig5*/*/
/*	where enrolid not in (select enrolid from LG0);*/
/*	quit;*/



*(LOGIC GROUP = 1: Enrollment Start NOT on first day of month and enrollment year 
equal year of birth
***********************************************************************************;

%PUT IDENTIFY EVERYONE WITH LOGICGROUP = 1;

proc sort data=infant_enroll4; *LG1_input;
	by enrolid dtstart;
run;

*Identify the first enrollment month and see if meets the criteria;
data temp1;
set infant_enroll4; *LG1_input;
	if age=0 and day(dtstart)ne 1 and EnrSeg=1 and dobyr=year(dtstart) then LogicGroup=1;
run;

*Assign DOB min and max;
data LG1 (keep=enrolid logicgroup dobyr dob_min dob_max);
set temp1; 

	*Deal with February and leap years;
	if dobyr in (1996, 2000, 2004, 2008, 2012, 2016, 2020) and month(dtstart)=2 then dob_day_max=29;
	if dobyr not in (1996, 2000, 2004, 2008, 2012, 2016, 2020) and month(dtstart)=2 then dob_day_max=28;

	if month(dtstart) in (1, 3, 5, 7, 8, 10, 12) then dob_day_max=31;
	if month(dtstart) in (4, 6, 9, 11) then dob_day_max=30;

	if logicgroup=1 then dob_min=mdy(month(dtstart),1,dobyr);
	if logicgroup=1 then dob_max=mdy(month(dtend),dob_day_max,dobyr);
	format dob_min dob_max yymmddd10.;

	*Delete all enrollment months where not useful for identifying qualifying person;
	if logicgroup=. then delete;
run;

%PUT COUNT DISTINCT IDS WHERE LOGICGROUP = 1;
proc sql;
	select count(distinct ENROLID) as COUNT_IDS from LG1 where logicgroup=1; 	
	quit;

*Create dataset of individuals that need to be assigned a DOB MIN and MAX and now evaluated using logic group 2 logic.;
proc sql;
	create table LG2_input
	as select * from infant_enroll4 /*elig5*/
	where enrolid not in (select enrolid from LG1);
	quit;











*STEP 8 - Age zero in 1st and 13th month (LOGIC GROUP = 2)
***********************************************************************************;

%PUT IDENTIFY LOGIC GROUP 2 INFANTS;

*Identify individuals where age=0 on the 1st and 13th month of enrollment;
data temp2;
set LG2_input;
	if age=0 and enrseg=13 and ceseg=1 then LogicGroup = 2; *Guaranteed that ceseg = 1 if age=0 when enrseg=13. However, added ceseg = 1 to ensure;
run;

*Assign DOB_MIN and DOB_MAX;
data LG2 (keep=enrolid logicgroup dobyr dob_min dob_max);
set temp2;

	**Assign day;
		*Deal w February and leap years;
	if dobyr in (1996, 2000, 2004, 2008, 2012, 2016, 2020) and month(dtstart)=2 then dob_day_max=29;
	if dobyr not in (1996, 2000, 2004, 2008, 2012, 2016, 2020) and month(dtstart)=2 then dob_day_max=28;
		*Rest of the months;
	if month(dtstart) in (1, 3, 5, 7, 8, 10, 12) then dob_day_max=31;
	if month(dtstart) in (4, 6, 9, 11) then dob_day_max=30;

	if logicgroup=2 then dob_min=mdy(month(dtstart),1,dobyr);
	if logicgroup=2 then dob_max=mdy(month(dtstart),dob_day_max,dobyr);

	if logicgroup=. then delete;
	format dob_min dob_max yymmddd10.;
run;

%PUT COUNT OF DISTINCT IDS FOR LOGIC GROUP 2 INFANTS;
proc sql;
	select count(distinct ENROLID) as COUNT_IDS from LG2 where logicgroup=2; 		
	quit;

*Output the dataset to identify those where LOGICGROUP = 3;
proc sql;
	create table LG3_input
	as select * from LG2_input
	where enrolid not in (select enrolid from LG2);
	quit;







*Age changes in 13th enrollment segment  (LOGIC GROUP = 3)
***********************************************************************************;

%PUT IDENTIFY LOGIC GROUP 3 INFANTS;

*Identify individuals that should have logic group = 3;
data temp3;
set LG3_input;
	if age=0 and enrseg=12 and ageseg=1 and ceseg=1 then flag=1; 
	if age=1 and enrseg=13 and ageseg=2 and ceseg=1 then flag=1;
run;
data temp3b;
set temp3;
	lag=flag-lag(flag);
	if lag=0 then output; /*Will always output the enrseg = 13 row*/
run;

*Calculate DOB_MIN and DOB_MAX for everyone where logic group = 3;
data LG3 (keep=enrolid logicgroup dobyr dob_min dob_max);
set temp3b;

	*Set DOB month to prior month;
	if month(dtstart)=1 then month=12; *If January, then prior month is December;
	if month(dtstart) ne 1 then month=month(dtstart)-1; *Otherwise, just subtract 1 from the month;

	*SET DOB day;
		** Deal with Feb and leap year;
	if dobyr in (1996, 2000, 2004, 2008, 2012, 2016, 2020) and month=2 then dob_day_max=29;
	if dobyr not in (1996, 2000, 2004, 2008, 2012, 2016, 2020) and month=2 then dob_day_max=28;
	if month in (1, 3, 5, 7, 8, 10, 12) then dob_day_max=31;
	if month in (4, 6, 9, 11) then dob_day_max=30;

	dob_min=mdy(month,1,dobyr);
	dob_max=mdy(month,dob_day_max,dobyr);
	format dob_min dob_max yymmddd10.;
	logicgroup=3;
run;

%PUT COUNT LOGIC GROUP 3 INFANTS;
*Calculate counts;
proc sql;
	select count(distinct ENROLID) as COUNT_IDS from LG3 where logicgroup=3; 	*104,158;
	quit;

*Create dataset that is going to be evaluated for logic group 4;
proc sql;
	create table LG4_input
	as select * from LG3_input 
	where enrolid not in (select enrolid from LG3);
	quit;

*Checks;
/*proc means data=lg4_input n mean median std min max;*/
/*	var age EnrSeg AgeSeg CESeg EnrSeg_n ageseg_n;*/
/*run;*/









*Multiple age Changes (LOGIC GROUP = 4)
***********************************************************************************;

%PUT IDENTIFY LOGIC GROUP 4 INFANTS;

 *identify all instances of full age year (i.e., same age for 12 continuous months) -- in this code, only for ages 0 and 1;
proc sort data=LG4_input;
	by enrolid ageseg;
run;

*Flag the last record of each continuous age segment.;
data temp4;
set LG4_input;
	by enrolid ageseg;
	if last.ageseg then flag=1;
	if ageseg_n=12 and flag=1 then output; *If flag occurs on 12th month of age-year, keep that record;
run;

*Assign the DOBMIN and DOBMAX for each of the monthly enrollment records - some will be dropped later.;
data LG4_prelim (keep=enrolid logicgroup dobyr dob_min dob_max month);
set temp4;
	
	month=month(dtstart);
	if dobyr in (1996, 2000, 2004, 2008, 2012, 2016, 2020) and month(dtend)=2 then dob_day_max=29;
	if dobyr not in (1996, 2000, 2004, 2008, 2012, 2016, 2020) and month(dtend)=2 then dob_day_max=28;
	if month(dtend) in (1, 3, 5, 7, 8, 10, 12) then dob_day_max=31;
	if month(dtend) in (4, 6, 9, 11) then dob_day_max=30;

	dob_min=mdy(month(dtstart),1,dobyr);
	dob_max=mdy(month(dtend),dob_day_max,dobyr);
	format dob_min dob_max yymmddd10.;
	logicgroup=4;

run;

*Sort for easier reading;
proc sort data=LG4_prelim; 
	by enrolid dob_min; 
run;

*Check counts;
/*proc sql;*/
/*	select count(distinct ENROLID) as COUNT_IDS from LG4_prelim where logicgroup=4; */
/*	quit;*/


*Split file into those with one full year segment versus at least two full year segments;
*First, just grab the necessary variables.;
data LG4ids1 ;
set LG4_prelim (keep= enrolid month);
run;

proc sort data=LG4ids1; 
	by enrolid month; 
run;
**split file into those with one full year segment vs. at least two full year segments;
data singles1 dups1;
set LG4ids1;
	by enrolid;

	if first.enrolid and last.enrolid then output singles1; /*Dont want to retain these individuals for logic group 4*/
		else output dups1;
run;
*Check counts;
/*proc sql;*/
/*	select count(distinct ENROLID) as COUNT_IDS from singles1; 						/*those with one full age-year span*/*/
/*	select count(*) as COUNT_IDS from singles1; 										*/
/*	select count(distinct ENROLID) as COUNT_IDS from dups1; 						/*those with >1 full age-year span*/*/
/*	select count(*) as COUNT_IDS from dups1; 											*/
/*	quit;*/

*identify those with >1 full age-year span BUT different months;
proc sort data=dups1 nodup;  *Remove duplicates;
	by enrolid month; 
run;
*Now, if only one record after removing duplicates, then we want to retain.;
data singles2 dups2;
set dups1;
	by enrolid;

	if first.enrolid and last.enrolid then output singles2; *Want to retain these IDs;
		else output dups2;
run;
*Checks;
/*proc sql;*/
/*	select count(distinct ENROLID) as COUNT_IDS from singles2; 							*121633 - KEEP those with one possible dob-month ; */
/*	select count(*) as COUNT_IDS from singles2; 										*121633;*/
/*	select count(distinct ENROLID) as COUNT_IDS from dups2; 							*11538 - those with >1 possible dob-month; */
/*	select count(*) as COUNT_IDS from dups2; 											*24037;*/
/*	quit;*/




*remove end-of-year terms;
data dups2;
set dups2;
	if month=12 then delete;
run;

*Now remove duplicates;
proc sort data=dups2 nodup; 
	by enrolid month; 
run;
data singles3 dups3;
set dups2;
	by enrolid;
	if first.enrolid and last.enrolid then output singles3; 
		else output dups3;
run;
/*proc sql;*/
/*	select count(distinct ENROLID) as COUNT_IDS from singles3; 							*4333 -- KEEP those with one possible dob-month; */
/*	select count(*) as COUNT_IDS from singles3; 										*4333;*/
/*	select count(distinct ENROLID) as COUNT_IDS from dups3; 							*7205 --those with >1 possible dob-month; */
/*	select count(*) as COUNT_IDS from dups3; 											*14410;*/
/*	quit;*/

*Summarize the remaining full age years and retain ;
proc sql;
	create table singles4 as 
	select enrolid, max(month) as month
	from dups3
	group by enrolid;
	quit;

*Stack all fo the IDs for logic group 4;
data lg_4_ids;
	set singles2 singles3 singles4;
run;
*Remove any duplicates;
proc sort data=lg_4_ids nodup; 
	by enrolid month; 
run;
/*proc sql;*/
/*	select count(distinct ENROLID) as COUNT_IDS from singles4; 							*/
/*	select count(*) as COUNT_IDS from singles4; 										*/
/*	select count(distinct ENROLID) as COUNT_IDS from lg_4_ids; 							*/
/*	select count(*) as COUNT_IDS from lg_4_ids; 										*/
/*	quit;*/

*create and join final files;
proc sql;
	create table LG4 as 
	select a.* /*, b.* */ /*CDL: REMOVED the b to remove the WARNING*/
	from LG4_prelim as a 
	inner join lg_4_ids as b on 
	a.enrolid=b.enrolid and a.month=b.month;
	quit;
* Remove duplicates ;
proc sort data=LG4 nodup; 
	by enrolid dob_min dob_max; 
run;
*Check counts;
/*proc sql;*/
/*	select count(distinct ENROLID) as COUNT_IDS from LG4; 							*/
/*	select count(*) as COUNT_IDS from LG4; 											*/
/*	quit;*/

*Create the next dataset for logic group 5;
proc sql;
	create table LG5_input
	as select * from LG4_input
	where enrolid not in (select enrolid from LG4);
	quit;










*STEP 12 - One Age Change (LOGIC GROUP = 5)
***********************************************************************************;

*Identify all full age years -- only need 1;
data temp5;
set LG5_input;
	if ageseg_n=12 then output;
run;

*Check max number of times a ID shows up in this dataset;
/*proc sql;*/
/*	select max(count_id) as max_count*/
/*	from (select count(enrolid) as count_id*/
/*			from temp5*/
/*			group by enrolid)*/
/*	; */
/*	quit;*/

*Determine DOB_MIN and DOB_MAX for each enrollment record;
data LG5_prelim (keep=enrolid logicgroup dobyr dob_min dob_max);
set temp5;

	*Deal with February and leap years;
	if dobyr in (1996, 2000, 2004, 2008, 2012, 2016, 2020) and month(dtend)=2 then dob_day_max=29;
	if dobyr not in (1996, 2000, 2004, 2008, 2012, 2016, 2020) and month(dtend)=2 then dob_day_max=28;
	if month(dtend) in (1, 3, 5, 7, 8, 10, 12) then dob_day_max=31;
	if month(dtend) in (4, 6, 9, 11) then dob_day_max=30;

	dob_min=mdy(month(dtstart),1,dobyr);
	dob_max=mdy(month(dtend),dob_day_max,dobyr);
	format dob_min dob_max yymmddd10.;
	logicgroup=5;

run;

*Remove all the duplicates;
proc sort data=LG5_prelim nodup; 
	by enrolid dob_min; 
run;
*Check counts;
/*proc sql;*/
/*	select count(distinct ENROLID) as COUNT_IDS from LG5_prelim where logicgroup=5; 		*70790;*/
/*	select count(*) as COUNT_IDS from LG5_prelim where logicgroup=5; 						*71006;*/
/*	quit;*/

*breakout duplicates;
*CDL: MODIFIED - Same as below but shorter code;
proc sort data=LG5_prelim out=LG5ids (keep=enrolid);
	by enrolid;
run;
/*data LG5ids (keep=enrolid);*/
/*	set LG5_prelim;*/
/*run;*/
/*proc sort data=LG5ids; */
/*	by enrolid;*/
/*run;*/
*Check counts;
/*proc sql;*/
/*	select count(distinct ENROLID) as COUNT_IDS from LG5ids; 								*70790;*/
/*	select count(*) as COUNT_IDS from LG5ids; 												*71006;*/
/*	quit;*/

*Separate those that only appear once from those with more than 1 record;
data LG5singles LG5dupes;
set LG5ids;
	by enrolid;
	
	if first.enrolid and last.enrolid then output LG5singles;
		else output LG5dupes;
run;
*Check counts;
/*proc sql;*/
/*	select count(distinct ENROLID) as COUNT_IDS from LG5singles; 							*70574;*/
/*	select count(*) as COUNT_IDS from LG5singles; 											*70574;*/
/*	select count(distinct ENROLID) as COUNT_IDS from LG5dupes; 								*216;*/
/*	select count(*) as COUNT_IDS from LG5dupes; 											*432;*/
/*	quit;*/

*Identify the logic group 5 infants;
proc sql;
	create table LG5 as 
	select a.* /*, b.**/
	from LG5_prelim as a 
	inner join LG5singles as b on 
	(a.enrolid=b.enrolid);
	quit;

*Create the input dataset for logic group 0; 
proc sql;
	create table LG0_input
	as select * from LG5_input
	where enrolid not in (select enrolid from LG5);
	quit;

*10.28.2024 UPDATE: REMOVED LOGIC GROUP 6;
/*proc sql;*/
/*	create table LG6_input*/
/*	as select * from LG5_input*/
/*	where enrolid not in (select enrolid from LG5);*/
/*	quit;*/
/**/
/**LOGIC GROUP = 6: 11 continous months where AGE=0 */
/************************************************************************************;*/
/**/
/**Identify those individuals that meet the criteria for logic group 6;*/
/*data temp6;*/
/*set LG6_input;*/
/*	if age=0 and ceseg=1 and ageseg_n=11 then logicgroup=6;*/
/*	if logicgroup=6 then output;*/
/*run;*/
/**/
/**/
/*/*CDL: NOTE -- THIS IS CURRENTLY NOT RIGHT. DIDNT COME BACK, GOING TO CHAT WITH LIZ FIRST.*/*/
/**/
/*/*Intended logic:*/
/*	One NEARLY FULL age-year (i.e., same age for an 11 month continuos span) segment where AGE=0.*/
/*	This is the only group that gets a 90 day rather than a 30 day window.*/
/*	We roll-up the DOBYR for DOB_MAX only if we cross from Dec to Jan.*/*/
/**/
/**Estimate DOB_MIN and DOB_MAX - use 90-day window;*/
/*data LG6 (keep=enrolid logicgroup dobyr dob_min dob_max);*/
/*set temp6;*/
/*	month_min=month(dtstart);*/
/*	if month(dtstart) in (1,2,3,4,5,6,7,8,9,10) then month_max= (month(dtstart)+2);*/
/*		else if month(dtstart) in (11,12) then month_max = (month(dtstart)-10); *For Nov and Dec, Max month is Jan or Feb of the next DOBYR;*/
/*	if month(dtstart) in (1,2,3,4,5,6,7,8,9,10) then dobyr_max = dobyr;*/
/*		else if month(dtstart) in (11,12) then dobyr_max = (dobyr+1); *CDL: ADDED else - also 2 lines above.;*/
/*	if dobyr_max in (1996, 2000, 2004, 2008, 2012, 2016, 2020) and month_max=2 then dob_day_max=29;*/
/*		else if dobyr_max not in (1996, 2000, 2004, 2008, 2012, 2016, 2020) and month_max=2 then dob_day_max=28; *CDL: ADDED else;*/
/*		else if month_max in (1, 3, 5, 7, 8, 10, 12) then dob_day_max=31; *CDL: ADDED else;*/
/*		else if month_max in (4, 6, 9, 11) then dob_day_max=30; *CDL: ADDED else;*/
/*	dob_min=mdy(month_min,1,dobyr);*/
/*	dob_max=mdy(month_max,dob_day_max,dobyr_max);*/
/*	format dob_min dob_max yymmddd10.;*/
/*run;*/
/**/
/**Check counts;*/
/*/*proc sql;*/*/
/*/*	select count(distinct ENROLID) as COUNT_IDS from LG6 where logicgroup=6; 			*/*/
/*/*	select count(*) as COUNT_IDS from LG6 where logicgroup=6; 							*/*/
/*/*	quit;*/*/


*Dont fall into any other category (LOGIC GROUP = 0)
***********************************************************************************;
%PUT IDENTIFY LOGIC GROUP 0;

proc sql;
	create table LG0
	as select * from LG0_input /*LG6_input*/
	where enrolid not in (select enrolid from LG5 /*LG6*/);
	quit;
data LG0 (keep=enrolid dob_min dob_max logicgroup);
set LG0;
 	logicgroup=0;
	dob_min=.;
	dob_max=.;
run;
proc sort data=LG0 nodup;
	by enrolid; 
run;

/**Check counts;*/
/*proc sql;*/
/*	select count(distinct ENROLID) as COUNT_IDS from LG0; 							***233196*** (25.3% of rec);*/
/*	quit;*/




*Merge the datasets with each other;
data LG_all;
set LG0 LG1 LG2 LG3 LG4 LG5; * LG6;
	if dob_min=. then dob_min=mdy(month(dob_max),1,year(dob_max));
run;

proc sort data=LG_all; 
	by enrolid logicgroup; 
run;














/***************************************************************************************************************

									05 - GET FIRST CLAIM FOR INFANTS

Note: I only focused on outpatient and inpatient services claims, not meds. In large part, this was because the
only codes we used to identify pregnancy markers were CPT, DRG, HCPCS, and ICD-9/10 Dx and Pr codes.

NOTE: This code does NOT currently capture DRG codes (10.28.2024). CDL is going to work with Virginia Pate
to determine the most efficient way to collect these.

All dx and pr codes are stacked from every inpatient admission, inpatient service, and outpatient service claim.
Datasets are created for each year of MarketScan data received. Files derived by Virginia Pate as part of UNC
role.

***************************************************************************************************************/


*Get the first claim for an infant in ;
%macro first_claim();

	/*Calculate the number of years*/
	%let numYr = %sysfunc(countw(&years));

	%do d=1 %to &numYr;

		%let loop&d = %scan(&years, &d);

		%if &d = 1 %then %do;

			proc sql;
            %IF &&loop&d in (2015 2016) %THEN %DO;
   				create table firstclaimdt as
   				select enrolid, min(svcdate) as svcdate
   				from (select enrolid, svcdate from der.alldx9&&loop&d  where enrolid in (select enrolid from LG_all)
                     union all corresponding 
                     select enrolid, svcdate from der.alldx10&&loop&d  where enrolid in (select enrolid from LG_all))   				
   				group by enrolid
   				;
            %END;
            %ELSE %DO;
         		create table firstclaimdt as
   				select enrolid, min(svcdate) as svcdate
   				from der.alldx&&loop&d
   				where enrolid in (select enrolid from LG_all)
   				group by enrolid
   				;
            %END;

				insert into firstclaimdt
				select enrolid, min(svcdate) as svcdate
				from der.allproc&&loop&d
				where enrolid in (select enrolid from LG_all)
				group by enrolid
				;

				/*CDL: 10.28.2024 -- Add outpatient medication claims*/
/*				insert into firstclaimdt*/
/*				select enrolid, min(svcdate) as svcdate*/
/*				from raw.outptdrug&&loop&d*/
/*				where enrolid in (select enrolid from LG_all)*/
/*				group by enrolid*/
/*				;*/

				quit;

		%end;

		%else %if &d ne 1 %then %do;

			proc sql;
            %IF &&loop&d in (2015 2016) %THEN %DO;
					insert into firstclaimdt
					select enrolid, min(svcdate) as svcdate
   				from (select enrolid, svcdate from der.alldx9&&loop&d  where enrolid in (select enrolid from LG_all)
                     union all corresponding 
                     select enrolid, svcdate from der.alldx10&&loop&d  where enrolid in (select enrolid from LG_all))   				
					group by enrolid
					;
				%END; %ELSE %DO;
					insert into firstclaimdt
					select enrolid, min(svcdate) as svcdate
					from der.alldx&&loop&d
					where enrolid in (select enrolid from LG_all)
					group by enrolid
					;
				%END;
				insert into firstclaimdt
				select enrolid, min(svcdate) as svcdate
				from der.allproc&&loop&d
				where enrolid in (select enrolid from LG_all)
				group by enrolid
				;

				/*CDL: 10.28.2024 -- Add outpatient medication claims*/
/*				insert into firstclaimdt*/
/*				select enrolid, min(svcdate) as svcdate*/
/*				from raw.outptdrug&&loop&d*/
/*				where enrolid in (select enrolid from LG_all)*/
/*				group by enrolid*/
/*				;*/

				quit;

		%end;

	%end;

%mend;

%first_claim();


*Now take the first row of the dataset to get each persons actual
first claim date;
proc sort data=firstclaimdt;
	by enrolid svcdate;
run;
data firstclaimdt2;
set firstclaimdt;
	by enrolid svcdate;

	if first.enrolid then output;

	format svcdate yymmddd10.;
run;


/*Grab all the pregnancy-related codes*/

*Create the code dataset;
data codes;
length code $17; *CDL: Added;
format code $17.; *CDL: Added;
set covref.delivery covref.ga (rename = (codecat=code_version)) covref.preg_markers; *CDL: ADDED rename here;

	if alg in ("LB","LBSB","UNK") then delivery=1;
		else delivery = 0;

	where code ne "";
run;

*Now group by code and code_version;
proc sql;
	create table pregnancy_codes as
	select code, code_version, max(delivery) as delivery
	from codes
	group by code, code_version
	;
	quit;

/*data pregnancy_codes_test; *UPDATE 1.16.2026: LS, re-wrote sql step below to circumvent error;*/
/*	length code $17; *CDL: Added;*/
/*	format code $17.; *CDL: Added;*/
/*	set covref.delivery covref.ga (rename = (codecat=code_version)) covref.preg_markers; *CDL: ADDED rename here;*/
/*	*/
/*	where code ne " ";*/
/*	*/
/*	if alg in ("LB","LBSB","UNK") then delivery=1;*/
/*		else delivery=0;*/
/*	*/
/*run;*/
/*old code that produces error: Ambiguous reference, column code_version is in more than one table.*/
/* proc sql; */
/* 	create table pregnancy_codes as */
/* 	select code, code_version, max(delivery) as delivery */
/* 	from (select code, code_version, case */
/* 										when alg IN ("LB","LBSB","UNK") then 1 */
/* 										else 0 */
/* 										end as delivery */
/* 			from covref.delivery */
/* 			union */
/* 			select code, codecat as code_version, 0 as delivery */
/* 			from covref.ga */
/* 			union */
/* 			select code, code_version, 0 as delivery */
/* 			from covref.preg_markers) */
/* 	where code ne "" */
/* 	group by code, code_version */
/* 	; */
/* 	quit; */
	;;
	
/*Subset the reference pregnancy outcome file to only deliveries*/
/*data delivery_codes;*/
/*set covref.delivery;*/
/*	where alg IN ("LB","LBSB","UNK");*/
/*run;*/


/*Subset the derived files with all DX & PR codes to only those only the first
service date

NOTE: This is NOT robust to starting in 2015 or 2016 becuase those
derived files for dx codes are split by ICD9 and 10. Assuming that this
code starts before then.*/

%macro first_dx_pr();

	/*Calculate the number of years*/
	%let numYr = %sysfunc(countw(&years));

	%do d=1 %to &numYr;

		%let loop&d = %scan(&years, &d);

		%if &d = 1 %then %do;

			proc sql;
				
					/*First, identify the diagnosis coes*/
					create table infant_del_codes as
					select b.enrolid, b.svcdate, b.tsvcdat, b.dx&&loop&d as code length=20, b.dxNum as code_position,
						   b.dxloc as location, c.code_version, c.delivery
					from firstclaimdt2 as a
					inner join der.alldx&&loop&d as b
					on a.enrolid = b.enrolid and a.svcdate = b.svcdate
					inner join pregnancy_codes as c
					on b.dx&&loop&d = c.code
					;

					/*Identify the procedure codes*/
					insert into infant_del_codes
					select b.enrolid, b.svcdate, b.tsvcdat, b.proc&&loop&d as code length=20, b.procNum as code_position,
						b.procLoc as location, c.code_version, c.delivery
					from firstclaimdt2 as a
					inner join der.allproc&&loop&d as b
					on a.enrolid = b.enrolid and a.svcdate = b.svcdate
					inner join pregnancy_codes as c
					on b.proc&&loop&d = c.code
					;

				quit;

		%end;

		%else %if &d ne 1 %then %do;


			proc sql;

				%if &&loop&d = 2015 or &&loop&d = 2016 %then %do;

					/*First, identify the diagnosis coes*/
					insert into infant_del_codes
					select b.enrolid, b.svcdate, b.tsvcdat, b.dx&&loop&d as code length=20, b.dxNum as code_position,
						   b.dxloc as location, c.code_version, c.delivery
					from firstclaimdt2 as a
					inner join der.alldx9&&loop&d as b
					on a.enrolid = b.enrolid and a.svcdate = b.svcdate
					inner join pregnancy_codes as c
					on b.dx&&loop&d = c.code
					;

					/*First, identify the diagnosis coes*/
					insert into infant_del_codes
					select b.enrolid, b.svcdate, b.tsvcdat, b.dx&&loop&d as code length=20, b.dxNum as code_position,
						   b.dxloc as location, c.code_version, c.delivery
					from firstclaimdt2 as a
					inner join der.alldx10&&loop&d as b
					on a.enrolid = b.enrolid and a.svcdate = b.svcdate
					inner join pregnancy_codes as c
					on b.dx&&loop&d = c.code
					;

				%end;

				%else %do;
				
					/*First, identify the diagnosis coes*/
					insert into infant_del_codes
					select b.enrolid, b.svcdate, b.tsvcdat, b.dx&&loop&d as code length=20, b.dxNum as code_position,
						   b.dxloc as location, c.code_version, c.delivery
					from firstclaimdt2 as a
					inner join der.alldx&&loop&d as b
					on a.enrolid = b.enrolid and a.svcdate = b.svcdate
					inner join pregnancy_codes as c
					on b.dx&&loop&d = c.code
					;

				%end;

				/*Identify the procedure codes*/
				insert into infant_del_codes
				select b.enrolid, b.svcdate, b.tsvcdat, b.proc&&loop&d as code length=20, b.procNum as code_position,
						b.procLoc as location, c.code_version, c.delivery
				from firstclaimdt2 as a
				inner join der.allproc&&loop&d as b
				on a.enrolid = b.enrolid and a.svcdate = b.svcdate
				inner join pregnancy_codes as c
				on b.proc&&loop&d = c.code
					;	

				quit;

		%end;

	%end;

%mend;

%first_dx_pr();

/*Save the dataset in case we want to look at these delivery-related codes on 
infant-s first claims later*/
data out.infant_suarez_deliverycodes;
set infant_del_codes;
	pgclaim = 1;
	if delivery = 1 then delclaim = 1;
		else delclaim = 0;
run;


/*Create a flag for every infant that has at least 1 delivery code on their
first claim*/
data infant_del_codes;
set infant_del_codes;
	pgclaim = 1;
	if delivery = 1 then delclaim = 1;
		else delclaim = 0;
run;

/*proc contents data=infant_del_codes; run;*/

/*Merge that flag onto the dataset*/
proc sql;
	create table infants as
	select a.*, case when b.pgclaim = 1 then 1 else 0 end as pgclaim, 
				case when b.delclaim = 1 then 1 else 0 end as delclaim
	from lg_all as a
	left join (select enrolid, max(pgclaim) as pgclaim, max(delclaim) as delclaim
				from infant_del_codes
				group by enrolid) as b
	on a.enrolid = b.enrolid
	;
	quit;










/***************************************************************************************************************

									06 - OUTPUT INFANT DATASET

***************************************************************************************************************/

*Checks;
/*proc freq data=LG_all; */
/*	table dobyr / missing;  */
/*run;*/
/*proc sql;*/
/*	select count(distinct ENROLID) as COUNT_IDS from LG_all; 								*/
/*	select count(*) as COUNT_IDS from LG_all; 												*/
/*	quit;*/

*Check that all infants from beginning accounted for;
/*proc sql;*/
/*	select count(distinct enrolid) as n_ppl_lg from LG_all;*/
/*	select count(distinct enrolid) as n_ppl_ids from infant_ids_distinct;*/
/*	select sum(logicgroup = .) as n_missing_lg from LG_all;*/
/*	quit;*/

*Check that only one record per person in the first_cont_enrl file - Good;
/*proc sql;*/
/*	select count (distinct enrolid) as distinctenrolid,*/
/*			count(enrolid) as enrolid*/
/*	from first_cont_enrl  */
/*	;*/
/*	quit;*/


proc sql;
	create table infant_suarez as
	select a.*, b.ce_start, b.ce_end, c.svcdate
	from infants (drop = month) as a
	left join first_cont_enrl as b
	on a.enrolid = b.enrolid
	left join firstclaimdt2 as c
	on a.enrolid = c.enrolid
	;
	quit;

/*Output final infant dataset*/
data out.infant_suarez;
set infant_suarez ;

	EFAMID = substr(ENROLID,1,length(ENROLID)-2);

run;

proc freq data=infant_suarez;
	table pgclaim*delclaim / missing;
run;

/*Check counts*/
/*proc sql;*/
/*	select count(distinct enrolid) as distinct_n from infant_suarez;*/
/*	select count(enrolid) as n from infant_suarez;*/
/*	quit;*/
