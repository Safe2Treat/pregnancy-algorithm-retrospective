
/********************************************************************************************************************************************
Program Name: 03_preg_person_cohort.sas
Goal: To create a cohort of people who experienced a pregnancy outcome for Liz Suarez adaptation of the Ailes et al. 2023 pregnancy 
identification algorithm.

Input: MarketScan inpatient summary, inpatient services, enrollment, and outpatient datasets
		covref.delivery
		covref.ga
		covref.preg_markers

Macros: 	

Output: out.preg_person_suarez

Programmer: Oluwasolape Olawore (OO)
Date: May 2024 

Modifications:
- CDL: updated and cleaned comments, etc.
- Chase Latour (CDL) reviewed the code created by OO.
- 04.01.2025 - added MS year 2023 (LS)

********************************************************************************************************************************************/









/***************************************************************************************************************

TABLE OF CONTENTS:
	- 00 - SET LIBRARIES
	- 01 - IDENTIFY ELIGIBLE FEMALES
	- 02 - PREP THE CODE REFERENCE FILES
	- 03 - GET INPATIENT CLAIMS
	- 04 - GET OUTPATIENT CLAIMS
	- 05 - COMBINE THE DATASETS
	- 06 - OLD CODE

***************************************************************************************************************/













/***************************************************************************************************************

											00 - SET LIBRARIES

***************************************************************************************************************/


/*run this locally if you need to log onto the N2 server.*/
/*SIGNOFF;
%LET server=n2.schsr.unc.edu 1234; 
options comamid=tcp remote=server; 
signon username=_prompt_;*/

*Run setup macro and define libnames;
options sasautos=(SASAUTOS "/local/projects/marketscan_preg/raw_data/programs/macros");
/*change "saveLog=" to "Y" when program is closer to complete*/
%setup(sample=full, programname=ailes_suarez_modification/03_preg_person_cohort, savelog=Y)

/*Create local mirrors of the server libraries*/
/*libname lout slibref=out server=server;*/
/*libname lwork slibref = work server = server;*/
/*libname lcovref slibref = covref server = server;*/
/*libname lder slibref = der server=server;*/
/*libname lraw slibref = raw server=server;*/

*Set global macro variables.;
%let yearstart=2000; /*First year we look at -- CDL: ADDED*/
%let yearend=2023; /*the final year of the dataset*/
%let abbrevyr_2000 = 2000; 
%let abbrevyr_2001 = 2001; 
%let abbrevyr_2002 = 2002; 
%let abbrevyr_2003 = 2003; 
%let abbrevyr_2004 = 2004; 
%let abbrevyr_2005 = 2005; 
%let abbrevyr_2006 = 2006; 
%let abbrevyr_2007 = 2007;
%let abbrevyr_2008 = 2008; 
%let abbrevyr_2009 = 2009; 
%let abbrevyr_2010 = 2010;   
%let abbrevyr_2011 = 2011; 
%let abbrevyr_2012 = 2012; 
%let abbrevyr_2013 = 2013; 
%let abbrevyr_2014 = 2014; 
%let abbrevyr_2015 = 2015;
%let abbrevyr_2016 = 2016;
%let abbrevyr_2017 = 2017;
%let abbrevyr_2018 = 2018;
%let abbrevyr_2019 = 2019;
%let abbrevyr_2020 = 2020;
%let abbrevyr_2021 = 2021;
%let abbrevyr_2022 = 2022;
%let abbrevyr_2023 = 2023;
****This step is just to estimate the number of women, does not really contribute much to code; 






/***************************************************************************************************************

										01 - IDENTIFY ELIGIBLE FEMALES

***************************************************************************************************************/



*Step 1 -Find Women 12-55 from the inpatient summary, inpatient services, enrollment, and outpatient dataset.
These are individuals with claims;

*Create an empty dataset where the necessary information will be stored.;
proc sql; 
	create table women
	(enrolid num format=best12.,
	 age num  format=best12.,
	 sex char format $1.,
	 f num  format = best12.);
	quit;



