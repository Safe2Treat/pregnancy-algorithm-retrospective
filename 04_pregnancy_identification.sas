
/********************************************************************************************************************************************
Program Name: 01_pregnancy_identification.sas
Goal: To link mothers and infants for the Liz Suarez adaptation of the Ailes et al. 2023 pregnancy identification algorithm.

Input:	out.preg_person_suarez -  all pregnancy identification codes and GA codes in females aged 10-55
		out.infant_suarez - all infants (age=0), first claim, estimated DOB (min and max)
		out.ce_women

Macros: 	

Output: out.linked_inf
		out.pregfinal

Programmer: Lizzy Simmons (LS)
Date: September 30, 2024 

Modifications:
1/13/2026 - Chase Latour cleaned up formatting and comments.
10/11/2024 - updated according to MarketScan Pregnancy Cohort_v3_20241003.sas
5/15/2025 - ran on full ICD-10 data

********************************************************************************************************************************************/











/***************************************************************************************************************

TABLE OF CONTENTS:
	- 00 - SET LIBRARIES
	- 01 - PREGNANCY IDENTIFICATION
	- 02 - LINK TO INFANTS
	- 03 - ESTIMATE GESTATIONAL AGE
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
%setup(sample=full, programname=ailes_suarez_modification/04_pregnancy_identification, savelog=Y)

options mprint;

/*Create local mirrors of the server libraries*/
/*libname lout slibref=out server=server;*/
/*libname lwork slibref = work server = server;*/
/*libname lcovref slibref = covref server = server;*/
/*libname lder slibref = der server=server;*/
/*libname lraw slibref = raw server=server;*/


options fullstimer;
options mprint;
options mlogic;



**************************************************
*Input datasets:
	*-out.preg_person_suarez: all pregnancy identification codes and GA codes in females aged 10-55 (OLD=pgwork)
	*-out.infant_suarez: all infants (age=0), first claim, estimated DOB (min and max) (OLD=infwork)
	*-ce_woman: continous enrollment segments for females age 10-55 /*TO DO where is this?*/
	*-ce_infant: continous enrollment segments for infants age=0 /*TO DO where is this?*/
************************************************;











/***************************************************************************************************************

											01 - PREGNANCY IDENTIFICATION

***************************************************************************************************************/

*clean up missing age by carrying age across claims of same date;
	*Note: this could be done at the code pull stage instead;
proc sql;
	create table age as
	select enrolid, svcdate, max(age) as age
	from out.preg_person_suarez
	group by enrolid, svcdate
	;
	quit;

*Create a dataset with just end of pregnancy (EOP) codes;
proc sql;
	create table pgwork as 
	select a.enrolid, a.efamid, b.age, a.svcdate, a.setting, a.code, a.codecat, a.prin_dx, a.alg
	from out.preg_person_suarez as a left join age as b
	on a.enrolid=b.enrolid and a.svcdate=b.svcdate
	where a.dlv=1
	order by enrolid, svcdate, code, setting
	;
	quit;
*Output the first code from this dataset within the same svcdate and enrolid. Naturally will select
Inpatient (I) before outpatient (O). This is basically de-duplicating while prioritizing inpatient claims
on the same date.;
data pgwork1;
	set pgwork;
	by enrolid svcdate code setting;
	if first.code; *Output the first code from this dataset within the same svcdate and enrolid;
run;

*limit to ages 12-55;
data pgwork2;
	set pgwork1;
	where 12<=age<=55; 
run;

*check counts;
proc sql noprint;
	select count(distinct ENROLID) as COUNT_UNIQUE from pgwork2; 		
	select count(*) as COUNT_ALL from pgwork2;		 					
	quit;



*****
*Group pregnancy end codes into episodes;
	*group all codes occurring within 30 days of first code;
	*start new episode with first code occurring more than 30 days after the first code;
	*repeat;
