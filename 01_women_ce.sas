/********************************************************************************************************************************************
Program Name: 01_women_ce.sas
Goal: To create a dataset of continuous enrollment for pregnant women.

Input:	Enrollment data for random 1% sample (enrdet2000 enrdet2001 enrdet2002 enrdet2003 enrdet2004 enrdet2005
	 enrdet2006 enrdet2007 enrdet2008 enrdet2009 enrdet2010 enrdet2011 enrdet2012
	enrdet2013 enrdet2014 enrdet2015 enrdet2016 enrdet2017 enrdet2018 enrdet2019
	enrdet2020 enrdet2021 enrdet2022 enrdet2023)

Macros: 	

Output: out.elig_woman - dataset with enrollment information for eligible women
		out.ce_woman - dataset that includes women with continuous enrollment

Programmer: Lizzy Simmons (LS)
Date: October 25, 2024

Modifications:
	January 13, 2025: cleaned up comments, etc.
	April 1, 2025: updated to include year 2023
********************************************************************************************************************************************/









/***************************************************************************************************************

TABLE OF CONTENTS:
	- 00 - SET LIBRARIES
	- 01 - Create a long file with all monthly enrollment information
	- 02 - Compile continuous enrollment information
***************************************************************************************************************/










/***************************************************************************************************************

											00 - SET LIBRARIES

***************************************************************************************************************/


/*run this locally if you need to log onto the N2 server.*/
/*SIGNOFF;*/
/*%LET server=n2.schsr.unc.edu 1234; */
/*options comamid=tcp remote=server;*/
/*signon username=_prompt_;*/

*Run setup macro and define libnames;
options sasautos=(SASAUTOS "/local/projects/marketscan_preg/raw_data/programs/macros");
/*change "saveLog=" to "Y" when program is closer to complete*/
%setup(sample= 1pct, programname=ailes_suarez_modification/01_women_ce, savelog=N)

options mprint;


*Create a distinct library defined as in&yr for each of the years of input data. Each one points
to the same location. This reflects how data were stored in Rutgers servers: each year was separate whereas
UNC stores all data in one folder with year in the file name.;
%macro assign_lib(sample);
   %DO yr=2000 %TO 2023; libname in&yr "/local/data/master/marketscanccae/&sample/ccae"; %END;
%mend;
%assign_lib(random1pct)


*LIST OF ALL DATA INPUTS;
*Create global variables with all of the library names as assigned in assign_lib and the file names for the monthly enrollment files.;
%let libnames_t = in2000 in2001 in2002 in2003 in2004 
	in2005 in2006 in2007 in2008 in2009 in2010 in2011 in2012 in2013 in2014 in2015 
	in2016 in2017 in2018 in2019 in2020 in2021 in2022 in2023;
%let file_t = enrdet2000 enrdet2001 enrdet2002 enrdet2003 enrdet2004 enrdet2005
	 enrdet2006 enrdet2007 enrdet2008 enrdet2009 enrdet2010 enrdet2011 enrdet2012
	enrdet2013 enrdet2014 enrdet2015 enrdet2016 enrdet2017 enrdet2018 enrdet2019
	enrdet2020 enrdet2021 enrdet2022 enrdet2023;


**************************************************
* Clear Work Library
*************************************************;
proc datasets library=work kill;
run;

quit;









/***************************************************************************************************************

							01 - Create a long file with all monthly enrollment information

***************************************************************************************************************/


/*
MACRO: drug
PURPOSE: To create one long file with all monthly enrollment information across all of the study years.

INPUT:
- name - name of the output data file with the list of eligible females. Default = elig_woman
- lib - list of library names where the enrollment data is stored. Input later: &libnames_t
- dat - list of the data files with the monthly enrollment data (in lib). Input later: &file_t.
*/

%macro drug (name = elig_woman, lib = , dat = );

	%*Create a temporary (work lib) dataset for each monthly enrollment file for each year. Subset to those with non-missing enrolid
	values and where sex is female.;
	%do j=1 %to %sysfunc(countw(&libnames_t));
		%let next_lib = %scan(&libnames_t,&j);
		%let next_dat = %scan(&dat,&j);

		data dat&j;
			set &next_lib..&next_dat (keep= DOBYR DTEND DTSTART ENROLID SEX where=(SEX='2' and ENROLID ne .));
			YEAR=YEAR(DTSTART);
			EFAMID=substr(ENROLID,1,length(ENROLID)-2); %*Family ID;
		run;

	%end;

	%*combine and dedup by date;

	%*Count the number of libraries as a proxy for the number of files and years;
	%let num=%sysfunc(countw(&libnames_t));
	%*Stack all of the enrollment files from each year;
	data &name;
		set dat1-dat&num;
	run;
	%*Ensure no duplicates and sort by enrolid;
	proc sort data=&name out=out.&name nodup;
		by enrolid;
	run;
	%*Delete the working datasets that are no longer necessary;
	proc datasets library=work;
		delete dat1-dat&num;
	run;

	*check counts;
	proc sql;
		select count(distinct ENROLID) as COUNT_UNIQUE from out.&name;

		*10,764,401;
		select count(*) as COUNT_ALL from out.&name;

		*3.6992E8;
		quit;

%mend drug;


*Now, create the stacked enrollment datasets;
%drug(elig_woman,&libnames_t,&file_t);









/***************************************************************************************************************

							02 - Compile continuous enrollment information

***************************************************************************************************************/


*Continuous Eligibility;

%*Sort by monthly enrollment start date (each row is a month, eg, Jan, Feb) and then output a dataset with an indicator
for continuous enrollment segments, allowing for a 31-day grace period.;
proc sort data=elig_woman nodup;
	by ENROLID DTSTART;
run;
data out.elig_woman;
	set elig_woman;
	by enrolid;
	retain EnrSeg;
	lag=dtstart-lag(dtend);

	if first.enrolid then EnrSeg=1;
		else if lag>31 then EnrSeg=EnrSeg+1;
run;


*Create an output dataset with the continuous enrollment segments.;
proc sql;
	create table out.ce_woman as 
	select ENROLID, min(DTSTART) as CE_START, max(DTEND) as CE_END, EnrSeg 
	from out.elig_woman 
	group by ENROLID, EnrSeg
	;
	quit;
*Derive years for start and end;
data out.ce_woman;
	set out.ce_woman;
	YRSTART=YEAR(CE_START);
	YREND=YEAR(CE_END);
	format ce_start ce_end date9.;
run;

*check counts;
proc sql;
	select count(distinct ENROLID) as COUNT_UNIQUE_CE from out.ce_woman;
	select count(*) as COUNT_ALL_CE from out.ce_woman;
	quit;

*check enrseg logic;
proc sql;
	select count(distinct ENROLID) as CHECK_ENRSEG from out.ce_woman where enrseg=.;
	select count(distinct ENROLID) as CHECK_ENRSEG from out.ce_woman where enrseg=1;
	select count(distinct ENROLID) as CHECK_ENRSEG from out.ce_woman where enrseg>1;
	quit;