/*
MACRO: findwomen
PURPOSE: This macro creates a dataset (working directory) called women, which contains 1 row for each female with 
at least 1 claim across inpatient admissions, inpatient services, outpatient services, and outpatient precription fills.

INPUT: none.
*/
%macro findwomen; 

	%*Specify the input data types;
	%let datalist= Inptadm Inptserv Outptserv Outptdrug /*Enrdet*/;
 
	%*Look at each dataset and create a dataset with all women with at least 1 claim.;
	%do i_d = 1 %to %sysfunc(countw(&datalist));

		%let d = %scan(&datalist, &i_d);

		%do yr = &yearstart %to &yearend; 

			%*Get the raw claims data from each of the inpatient admission, inpatient service, outpatient service, and
			outpatient drug datasets. We are interested in identifying all people with claims in that period;
			data women_sub; ;
				set raw.&d.&&abbrevyr_&yr(keep=enrolid age sex  where=(enrolid ne . and sex='2' and age >= 12 & age <= 55 )); 
			run;

			proc sort data=women_sub; 
				by enrolid; 
			run;
			%*Retain only the first record;
			data women_sub(where=(f=1)); 
				set women_sub; 
				by enrolid; 
				if first.enrolid then f=1; 
			run;
			%*Add the data to the empty dataset created earlier.;
			proc append base = women data = women_sub ; run ;

		%end; 

	%end;

	%*Further restrict to only one record per woman;
	proc sort data=women; by enrolid age; run;
	data women (Where=(f=1));
		set women(drop=f); 
		by enrolid; 
		if first.enrolid then f=1; 
	run;

	title 'Number of Unique Women Ages 12-55 in all years of the dataset';
	proc freq data= women; 
		tables f / missing; 
	run;
	title;

	*Drop the f indicator variable;
	data women; 
	set women (drop=f); 
	run;
%mend; 


%findwomen; run; quit; run;












/***************************************************************************************************************

									02 - PREP THE CODE REFERENCE FILES

***************************************************************************************************************/

*Consider the codelists and make sure to subset to only those rows with a non-missing code value. Simple cleaning step.;

*had ICDCM, ICDPCS, HCPCS, CPT, and DRG;
data delivery;
set covref.delivery;
if code ne ""; 
run;

**only has icd CM, cpt and hcpcs codes; 
data gestation;
set covref.ga;
if code ne ""; 
rename codecat = code_version;
run; 

*pregnancy markers
*has ICDCM, ICDPCS, HCPCS, CPT, and DRG;
data pregmark;
set covref.preg_markers;
if code ne "";
keep code code_version fulldescription;
run;


options mprint;



*OUTPUT DIAGNOSIS AND PROCEDURE CODES TO TEMPORARY DATA TO HELP DATA STEP BELOW;	

proc sql;

	/*Get all delivery codes*/
	select distinct code into :delivery_dx9 separated by '", "' from delivery where code_version="ICD9CM";
	select distinct code into :delivery_dx10 separated by '", "' from delivery where code_version="ICD10CM";
	select distinct code into :delivery_prc9 separated by '", "' from delivery where code_version="ICD9PCS";
	select distinct code into :delivery_prc10 separated by '", "' from delivery where code_version="ICD10PCS";
	select distinct code into :delivery_cpt separated by '", "' from delivery where code_version in ('CPT' 'HCPCS');
	select distinct code into :delivery_drg separated by '", "' from delivery where code_version='DRG';

	/*Get all gestational age codes*/
	select distinct code into :gestation_dx9 separated by '", "' from gestation where code_version='ICD9CM'; 
	select distinct code into :gestation_dx10 separated by '", "' from gestation where code_version='ICD10CM'; 
	select distinct code into :gestation_cpt separated by '", "' from gestation where code_version in ('CPT' 'HCPCS');

	/*Get all pregnancy marker codes*/
	select distinct code into :pregmark_dx9 separated by '", "' from pregmark where code_version="ICD9CM";
	select distinct code into :pregmark_dx10 separated by '", "' from pregmark where code_version="ICD10CM";
	select distinct code into :pregmark_prc9 separated by '", "' from pregmark where code_version="ICD9PCS";
	select distinct code into :pregmark_prc10 separated by '", "' from pregmark where code_version="ICD10PCS";
	select distinct code into :pregmark_cpt separated by '", "' from pregmark where code_version in ('CPT' 'HCPCS');
	select distinct code into :pregmark_drg separated by '", "' from pregmark where code_version='DRG';

	quit;

