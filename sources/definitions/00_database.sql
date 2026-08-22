/* The POC database is named DEVELOP deliberately.

   The pipeline DDL is schema-qualified but NOT database-qualified
   (LND."PBI_AllCapacities"), so a database name has to be supplied here
   regardless. Using the same name the real dev database uses keeps these
   definitions directly comparable with target-state/GET_DDL_2026-08-22.txt
   and removes a class of transplant error.

   This is the PERSONAL account. It is not the Snowy DEVELOP database.

   CDM_DEV is a Matillion environment name and is not a database. Do not use it here. */

DEFINE DATABASE DEVELOP
    COMMENT = 'Power BI governance estate - DCM POC. Structural only, no data.';
