
/********************************************************************************************************************************************
Program Name: 05_make_lookup_datasets.sas
Goal: To make lookup dataset for the Liz Suarez adaptation of the Ailes et al. 2023 pregnancy identification algorithm.

Input:	out.pregfinal

Macros: 	

Output: 

Programmer: Lizzy Simmons (LS)
Date: June 26, 2026

Modifications:
- CDL: Standardized formatting with other programs.

********************************************************************************************************************************************/







/***************************************************************************************************************

TABLE OF CONTENTS:
	- 00 - SET LIBRARIES
	- 01 - CREATE NECESSARY GLOBAL VARIABLES
	- 02 - CREATE LOOK-UP DATASETS
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
%setup(sample=full, programname=ailes_suarez_modification/05_make_lookup_datasets, savelog=Y)

options mprint;

libname ld '/local/data/master/marketscanccae/random1pct/ccae'; /* location where the CCAEx datafiles are location */ 
libname mw '/local/projects/marketscan_preg/raw_data/data/random1pct'; /*where I want to save the data */ 







/***************************************************************************************************************

								01 - CREATE NECESSARY GLOBAL VARIABLES

***************************************************************************************************************/


/* Step 0 - set parameters */

%let yearend=2023; /*if you are adding an additional year - change this number to the final year of the dataset*/

%let rnum = r1; /* version number - increase number when a new year is added */
%let s = inptserv;
%let o = outptserv;
%let t = enrdet;
%let d = outptdrug;
%let i = inptadm;
%let r = lab;

%let keep_variables_&i= admdate admtyp age agegrp caseid days disdate dobyr drg dstatus dx1-dx15
						eeclass eestatu efamid egeoloc eidflag emprel enrflag enrolid   
						hlthplan indstry mdc mhsacovg msa pdx phyflag physid plantyp pproc proc1-proc15 
					 	region rx sex state year ;

%let keep_variables_&s= admdate admtyp age agegrp caseid disdate dobyr drg dstatus dx1 dx2 dx3 dx4 
						eeclass eestatu efamid egeoloc eidflag emprel enrflag enrolid   
						hlthplan indstry mdc mhsacovg msa pdx phyflag plantyp pproc proc1 pddate
						proctyp provid region rx sex stdplac stdprov svcscat svcdate year tsvcdat;

%let keep_variables_&o= age agegrp dx1 dx2 dx3 dx4 efamid enrolid eeclass eestatu egeoloc emprel proc1 
						proctyp  svcdate dobyr year hlthplan region indstry sex mdc msa phyflag plantyp 
						pddate provid stdplac tsvcdat rx stdprov svcscat eidflag enrflag mhsacovg;

%let keep_variables_&d= age dawind daysupp deaclas dobyr eeclass eestatu efamid egeoloc 
						eidflag emprel enrflag enrolid generid genind hlthplan indstry metqty msa maintin mhsacovg
						ndcnum pddate pharmid phyflag qty refill region sex svcdate thercls thergrp year;
	
%let keep_variables_&t= age dtend dtstart efamid enrolid  memdays sex year mhsacovg region rx;

options notes mprint mprintnest  nomlogic ;

proc format;
	value type
	1 = "1 Stillbirth + Livebirth"
	2 = "2 Livebirth"
	3 = "3 SAB" 
	4 = "4 Termination"
	5 = "5 Stillbirth"
	6 = "6 Unspecified Abortion"
	99 = "99 Ectopic/ Molar Removed"
	999 = "999 Removed"
	;
run;












/***************************************************************************************************************

									02 - CREATE LOOK-UP DATASETS

***************************************************************************************************************/


*Unique Women Ages 18-50 in all years of the dataset;
data preg_womenlist; 
set out.pregfinal_suarez (keep=enrolid pregid eop_date outcome); 
run; 
proc sort data=preg_womenlist; 
	by enrolid; 
run;
data mw.preg_womenlist_10_&rnum.(where=(pregnancy=1)); 
set preg_womenlist;
	by enrolid; 
	pregnancy+1; 
	if first.enrolid then pregnancy=1; 
run;


*Derive a list of the infants;
data mw.preg_infantlist_10_&rnum.;
set out.pregfinal_suarez (keep=enrolid pregid eop_date num_inf);
	where num_inf>0; 
	drop num_inf;
	pregnancy=1;