/**Double check code_version in output datasets;*/
/**/
/*proc freq data = delivery;*/
/*tables code_version;*/
/*run; */
/**/
/*proc freq data = gestation;*/
/*tables code_version;*/
/*run; */
/**/
/*proc freq data = pregmark;*/
/*tables code_version;*/
/*run; */








/***************************************************************************************************************

										 03 - GET INPATIENT CLAIMS

***************************************************************************************************************/


*6/5/2024 - update in inptadm macro to use datastep instead of PROC SQL;

/*
MACRO: inptadm
PURPOSE: To get files for inpatient admission including procedure codes, diagnosis codes and drg codes.

INPUT:
- startYr: first year of claims. Default=2000.
- endYr: last year of claims. Default=2023.
*/

 
%macro inptadm (startYr = 2000 , endYr = 2023);

	%*Create 3 datasets: women_inptadmdx, women_inptadmproc, women_inptadmDRG;
	data women_inptadmdx(keep=enrolid age code codecat svcdate prin_dx ga mrk dlv setting) 
		 women_inptadmproc(keep=enrolid age code codecat svcdate prin_proc ga mrk dlv setting)
		 women_inptadmDRG(keep=enrolid age code codecat svcdate ga mrk dlv setting);
	%*Stack the raw claims files for each year. Retain only the relevant variables.;
	set %DO yr=&endYr %TO &startYr %BY -1; raw.inptadm&yr(where=(12<=age<=55 and sex='2') keep=enrolid age sex admdate pdx dx: pproc proc: drg %IF &yr>2014 %THEN drop=dxver; ) %END;;
		length codecat code $15;

		%*Create arrays to look through the diagnosis and procedure columns for each claim (multiple columns per claim);
		array dx(*) pdx dx:;
		array prc(*) pproc proc:;

		%*Pull in the DRG codes from the inpatient admission claims;
		if drg in ("&delivery_drg" "&pregmark_drg") then do;
			code = put(drg,3.0); 
			setting = "I";
			if drg in ("&delivery_drg") then dlv = 1; else dlv =0;
			if drg in ("&pregmark_drg") then mrk = 1; else mrk = 0;
			ga = 0;
		    codecat = "DRG";
			output women_inptadmdrg;
		end;

		%*Look through the columns for diagnosis codes;
		codecat = ""; %*Reset to missing;
		do d=1 to dim(dx); 
			if dx(d) in ("&delivery_dx9" "&delivery_dx10" "&gestation_dx9" "&gestation_dx10" "&pregmark_dx9" "&pregmark_dx10") then do;
				code=dx(d);
				if d=1 then prin_dx=1; else prin_dx=0;

				if dx(d) in ("&gestation_dx9" "&gestation_dx10") then ga=1; else ga=0;
				if dx(d) in ("&delivery_dx9" "&delivery_dx10") then dlv = 1; else dlv = 0;
				if dx(d) in ("&pregmark_dx9" "&pregmark_dx10") then mrk = 1; else mrk = 0;
				if dx(d) in ("&delivery_dx9" "&gestation_dx9" "&pregmark_dx9") THEN codecat='ICD9CM';  ELSE codecat='ICD10CM';
				setting = "I";
				output women_inptadmdx;
			end;
		end;

		%*Look through the procedure code columns to get all the relevant codes.;
		Codecat=" "; %*Reset to missing;
		do p=1 to dim(prc); 
			if prc(p) in ("&delivery_prc9" "&delivery_prc10" "&delivery_cpt" "&pregmark_prc9" "&pregmark_prc10" "&pregmark_cpt" "&gestation_cpt") then do;
				code=prc(p);
				if p=1 then prin_proc=1; else prin_proc=0;

				if prc(p) in ("&gestation_cpt") then ga=1; else ga=0;
				if prc(p) in ("&delivery_prc9" "&delivery_prc10" "&delivery_cpt") then dlv = 1; else dlv = 0;
				if prc(p) in ("&pregmark_prc9" "&pregmark_prc10" "&pregmark_cpt") then mrk = 1; else mrk = 0;

			if prc(p) in ("&delivery_prc9" "&pregmark_prc9") THEN codecat='ICD9PRC';  ELSE if prc(p) in ("&delivery_prc10" "&pregmark_prc10") then codecat='ICD10PRC';
					else if prc(p) in ("&delivery_cpt" "&gestation_cpt" "&pregmark_cpt") then codecat='CPT';
					setting = "I";
				output women_inptadmproc;
			end;
		end;
		codecat = ""; %*Reset to missing;

		rename admdate=svcdate; 
		format admdate date9.;
	run;

	proc datasets lib=work nolist nodetails; 
		delete women_inptadmdx1_:; 
	run; quit; run;