data episodes;
set pgwork2;
	by enrolid svcdate;

	*first record;
	if first.enrolid then do;
		seq = 1;
		series = 1;
		day1 = svcdate; *Starting date of episode 1;
		dayend = svcdate;
	end;

	retain seq series day1 dayend;

	if enrolid = lag(enrolid) then do;
	*Create episodes with EOP codes within 30 days;
		if svcdate-day1 <= 30 then do;
			seq = seq + 1;
			dayend = svcdate;
		end;
		else if svcdate-day1 > 30 then do;  
			series = series + 1;*New episode;
			seq = 1;
			day1 = svcdate;*Starting date of episode 1;
			dayend = svcdate;
		end;
	end;
	*ID for each pregnancy episode;
	newid = compress(cat(enrolid, "-", series)," ");
	format day1 dayend date9.;
run;

*select the first claim date during each episode to assign as the end date;
	*only use dates not identified by principal codes;
proc sql;
	create table epi_date as
	select newid, min(svcdate) as del_date1
	from episodes
	where prin_dx ne 1
	group by newid
	;
	quit;

*merge in end date with episodes;
	*episodes with only principal codes will have missing del_date1;
	*assign these missing dates to day1 (earliest date);
	*create a flag for whether the date was assigned only with principal codes;
proc sql;
	create table episodes2 as
	select a.*, case when b.del_date1=. then a.day1 else b.del_date1 end as del_date2 format=date9.,
		case when b.del_date1=. then 1 else 0 end as date_prin
	from episodes as a left join epi_date as b
	on a.newid=b.newid
	;
	quit;
*N=  415,692 (in Suarez code N= 8,017,203);









/***************************************************************************************************************

											02 - LINK TO INFANTS

***************************************************************************************************************/


*prepare infant data;
proc sql; 
	create table infwork as
	select enrolid as enrolid_i, efamid, ce_start, ce_end, svcdate as firstclaim, dob_min, dob_max,  
		case when dob_min ne . then year(dob_min) else year(ce_start) end as infyrmin,
		case when dob_min ne . then year(dob_max) else year(ce_start) end as infyrmax
	from out.infant_suarez
	order by enrolid, efamid
	;
	quit;

*merge pregnancy episodes with infants by efamid and year;
	*create linkage flags in priority of keeping infant linkages;
proc sql;
	create table del_inf as
	select a.*, b.*, year(del_date2) as delyr,
		/*first claim date is the same as code date*/
		/*this code date will override the estimated EOP date (del_date2)*/
		case when firstclaim=svcdate then 1 else 0 end as flag1, 
		/*estimated EOP date is between dob min and max*/
		case when dob_min<=del_date2<=dob_max then 1 else 0 end as flag2,  
		/*first first claim date is 1 day before estimated EOP date or up to 30 days after*/
		case when del_date2-1<=firstclaim<=del_date2+30 then 1 else 0 end as flag3 
	from episodes2 as a left join infwork as b
	on a.efamid=b.efamid and (year(a.svcdate)=b.infyrmin or year(a.svcdate)=b.infyrmax)
	;
	quit;

*delete (will merge back in later) all lines with all flags=0;
	*when firstclaim=svcdate, classify as final delivery date;
data del_inf2;
	set del_inf;
	if flag1=0 and flag2=0 and flag3=0 then delete;
	if flag1=1 then del_date3=svcdate;
	format del_date3 date9.;
run;


*collapse to one line per preg/inf linkage;
proc sql;
	create table del_inf3 as
	select newid, enrolid, efamid, enrolid_i, del_date2, ce_start, ce_end, firstclaim,
		dob_min, dob_max, max(flag1) as flag1, max(flag2) as flag2, max(flag3) as flag3,
		max(del_date3) as del_date3 format=date9.
	from del_inf2
	group by newid, enrolid, enrolid_i, efamid, enrolid_i, del_date2, ce_start, ce_end, firstclaim,
		dob_min, dob_max
	;
	quit;

*create hierarchy of infant links;
	*also set EOP date to previously estimated EOP date if missing;
data del_inf4;
	set del_inf3;
	if del_date3=. then del_date3=del_date2;
	if flag1=1 then infkeep=1;			
		else if flag2=1 and flag3=1 then infkeep=2;	
		else if flag2=1 then infkeep=3;
		else if flag3=1 then infkeep=4;
run;

