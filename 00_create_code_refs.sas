
/********************************************************************************************************************************************
Program Name: 00_create_code_refs.sas
Goal: To create a SAS datasets with the reference code sets for pregnancy outcomes.

Input:	

Macros: 	

Output: covref.delivery
		covref.ga
		covref.preg_markers

Programmer: Chase Latour
Date: May 2024 

Modifications:
	10.04.2024: Updated the files based off the revised codelist sent by Liz Suarez on 10.03.2024
	04.01.2025: Updated files based on revised codelist created by comparing Liz Suarez's list to original Ailes Algorithm (LS)

********************************************************************************************************************************************/








/***************************************************************************************************************

TABLE OF CONTENTS:
	- 00 - SET LIBRARIES
	- 01 - IMPORT EXCEL SHEETS AND MAKE RELEVANT SAS DATASETS

***************************************************************************************************************/









/***************************************************************************************************************

											00 - SET LIBRARIES

***************************************************************************************************************/


/*run this locally if you need to log onto the N2 server.*/
SIGNOFF;
%LET server=n2.schsr.unc.edu 1234; 
options comamid=tcp remote=server; 
signon username=_prompt_;

*Run setup macro and define libnames;
options sasautos=(SASAUTOS "/local/projects/marketscan_preg/raw_data/programs/macros");
/*change "saveLog=" to "Y" when program is closer to complete*/
%setup(sample= random1pct, programname=00_create_code_refs, savelog=N)

/*Create local mirrors of the server libraries*/
libname lout slibref=out server=server;
libname lwork slibref = work server = server;
libname lcovref slibref = covref server = server;
libname lder slibref = der server=server;
libname lraw slibref = raw server=server;








/***************************************************************************************************************

							01 - IMPORT EXCEL SHEETS AND MAKE RELEVANT SAS DATASETS

***************************************************************************************************************/

*Pregnancy outcome codes (note that this is erroneously labeled delivery);
proc import datafile='/local/projects/marketscan_preg/raw_data/programs/ailes_suarez_modification/Delivery_GA_PregMarker_Codes.xlsx'
	dbms = xlsx
	out = delivery
	replace;
	sheet = 'delivery';
run;
data covref.delivery;
	set delivery;
	where include_final=1;
run;
proc print data=covref.preg_markers; run;

*Gestational age codes;
proc import datafile='/local/projects/marketscan_preg/raw_data/programs/ailes_suarez_modification/Delivery_GA_PregMarker_Codes.xlsx'
	dbms = xlsx
	out = ga
	replace;
	sheet = 'GA';
run;
data covref.ga;
	set ga;
	where include_final=1;
run;


*Pregnancy marker codes;
proc import datafile='/local/projects/marketscan_preg/raw_data/programs/ailes_suarez_modification/Delivery_GA_PregMarker_Codes.xlsx'
	dbms = xlsx
	out = covref.preg_markers
	replace;
	sheet = 'pregnancy markers';
run;