%mend; 

*Now, run the macro.;
options mprint;
%inptadm()

*Left join the gestational and delivery code lists onto the diagnosis codes from the inpatient admission claims;
proc sql;
	create table women_inptadmdx2 
	as select a.*, 
		case when a.ga=1 then b.prioritygroup1 else . end as prioritygroup1,
		case when a.ga=1 then b.prioritygroup2 else . end as prioritygroup2,
		case when a.ga=1 then b.priority else . end as priority,    
		case when a.ga=1 then b.duration else . end as duration,
		case when a.ga=1 then b.lb else . end as LB, 
		case when a.ga = 1 then b.sb else . end as SB, 
		case when a.ga = 1 then b.lbsb else . end as LBSB, 
		case when a.ga = 1 then b.sab else . end as SAB, 
		case when a.ga = 1 then b.iab else . end as IAB,
		case when a.ga = 1 then b.abn else . end as ABN, 
		case when a.ga=0 then c.alg else '' end as alg
	from  women_inptadmdx as a 
	left join gestation as b 
	on a.code=b.code
	left join delivery as c 
	on a.code=c.code
	;
	quit;

*Left join the delivery and ga code lists onto the inpatient admission procedure codes;
proc sql;
	create table women_inptadmproc2 as 
	select a.*,  
		case when a.ga=1 then b.prioritygroup1 else . end as prioritygroup1,
		case when a.ga=1 then b.prioritygroup2 else . end as prioritygroup2,
		case when a.ga=1 then b.priority else . end as priority,    
		case when a.ga=1 then b.duration else . end as duration,
		case when a.ga=1 then b.lb else . end as LB, 
		case when a.ga = 1 then b.sb else . end as SB, 
		case when a.ga = 1 then b.lbsb else . end as LBSB, 
		case when a.ga = 1 then b.sab else . end as SAB, 
		case when a.ga = 1 then b.iab else . end as IAB,
		case when a.ga = 1 then b.abn else . end as ABN, 
		case when a.ga=0 then c.alg else '' end as alg
	from  women_inptadmproc as a 
	left join gestation as b 
	on a.code=b.code
	left join delivery as c 
	on a.code=c.code
	;
	quit;


*Finally pull in all the DRG information. None for inpatient admissions.;
proc sql;
	create table women_inptadmdrg2 as 
	select a.*, . as prioritygroup1, . as prioritygroup2, . as priority, . as duration, . as LB, 
			. as SB, . as LBSB, . as SAB, . as IAB, . as ABN, c.alg 
	from  women_inptadmdrg as a 
	left join delivery as c 
	on a.code=c.code;
	quit;











/***************************************************************************************************************

										 04 - GET OUTPATIENT CLAIMS

***************************************************************************************************************/