*count number of mom and pregnancies matched per infant;
proc sql;
	create table match_count as
	select enrolid_i, count(distinct enrolid) as num_mom, count(distinct newid) as num_preg
	from del_inf4
	where enrolid_i ne .
	group by enrolid_i
	;
	quit;

*merge match counts back in with preg/inf linkage table;
proc sql;
	create table del_inf5 as
	select a.*, b.num_mom, b.num_preg
	from del_inf4 as a left join match_count as b
	on a.enrolid_i=b.enrolid_i
	;
	quit;

/*
	*evaluate instances when infants linked to multiple pregnancies;
		data multipreg;
			set del_inf5;
			where num_mom=1 and num_preg>1;
			diff=firstclaim-del_date2;
		run;

		**keep the pregnancy/inf link with the lowest infkeep value;
			**keep the other pregnancy, just delete infant data (will clean up these close episodes later);

		data multimom;
			set del_inf5;
			where num_mom>1;
			diff=firstclaim-del_date2;
		run;

		**if infkeep is the same across women linked to the same infant, delete 
			(these are likely to be duplicate records of the same mother);
		**if infkeep is not the same, we could keep the lower infkeep (better linkage);
			**this will sometimes (not sure how often) keep duplicates;
		**OR delete all pregnancies with linkage of one infant to multiple mothers (went with this option);
*/

*if linked to only one mom, keep the lowest infkeep value;
data onemom;
	set del_inf5;
	where num_mom=1;
run;
*48,167 (from Suarez code=517,194);
proc sort data=onemom; by enrolid_i infkeep; run;
data onemom1;
	set onemom;
	by enrolid_i;
	if first.enrolid_i;
run;
*N=48,147 (from Suarez code N=516,930);

*if linked to more than one mom, flag for deletion;
data plusmom;
	set del_inf5;
	where num_mom>1;
	pregdelete=1;
run;
*N=74 (from Suarez code N=748);

*stack linked infants;
data allinf;
	set onemom1 plusmom;
	rename flag3=inf_firstclaim_30;
run;	
*N=48,221 (from Suarez code N=517,678);

*output linked infants;
*include a flag for whether the infant has a first claim within 30 days of delivery;
data out.linked_inf_suarez;
	set allinf;
	where pregdelete ne 1;
	keep newid efamid enrolid_i del_date3 ce_start ce_end inf_firstclaim_30;
run;

*merge with all pregnancy codes to start outcome assignment process;
	*delete the pregnancies flagged for deletion;
proc sql;
	create table preg as
	select a.*, b.*
	from episodes2 as a left join allinf as b
	on a.newid=b.newid
	where pregdelete ne 1
	;
	quit;
*N=418,118 (from Suarez code N=8,011,228);

*create flags for EOP type classification;
data preg2;
	set preg;
	if alg='LB' then eop_lb=1;
	if alg='LBSB' then eop_lbsb=1;
	if alg='ECT' then eop_ect=1;
	if alg='IAB' then eop_iab=1;
	if alg='ABN' then eop_abn=1;
	if alg='SAB' then eop_sab=1;
	if alg='SB' then eop_sb=1;
	if alg='UNK' then eop_unk=1;
	if enrolid_i ne . then eop_lb=1;
	*some cleaning;
	if del_date3=. then del_date3=del_date2;
	rename del_date3=eop_date;
	drop del_date2 flag1 flag2 infkeep num_mom num_preg pregdelete; 
run;

*collapse to one line per pregnancy;
	*take min eop_date to select one date in instances where there are multiple infants with slightly different dates (e.g. twins);
proc sql;
	create table preg3 as
	select enrolid, efamid, newid, date_prin, inf_firstclaim_30, min(eop_date) as eop_date format=date9., min(age) as mage, count(distinct code) as num_code, 
		count(distinct enrolid_i) as num_inf, sum(eop_lb) as eop_lb, sum(eop_lbsb) as eop_lbsb, 
		sum(eop_ect) as eop_ect, sum(eop_iab) as eop_iab, sum(eop_abn) as eop_abn, sum(eop_sab) as eop_sab,
		sum(eop_sb) as eop_sb, sum(eop_unk) as eop_unk
	from preg2
	group by enrolid, efamid, newid, date_prin, inf_firstclaim_30
	;
	quit;