run;



/*
MACRO: make_final_lookup
PURPOSE: Make the final lookup datasets by looping over person-level datasets and the claims

INPUT: none.
*/


%Macro Make_final_lookup;

	%*Set global variables in the macro;
	%let personlist= women infant ; 
	%let datalist=&&s &&o &&t &&d &&i &&r*; 
	%let datalist2=s o t d i r;

	%do i_p = 1 %to %sysfunc(countw(&personlist)); %*Look over the two person-level datasets;

		%let person = %scan(&personlist, &i_p); %*Select the dataset corresponding to the loop;

		%do i_d = 1 %to  %sysfunc(countw(&datalist)); %*Loop over all of the claims files for persons in that list;

			%let d1 = %scan(&datalist, &i_d);
			%let d2= %scan(&datalist2, &i_d);

			%if &d1 = &&s OR &d1 = &&o OR &d1 = &&i | &d1 = &&r %then %let h_dxver=dxver; 
			%if &d1 = &&d OR &d1=&&t %then %let h_dxver=; 
			%do yr=2015 %to &&yearend; 
				%if &d1 = &&i %then %let datevar=disdate; 
				%if &d1 = &&s | &d1 = &&o | &d1=&&d | &d1=&&r %then %let datevar=svcdate; 
				%if &d1 = &&t %then %let datevar=dtstart;  
				%if &yr=2015 %then %do; /* Restrict dates for 2015 year and not for other yrs*/
					%if &d1 ne &&r %then %do;
						proc sql; 
							create table sub(where=(pregnancy=1)) as
							select *
							from mw.preg_&person.list_10_&rnum. as a 
							full join ld.&d1&yr(keep=&&keep_variables_&d1 &h_dxver where=(&datevar >= mdy(10,1,2015))) as b
							on a.enrolid=b.enrolid ;
							quit; run; 
					%end;
				%end; 
				%else %do;
					%if &d1 ne &&r %then %do;
						proc sql; 
						create table sub(where=(pregnancy=1)) as
						select *
						from mw.preg_&person.list_10_&rnum. /*(drop=pregid )*/ as a
						full join ld.&d1&yr(keep=&&keep_variables_&d1 ) as b
						on a.enrolid=b.enrolid ;
						quit; run; 

						data sub; set sub; run;
					%end;
				%end;

				data sub2; 
				%if &d1=&&o %then %do; 
					length  DX1-DX4 PROC1 $7 DXVER $2;
				%end;
				%if &d1=&&s %then %do; 
					length PDX DX1-DX4 PPROC PROC1 $7 DXVER $2;
				%end;
				%if &d1=&&i  %then %do;
					length PDX DX1-DX15 PPROC PROC1-PROC15 $7 DXVER $2;
				%end;
				set sub(Where=(year ne .));
					%if &d1=&&o | &d1=&&s | &d1=&&i %then %do;
						if &datevar >= mdy(10,1,2015) & dxver = "" then dxver ="10";  
					%end;
				run; 

				%if &yr = 2015 %then %do;
					data mw.&person._pregcohort_10_&d2._&rnum. ; set sub2(drop=pregnancy); run;
				%end;
					%else %do; 
						proc append base = mw.&person._pregcohort_10_&d2._&rnum.   data = sub2(drop=pregnancy) force; run ;
					%end; 

				%if &yr = &&yearend %then %do;
					title "Number of Unique people on file &person._pregcohort_10_&d2._&rnum."; 
					proc sql; 
						select count(distinct enrolid) into:numobs from mw.&person._pregcohort_10_&d2._&rnum.;  quit; title;
				%end;
			%end; /* year end */
		%end; /*dataset end */
	%end; /* person end */
%mend; 


%Make_final_lookup;




/*
MACRO: make_simplelookup
PURPOSE: Create simpler lookup datasets

INPUT: None.
*/


