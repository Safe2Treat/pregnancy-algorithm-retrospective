The code provided in this repository was constructed to identify a cohort of pregnancies based upon observed outcomes (e.g., live or stillbirth) in MarketScan claims data. Go to the Wiki page for detailed documentation for implementing this algorithm.

All of the SAS files are extensively commented to facilitate use, but we provide a description below for getting started. This project was conducted on a remote server through a local interface. Some lines of coded were included to create the connection between the local SAS session and remote server. This led to some lines that needed to be run locally, though the majority were run directly to the server. This should be indicated in the files.

**Algorithm Description**
`MarketScan Pregnancy Cohort_protocol.pdf` - This file is saved on the Wiki page and provides a detailed overview of the algorithm and the associated programs for implementing steps. 

**Codelist**
`Delivery_GA_PregMarker_Codes_forGitHub.xlsx` -- This file contains all the reference code lists for pregnancy markers, pregnancy outcomes, and gestational age. We create SAS files for these code lists in the 00_create_code_refs.sas program.
Given the important shifts in legislation and policy surrounding induced abortion and reproductive freedom/autonomy in the U.S., we have modified this code such that it does not identify induced abortions specifically. Instead, they are identified as "Unspecified Abortions". As such, this category can include induced abortionsn as well as spontaneous abortions where the coding documentation did not clearly indicate that it was spontaneous. To identify induced abortions, users must modify the pregnancy outcome codelist to determine which codes they believe identify an induced abortion specifically.

**Pregnancy Algorithm**
The pregnancy algorithm is then implemented in order. Libraries will need to be re-set based upon the users' environment.

- `01_women_ce.sas` - Identifies periods of continuous enrollment for females of reproductive age.
- `02_infant_cohort.sas` - Identifies a cohort of infants.
- `03_preg_person_cohort.sas` - Creates a long file of all pregnancy-related claims for females of reproductive age.
- `04_pregnancy_identification.sas` - Identifies pregnancies based upon pregnancy-related claims and infant linkage.
- `05_make_lookup_datasets.sas` - Creates look-up files for easier data management.

This code was developed using claims data from Merative's Commerical Claims and Encounters Databases. Data are accessible after payment to Merative with an appropriate data use agreement. All analyses were approved by UNC's Institutional Review Board. No data are uploaded to this repository.