*add in pregnancy marker codes;
	*flag as having a pregnancy marker if code with within 30 prior to and including delivery date;
data pregmark;
	set out.preg_person_suarez;
	where mrk=1;
	rename svcdate=pregmkdt;
	keep enrolid svcdate;
run;
proc sql;
	create table pregmark2 as
	select a.*, case when pregmkdt ne . then 1 else 0 end as pregmark
	from preg3 as a left join pregmark as b
	on a.enrolid=b.enrolid and eop_date-30<=pregmkdt<=eop_date
	;
	quit;
proc sql;
	create table pregmark3 as
	select enrolid, efamid, newid, date_prin, inf_firstclaim_30, eop_date, mage, num_code, 
		num_inf, eop_lb, eop_lbsb, eop_ect, eop_iab, eop_abn, eop_sab, eop_sb, eop_unk,
		max(pregmark) as pregmark
	from pregmark2
	group by enrolid, efamid, newid, date_prin, inf_firstclaim_30, eop_date, mage, num_code, 
		num_inf, eop_lb, eop_lbsb, eop_ect, eop_iab, eop_abn, eop_sab, eop_sb, eop_unk
	;
	quit;
	
*classify outcome type based on hierarchy;
	**NOTE: in the MacDonald algorithm, they also use pregnancy marker codes to veryify pregnancies
		I did not include that because we haven't pulled this code list yet, but we can add it easily;
*classify outcome type based on hierarchy;
data preg4;
	set pregmark3 /*old=preg3*/;
	count=sum(eop_lb, eop_lbsb, eop_ect, eop_iab, eop_abn, eop_sab, eop_sb);

	*Mixed live and stillbirth;
	if eop_lbsb>0 and eop_unk>0 then outcome='LBSB';

		*Live birth;
		else if eop_lb>0 and eop_unk>0 then outcome='LB';
		else if eop_lb>0 and num_inf>0 then outcome='LB';
		else if eop_unk>0 and num_inf>0 then outcome='LB';
		else if eop_unk>1 and eop_lb<1 and eop_lbsb<1 and eop_ect<1 and eop_iab<1 and eop_abn<1
			and eop_sab<1 and eop_sb<1 then outcome='LB';
		else if eop_unk>0 and pregmark=1 and eop_lb<1 and eop_lbsb<1 and eop_ect<1 and eop_iab<1 
			and eop_abn<1 and eop_sab<1 and eop_sb<1 then outcome='LB';
		else if eop_lb>0 and pregmark=1 then outcome='LB';

		*Ectopic;
		else if eop_ect>0 then outcome='ECT';

		*Induced abortion;
		else if eop_iab>1 and num_inf=0 then outcome='IAB';
		else if eop_iab>0 and eop_abn>0 and num_inf=0 and eop_sab<1 and eop_sb<1 then outcome='IAB';
		else if eop_iab>0 and pregmark=1 and num_inf=0 and eop_sab<1 and eop_sb<1 then outcome='IAB';

		*Spontaneous abortion;
		else if eop_sab>1 and num_inf=0 then outcome='SAB';
		else if eop_sab>0 and eop_abn>0 and num_inf=0 and eop_iab<1 and eop_sb<1 then outcome='SAB';
		else if eop_sab>0 and pregmark=1 and num_inf=0 and eop_iab<1 and eop_sb<1 then outcome='SAB';

		*Unspecified abortion;
		else if eop_sab>0 and eop_iab>0 and num_inf=0 then outcome='ABN';
		else if eop_abn>1 and num_inf=0 and eop_sb<1 then outcome='ABN';
		else if eop_abn>1 and pregmark=1 and num_inf=0 and eop_sb<1 then outcome='ABN';

		*Stillbirth;
		else if eop_sb>0 and eop_unk>0 and num_inf=0 then outcome='SB';

run;

*drop pregnancies with no outcome type assigned or ECT;
data preg5;
	set preg4;
	if outcome='' or outcome='ECT' then delete;
run;
*N=83,279 (from Suarez code N=849,160);