%Macro Make_simplelookup; /*infant women*/
	%let personlist= women infant ; 
	
	%do i_p = 1 %to %sysfunc(countw(&personlist)); 

		%let person = %scan(&personlist, &i_p);

		data sub(where=(codedp ne "")
		drop=dx: proc1); 
		set mw.&person._pregcohort_10_o_&rnum(keep=enrolid pregid dx: proc1 svcdate year);
			sourcedata="Outptserv";
			codedp=dx1; dtype='d'; princ=0; code_num=1; output; 
			codedp=dx2; dtype='d'; princ=0; code_num=2; output;
			codedp=dx3; dtype='d'; princ=0; code_num=3; output;
			codedp=dx4; dtype='d'; princ=0; code_num=4; output;
			codedp=proc1; dtype='p'; princ=0; code_num=1; output;
		run;

		/* keep only one per woman per date per code per source data */ 
		proc sort data=sub; 
			by enrolid svcdate dtype codedp princ code_num ; 
		run;
		data sub; 
		set sub; 
			by enrolid svcdate dtype codedp princ code_num ; 
			if first.enrolid | first.svcdate| first.dtype | first.codedp | first.princ then ff=1;  
		run; 
		data mw.&person._pregcohort_10_o_&rnum._m(drop=ff); 
		set sub(where=(ff=1)); 
		run;
		

		data sub(where=(codedp ne "" ) drop=dx: proc1 pdx pproc drg drg_char); 
		set mw.&person._pregcohort_10_s_&rnum(keep=enrolid pregid dx: proc1 pdx pproc 
												drg caseid svcdate disdate admdate  year); 
			sourcedata="Inptserv";
			drg_char = left(put(drg,  $8.)); 
			codedp=drg_char; dtype='r'; princ=1; code_num=0; output;
			codedp=pdx; dtype='d'; princ=1; code_num=0; output; 
			codedp=dx1; dtype='d'; princ=0; code_num=1; output; 
			codedp=dx2; dtype='d'; princ=0; code_num=2;  output;
			codedp=dx3; dtype='d'; princ=0; code_num=3; output;
			codedp=dx4; dtype='d'; princ=0;  code_num=4; output;
			codedp=pproc; dtype='p';princ=1; code_num=0; output;
			codedp=proc1; dtype='p'; princ=0; code_num=1; output;
		run;

		/* keep only one per woman per date per code per source data */ 
		proc sort data=sub; 
			by enrolid svcdate dtype codedp princ code_num  ; 
		run;
		data sub; 
		set sub; 
			by enrolid svcdate dtype codedp princ ; 
			if first.enrolid | first.svcdate| first.dtype | first.codedp | first.princ  then ff=1;  
		run; 
		data sub2; set sub(where=(ff=1)); run;

		/* keep only one PDX and one PPROC per visit  */
		proc sort data=sub2; by enrolid caseid princ codedp code_num;  
		data sub2; 
		set sub2(drop=ff); by enrolid caseid princ codedp ;
			if first.enrolid | first.caseid | first.princ | first.codedp then ff=1;
			if princ ne 1 then ff=1; 
		run; 
		data mw.&person._pregcohort_10_s_&rnum._m(drop=ff); 
		set sub2(where=(ff=1)); 
		run;
	%end;
%Mend; 

%Make_simplelookup;





*get information for data dictionary;
%macro examine(dataset, id); 
	title "number of unique &id"; 
	proc sql; 
		select count(distinct  &id) as countdistin
		from &dataset ;
		quit;run;
	title;

	proc contents data=&dataset; run;
%mend;

%examine(dataset=OUT.PREG_WOMENLIST_10_R1, id=enrolid);
%examine(dataset=out.women_pregcohort_10_s_r1, id=enrolid);
%examine(dataset=out.women_pregcohort_10_o_r1, id=enrolid);
%examine(dataset=out.women_pregcohort_10_t_r1, id=enrolid);
%examine(dataset=out.women_pregcohort_10_d_r1, id=enrolid);
%examine(dataset=out.women_pregcohort_10_i_r1, id=enrolid);
%examine(dataset=out.infant_pregcohort_10_o_r1, id=enrolid);
%examine(dataset=out.infant_pregcohort_10_t_r1, id=enrolid);
%examine(dataset=out.infant_pregcohort_10_d_r1, id=enrolid);
%examine(dataset=out.infant_pregcohort_10_i_r1, id=enrolid);
%examine(dataset=out.women_pregcohort_10_o_r1_m, id=enrolid);
%examine(dataset=out.women_pregcohort_10_s_r1_m, id=enrolid);
%examine(dataset=out.infant_pregcohort_10_o_r1_m, id=enrolid);
%examine(dataset=out.infant_pregcohort_10_s_r1_m, id=enrolid);

