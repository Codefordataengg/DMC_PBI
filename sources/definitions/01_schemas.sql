/* The three layers. Names match the real estate exactly. */

DEFINE SCHEMA DEVELOP.LND
    COMMENT = 'Landing. Raw drop zones and append-only envelopes.';

DEFINE SCHEMA DEVELOP.STG
    COMMENT = 'Staging. Per-run snapshots, rebuilt each load.';

DEFINE SCHEMA DEVELOP.PRE
    COMMENT = 'Presentation. Merge targets consumed downstream.';