/*
MACRO: loop
PURPOSE: Identify and remove pregnancies that are too close to another EOP date. Flag all LB, SB, LBSB 
with eop_date occurring less than 211 days after prior EOP date. Flag all SAB, IAB, ABN with eop_date 
occurring less than 61 days after prior EOP date. Use MacDonald algorithm hierarchy to decide which 
--close-- pregnancy to keep. Look through multiple times until there are no close pregnancies left.

INPUT:
- indata: name of the input dataset of pregnancies
- outdata: name of the output dataset of pregnancies
*/

%macro loop(indata, outdata);

	*flag all LB, SB, LBSB with eop_date occurring less than 211 days after prior EOP date;
	*flag all SAB, IAB, ABN with eop_date occurring less than 61 days after prior EOP date;
	proc sort data=&indata; by enrolid eop_date; run;
	data preg6;
		set &indata;
		by enrolid;
		day_prev_eop=eop_date-lag(eop_date);
		if (outcome='LB' or outcome='SB' or outcome='LBSB') and day_prev_eop<211 then close=1;
		if (outcome='SAB' or outcome='IAB' or outcome='ABN') and day_prev_eop<61 then close=1;
		if first.enrolid then do; day_prev_eop=.; close=.; end;
	run;

	*create "episodes" of pregnancies with close dates;
	data preg7;
		set preg6;
		by enrolid eop_date;
		retain close_epi;
		if first.enrolid then close_epi=1;
		if not first.enrolid and close=. then close_epi=close_epi+1;
	run;

	*add indicator for close pregnancies to all pregnancies;
		*select pregnancies with too close EOP based on hierarchy;
	proc sort data=preg7; by enrolid descending eop_date; run;
	data preg8; 
		set preg7; 
		close_ind=lag(close);
		if close_ind=. then close_ind=close;
		if close_ind=1 then do;
			if num_inf>0 then rank=1;
			else if outcome='LB' then rank=2;
			else if outcome='LBSB' then rank=3;
			else if outcome='SB' then rank=4;
			else if outcome='SAB' then rank=5;
			else if outcome='IAB' then rank=6;
			else if outcome='ABN' then rank=7;
		end;
	run;

	*select all pregnancies to keep based on ranking;
	proc sort data=preg8; by enrolid close_epi rank date_prin descending num_code eop_date; run;
	data pregkeep;
		set preg8;
		by enrolid close_epi;
		if first.close_epi=1 then keep=1;
		if rank=. then keep=1;
	run;

	*all not selected to keep - remove first pregnancy;
	proc sql;
		create table pregremove as
		select * from pregkeep where keep=.
		order by enrolid, eop_date
		;
		quit;
	data pregkeep2;

	set pregremove;
		by enrolid close_epi;
		if not first.close_epi;
	run;

	data &outdata;
		set pregkeep (where=(keep=1)) pregkeep2;
		drop day_prev_eop close close_epi close_ind rank keep;
	run;
%mend loop;	