/*
MACRO: outptserv
PURPOSE: To get files for outpatient services claims including procedure codes, diagnosis codes and drg codes.

INPUT:
- startYr: first year of claims. Default=2000.
- endYr: last year of claims. Default=2023.
*/
%macro outptserv(startYr = 2000 , endYr = 2023 );

	%*Create 2 datasets: women_outptservdx, women_outptservproc;
	data women_outptservdx(keep=enrolid age code codecat svcdate prin_dx ga mrk dlv setting) 
		 women_outptservproc(keep=enrolid age code codecat svcdate prin_proc ga mrk dlv setting);
	*Pull in all relevant claims from the raw outpatient services files.;
	set %DO yr=&endYr %TO &startYr %BY -1; raw.outptserv&yr(where=(12<=age<=55 and sex='2') keep=enrolid age sex svcdate dx: proc: %IF &yr>2014 %THEN drop=dxver; drop = PROCGRP procmod proctyp) %END;;
		length codecat code $7;

		%*Create arrays because diagnosis and procedure codes are recorded across multiple columns within 1 row or claim;
		array dx(*) dx:;
		array prc(*) proc:;

		%*Get all of the diagnosis codes from the outpatient services claims.;
		do d=1 to dim(dx); 
			if dx(d) in ("&delivery_dx9" "&delivery_dx10" "&gestation_dx9" "&gestation_dx10" "&pregmark_dx9" "&pregmark_dx10") then do;
				code=dx(d);
				prin_dx=0;
				setting = "O";
				if dx(d) in ("&gestation_dx9" "&gestation_dx10") then ga=1; else ga=0;
				if dx(d) in ("&pregmark_dx9" "&pregmark_dx10") then mrk = 1; else mrk = 0; 
				if dx(d) in ("&delivery_dx9" "&delivery_dx10") then dlv = 1; else dlv = 0; 
			if dx(d) in ("&delivery_dx9" "&gestation_dx9" "&pregmark_dx9") THEN codecat='ICD9CM';  ELSE codecat='ICD10CM';
				output women_outptservdx;
			end;
		end;
		Codecat=" "; %*Reset to missing;

		%*Get all of the procedure codes from the outpatient services claims;
		do p=1 to dim(prc); 
			if prc(p) in ("&delivery_prc9" "&delivery_prc10" "&delivery_cpt" "&pregmark_prc9" "&pregmark_prc10" "&pregmark_cpt" "&gestation_cpt") then do;
				code=prc(p);
				prin_proc=0;
				setting = "O";
			if prc(p) in ("&gestation_cpt") then ga=1; else ga=0;
			if prc(p) in ("&pregmark_prc9" "&pregmark_prc10" "&pregmark_cpt") then mrk = 1; else mrk = 0; 
			if prc(p) in ("&delivery_prc9" "&delivery_prc10" "&delivery_cpt") then dlv = 1; else dlv = 0; 

			if prc(p) in ("&delivery_prc9" "&pregmark_prc9") THEN codecat='ICD9PRC';  ELSE if prc(p) in ("&delivery_prc10" "&pregmark_prc10") THEN codecat='ICD10PRC';
					else if prc(p) in ("&delivery_cpt" "&gestation_cpt" "&pregmark_cpt") then codecat='CPT';
				output women_outptservproc;
			end;
		end;
	
	run;

	proc datasets lib=work nolist nodetails; 
	delete women_outptservdx1_:; 
	run; quit; run;
%mend; 

%*Implement the macro to pull the necessary files.;
options mprint;
%outptserv();


*left join the outcome and gestational age information onto the diagnosis codes.;
proc sql;
	create table women_outptservdx2 as 
	select a.*, 
		case when a.ga=1 then b.prioritygroup1 else . end as prioritygroup1,
		case when a.ga=1 then b.prioritygroup2 else . end as prioritygroup2,
		case when a.ga=1 then b.priority else . end as priority,    
		case when a.ga=1 then b.duration else . end as duration,
		case when a.ga=1 then b.lb else . end as LB, 
		case when a.ga = 1 then b.sb else . end as SB, 
		case when a.ga = 1 then b.lbsb else . end as LBSB, 
		case when a.ga = 1 then b.sab else . end as SAB, 
		case when a.ga = 1 then b.iab else . end as IAB,
		case when a.ga = 1 then b.abn else . end as ABN, 
		case when a.ga=0 then c.alg else '' end as alg
	from women_outptservdx as a 
	left join gestation as b 
	on a.code=b.code
	left join delivery as c 
	on a.code=c.code;
	quit;

*left join the outcome and gestational age information onto the procedure codes.;
proc sql;
	create table women_outptservproc2 as 
	select a.*,  
		case when a.ga=1 then b.prioritygroup1 else . end as prioritygroup1,
		case when a.ga=1 then b.prioritygroup2 else . end as prioritygroup2,
		case when a.ga=1 then b.priority else . end as priority,    
		case when a.ga=1 then b.duration else . end as duration,
		case when a.ga=1 then b.lb else . end as LB, 
		case when a.ga = 1 then b.sb else . end as SB, 
		case when a.ga = 1 then b.lbsb else . end as LBSB, 
		case when a.ga = 1 then b.sab else . end as SAB, 
		case when a.ga = 1 then b.iab else . end as IAB,
		case when a.ga = 1 then b.abn else . end as ABN, 
		case when a.ga=0 then c.alg else '' end as alg
	from  women_outptservproc as a 
	left join gestation as b 
	on a.code=b.code
	left join delivery as c 
	on a.code=c.code;
	quit;