/**This version of the loop automatically runs until there are not changes;*/
/*%macro loop(indata, outdata);*/
/**/
/*	%let tooclose = 1;*/
/*	%let num = 0;*/
/**/
/*	%do %until (&tooclose = 0);*/
/**/
/*		%let num = &num+1;*/
/**/
/*		%if &num = 1 %then %do;*/
/*			*flag all LB, SB, LBSB with eop_date occurring less than 211 days after prior EOP date;*/
/*			*flag all SAB, IAB, ABN with eop_date occurring less than 61 days after prior EOP date;*/
/*			proc sort data=&indata; by enrolid eop_date; run;*/
/*			data preg6;*/
/*				set indata;*/
/*				by enrolid;*/
/*				day_prev_eop=eop_date-lag(eop_date);*/
/*				if (outcome='LB' or outcome='SB' or outcome='LBSB') and day_prev_eop<211 then close=1;*/
/*				if (outcome='SAB' or outcome='IAB' or outcome='ABN') and day_prev_eop<61 then close=1;*/
/*				if first.enrolid then do; day_prev_eop=.; close=.; end;*/
/*			run;*/
/*		%end;*/
/**/
/*		%else %do;*/
/*			*flag all LB, SB, LBSB with eop_date occurring less than 211 days after prior EOP date;*/
/*			*flag all SAB, IAB, ABN with eop_date occurring less than 61 days after prior EOP date;*/
/*			proc sort data=_out; by enrolid eop_date; run;*/
/*			data preg6;*/
/*				set _out;*/
/*				by enrolid;*/
/*				day_prev_eop=eop_date-lag(eop_date);*/
/*				if (outcome='LB' or outcome='SB' or outcome='LBSB') and day_prev_eop<211 then close=1;*/
/*				if (outcome='SAB' or outcome='IAB' or outcome='ABN') and day_prev_eop<61 then close=1;*/
/*				if first.enrolid then do; day_prev_eop=.; close=.; end;*/
/*			run;*/
/*		%end;*/
/**/
/*		*create "episodes" of pregnancies with close dates;*/
/*		data preg7;*/
/*			set preg6;*/
/*			by enrolid eop_date;*/
/*			retain close_epi;*/
/*			if first.enrolid then close_epi=1;*/
/*			if not first.enrolid and close=. then close_epi=close_epi+1;*/
/*		run;*/
/**/
/*		*add indicator for close pregnancies to all pregnancies;*/
/*			*select pregnancies with too close EOP based on hierarchy;*/
/*		proc sort data=preg7; by enrolid descending eop_date; run;*/
/*		data preg8; */
/*			set preg7; */
/*			close_ind=lag(close);*/
/*			if close_ind=. then close_ind=close;*/
/*			if close_ind=1 then do;*/
/*				if outcome='LB' then rank=1;*/
/*				else if outcome='LBSB' then rank=2;*/
/*				else if outcome='SB' then rank=3;*/
/*				else if outcome='SAB' then rank=4;*/
/*				else if outcome='IAB' then rank=5;*/
/*				else if outcome='ABN' then rank=6;*/
/*			end;*/
/*		run;*/
/**/
/*		*select all pregnancies to keep based on ranking;*/
/*		proc sort data=preg8; by enrolid close_epi rank date_prin descending num_code eop_date; run;*/
/*		data pregkeep;*/
/*			set preg8;*/
/*			by enrolid close_epi;*/
/*			if first.close_epi=1 then keep=1;*/
/*			if rank=. then keep=1;*/
/*		run;*/
/**/
/*		*all not selected to keep - remove first pregnancy;*/
/*		proc sql;*/
/*			create table pregremove as*/
/*			select * from pregkeep where keep=.*/
/*			order by enrolid, eop_date*/
/*			;*/
/*			quit;*/
/**/
/*		*Count the number of pregnancies that were too close in this round.;*/
/*		proc sql noprint;*/
/*			select count(enrolid) into :tooclose from pregremove;*/
/*			quit;*/
/*		%PUT ROUND: &num;*/
/*		%PUT NUM CLOSE: &tooclose ;*/
/**/
/*		data pregkeep2;*/
/*		set pregremove;*/
/*			by enrolid close_epi;*/
/*			if not first.close_epi;*/
/*		run;*/
/**/
/*		data _out1;*/
/*			set pregkeep (where=(keep=1)) pregkeep2;*/
/*		run;*/
/**/
/*		data _out;*/
/*		set _out1;*/
/*			drop day_prev_eop close close_epi close_ind rank keep;*/
/*		run;*/
/**/
/*	%end;*/
/**/
/*	data &outdata;*/
/*	set _out;*/
/*	run;*/
/**/
/*%mend loop;	*/



**Loop through until final N does not  change (or when pregkeep2 has 0 obs);
	**there is probably a way to automate this**;
%loop(preg5,pregout1);
*N=81,751;
%loop(pregout1,pregout2);
*N=81,644;
%loop(pregout2,pregout3);
*N=81,618;
%loop(pregout3,pregout4);
*N=81,611;
%loop(pregout4,pregout5);
*N=81,609;
%loop(pregout5,pregout6);
*N=81,608;
%loop(pregout6,pregout7);
*N=81,607;
%loop(pregout7,pregout8);
*N=81,606;
%loop(pregout8,pregout9);
*N=81,605;
%loop(pregout9,pregout10);
*N=81,604;
%loop(pregout10,pregout11);
*N=81,603;
%loop(pregout11,pregout12);
*N=81,603;

/*Now have final cohort*/
data allpreg;
	set pregout12;
	keep enrolid efamid newid eop_date mage num_inf	outcome inf_firstclaim_30;
run;

	proc freq data=allpreg; table outcome num_inf; run;
	*80%% LB, 59% linked to infant;
	*from Suarez code:82% LB, 61% of all pregnancies linked to infant;













/***************************************************************************************************************

											03 - ESTIMATE GESTATIONAL AGE

***************************************************************************************************************/

*all GA codes;
data ga;
	set out.preg_person_suarez;
	where ga=1;
run;

*merge with final pregnancies, only link when outcome type matches;
proc sql;	
	create table preg_ga as
	select a.*, b.code, b.svcdate as gadate, b.prioritygroup1, b.prioritygroup2, b.priority, b.duration,
		b.lb, b.sb, b.lbsb, b.sab, b.iab, b.abn
	from allpreg as a left join ga as b
	on a.enrolid=b.enrolid and a.eop_date-7<=b.svcdate<=a.eop_date+30 and
		((outcome='LB' and LB=1) or (outcome='SB' and SB=1) or (outcome='LBSB' and LBSB=1)
		or (outcome='SAB' and SAB=1) or (outcome='IAB' and IAB=1) or (outcome='ABN' and ABN=1))
	order by newid, prioritygroup1 desc, prioritygroup2 desc, priority
	;
	quit;

*collapse by pregnancy again and select final ga;
data preg_ga_final;
	set preg_ga;
	by newid;
	if first.newid;
	*set standard values for outcomes if duration is missing;
	if duration=. then do;
		if outcome='LB' then duration=273;
		if outcome='SB' then duration=196;
		if outcome='LBSB' then duration=245;
		if outcome='SAB' then duration=63;
		if outcome='IAB' then duration=70;
		if outcome='ABN' then duration=63;
	end;
	*assign LMP date;
	lmp_date=eop_date-duration;
	format lmp_date date9.;
run;

*link to maternal enrollment data;
*to do - why are some ce_start and ce_end set to missing here?;
proc sql;
	create table preg_ce as
	select a.*, b.ce_start, b.ce_end
	from preg_ga_final as a /*to do - change to inner join?*/ left join out.ce_woman as b
	on a.enrolid=b.enrolid and b.ce_start<=a.eop_date and a.eop_date<=b.ce_end
	order by a.newid
	;
	quit;

*create flags for enrollment;
data preg_ce2;
set preg_ce;
	if ce_start<=lmp_date and ce_end>=eop_date then preg_enroll=1;
	if ce_start<=lmp_date-90 and ce_end>=eop_date then preg_enroll_90=1;
	if ce_start<=lmp_date-180 and ce_end>=eop_date then preg_enroll_180=1;
run;

*output;
data out.pregfinal_suarez;
set preg_ce2;
	pregID=_N_+1000000000;
	keep enrolid pregid final_type source_lmp efamid newid eop_date mage num_inf outcome duration lmp_date 
		ce_start ce_end preg_enroll preg_enroll_90 preg_enroll_180 inf_firstclaim_30;
run;




*check final GA;
/*proc sort data=out.pregfinal; by outcome;
	proc means data=out.pregfinal;
		class outcome;
		var duration;
	run;*/
/*
proc import datafile="/local/projects/marketscan_preg/raw_data/programs/ailes_suarez_modification/enrolids_missing_demographic_info.xlsx"
	out=miss_demo
	dbms=xlsx
	replace;
run;

proc sort data=out.pregfinal_suarez; by enrolid;
proc sort data=miss_demo; by enrolid;
data desc;
	merge out.pregfinal_suarez miss_demo;
	by enrolid;
	diff_start=eop_date-ce_start;
	diff_end=ce_end-eop_date;
run;
proc print data=desc; where miss_demo=1 and ce_start=.; run;

proc freq data=desc; 
	where miss_demo=1;
	table outcome duration diff_start diff_end / missing;
run;*/