/***************************************************************************************************************

									05 - COMBINE THE DATASETS

COMBINE ALL DATASETS CREATED ABOVE TO GET MASTER DATA WITH ALL POSSIBLE PREGNANT PEOPLE

***************************************************************************************************************/


data out.preg_person_suarez;
set women_inptadmdx2 women_inptadmproc2 women_inptadmdrg2 
	/*women_inptservdx2 women_inptservproc2 women_inptservdrg2*/
	women_outptservdx2 women_outptservproc2;

	efamid = substr(enrolid,1,length(enrolid)-2); *Create family ID;
run; 
***only inpatient admission files required; 






/***************************************************************************************************************

												06 - OLD CODE

***************************************************************************************************************/


**************************************************************************************************************************************
									INPATIENT SERVICES FILES
**************************************************************************************************************************************;
/*%macro inptserv (startYr = 2000 , endYr = 2023 );
	data women_inptservdx(keep=enrolid age code codecat svcdate prin_dx ga setting) 
		 women_inptservproc(keep=enrolid age code codecat svcdate prin_proc ga setting)
		 women_inptservDRG(keep=enrolid age code svcdate ga setting);

		set %DO yr=&endYr %TO &startYr %BY -1; raw.inptserv&yr(where=(12<=age<=55 and sex='2') keep=enrolid age sex svcdate dx: pproc proc: drg %IF &yr>2014 %THEN drop=dxver; ) %END;;
		length codecat code $7;
		array dx(*) dx:;
		array prc(*) pproc proc:;

		if drg in ("&delivery_drg") then do;
			code = put(drg,3.0); 
			setting = "I";
			ga = 0;
			output women_inptservdrg;
		end;
		do d=1 to dim(dx); 
			if dx(d) in ("&delivery_dx9" "&delivery_dx10" "&gestation_dx9" "&gestation_dx10") then do;
				code=dx(d);
				prin_dx=0;

				if dx(d) in ("&gestation_dx9" "&gestation_dx10") then ga=1; else ga=0;
				if dx(d) in ("&delivery_dx9" "&gestation_dx9") THEN codecat='ICD9CM';  ELSE codecat='ICD10CM';
				setting = "I";
				output women_inptservdx;
			end;
		end;
		do p=1 to dim(prc); 
			if prc(p) in ("&delivery_proc9" "&delivery_proc10" "&delivery_cpt") then do;
				code=prc(p);
				if p=1 then prin_proc=1; else prin_proc=0;
				ga=0;
				if prc(p) in ("&delivery_proc9") THEN codecat='ICD9PRC';  ELSE if prc(p) in ("&delivery_proc10") then codecat='ICD10PRC';
					else if prc(p) in ("&delivery_cpt") then codecat='CPT';
					setting = "I";
					ga=0;
				output women_inptservproc;
			end;
		end;
		*rename admdate=svcdate; *format admdate date9.;
	run;

	proc datasets lib=work nolist nodetails; delete women_inptservdx1_:; run; quit;
%mend; 
options mprint;
%inptserv()

proc sql;
	create table women_inptservdx2 as select a.*, 
		case when a.ga=1 then b.prioritygroup1 else . end as prioritygroup1,
		case when a.ga=1 then b.prioritygroup2 else . end as prioritygroup2,
		case when a.ga=1 then b.priority else . end as priority,    
		case when a.ga=1 then b.duration else . end as duration,
		case when a.ga=0 then c.alg else '' end as alg
	from  women_inptservdx as a 
		left join gestation as b on a.code=b.code
		left join delivery as c on a.code=c.code;
quit;

proc sql;
	create table women_inptservproc2 as select a.*,  . as prioritygroup1, . as prioritygroup2, . as priority, . as duration, c.alg 
		from  women_inptservproc as a left join delivery as c on a.code=c.code;

	create table women_inptservdrg2 as select a.*,  . as prioritygroup1, . as prioritygroup2, . as priority, . as duration, c.alg 
		from  women_inptservdrg as a left join delivery as c on a.code=c.code;
quit;*/







*****Note: Code list from Liz does not have any medications thus may have missed some methotrexate or mifepristone prescriptions;


