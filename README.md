# ADS Coding Assessment
## Repository Structure
```text\
ads-coding-assessment/
├── README.md               
├── question_1_sdtm               
│   ├── 01_create_ds_domain.R           # R script for creating SDTM DS domain
│   ├── ds.csv                          # Output: DS domain (csv format)
│   ├── ds.rds                          # Output: DS domain (R data format)
│   └── 01_create_ds_domain.log         # Output: Script log
├── question_2_adam
│   ├── create_adsl.R                   # R script for creating ADSL dataset
│   ├── adsl.csv                        # Output: ADSL dataset (csv format)
│   ├── adsl.rds                        # Output: ADSL dataset (R data format)
│   └── create_adsl.log                 # Output: Script log
├── question_3_tlg
│   ├── 01_create_ae_summary_table.R    # R script for creating TEAE summary table
│   ├── 02_create_visualizations.R      # R script for creating AE visualizatoins
│   ├── g_ae_sev_dist.png               # Output: Graph (bar chart) of AE severity distribution by treatment (png format)
│   ├── g_ae_freq_top10.png             # Output: Graph (forest plot) of top 10 most frequent AEs (png format)
│   ├── 01_create_ae_summary_table.log  # Output: Script log
│   └── 02_create_visualizations.log    # Output: Script log
└── question_4_genai
    ├── create_clinical_agent.py        # Python script for creating GenAI clinical agent
    └── test_queries.py                 # Python script for testing the GenAI agent
```

## Description of Folders and Files
### `question_1_sdtm/`
- **Objective**: Create an SDTM DS domain from `pharmaverseraw::ds_raw` using `{sdtm.oak}`
- **Contents**:
  - `study_ct.csv` contains study controlled terminology used to standardize variables
  - `01_create_ds_domain.R` uses the `{sdtm.oak}` package to map raw variables to SDTM-compliant variables
  - Outputs and log files generated are included for reference
    - Outputs: `ds.csv`, `ds.rds`
      - Output variables in `ds.csv` include: \
        STUDYID, DOMAIN, USUBJID, DSSEQ, DSTERM, DSDECOD, DSCAT, VISITNUM, VISIT, DSDTC, DSSTDTC, DSSTDY
    - Log: `01_create_ds_domain.log`
- **Approach**:
  - Used `sdtm.oak::assign_no_ct()` for variables without controlled terminology (DSTERM)
  - Used `sdtm.oak::assign_ct()` for variables requiring controlled terminology mapping (DSDECOD, DSCAT, VISIT, VISITNUM) with `study_ct.csv`
  - **DSTERM** is derived per aCRF: Assign OTHERSP if not NA, otherwise assign IT.DSTERM
  - **DSDECOD** is derived per aCRF: Assign OTHERSP if not NA, otherwise assign IT.DSDECOD
  - **DSCAT** is derived per aCRF: (1) If OTHERSP is NA: If IT.DSDECOD is "Randomized" then assign "PROTOCOL MILESTONE", else assign "DISPOSITION EVENT" (2) If OTHERSP is not NA: Assign "OTHER EVENT"
  - **DSSTDTC** is mapped from `DSDTCOL` and `DSTMCOL` when hours and minutes are available, and mapped from `DSDTCOL` otherwise
  - **DSTDTC** is mapped from `IT.DSSTDAT`
  - **VISIT** and **VISITNUM** are mapped from `INSTANCE` 
  - **DSSTDY** is derived relative to `DM.RFSTDTC`
  - **DSSEQ** is generated last to capture sequence numbers
- **Key Decisions**:
  - Fixed minor case or spelling issues before mapping
  - Unscheduled visits not in the study controlled terminology were kept as-is, where VISIT shows the original value and VISITNUM is derived from the numeric portion
    
### `question_2_adam/`
- **Objective**: Create ADaM ADSL dataset from `pharmaversesdtm` sources using `{admiral}`
- **Contents**:
  - `create_adsl.R` uses the `{admiral}` package to create the ADSL dataset and derives key study variables
    - **ITTFL**: Randomization flag
    - **AGEGR9, AGEGR9N**: Age grouping
    - **TRTSDTM, TRTSDTMF**: Treatment start datetime and time flag
    - **LSTAVLDT**: Last known alive date
  - Outputs and log files generated are included for reference
    - Outputs: `adsl.csv`, `adsl.rds`
    - Log: `create_adsl.log`
- **Approach**:
    - **ITTFL**: `Y` when `DM.ARM` not missing; `N` otherwise
    - **AGEGR9, AGEGR9N**: Age thresholds `<18`, `18–50`, `>50` mapped to numeric codes `1`, `2`, `3`
    - **TRTSDTM, TRTSDTMF**: First `EX.EXSTDTC`, impute the earliest possible time
    - **LSTAVLDT**: Latest of
      (1) LSTVSDT: Last complete date of vital assessment with valid result
      (2) LSTAEDT: Last complete AE onset date
      (3) LSTDSDT: Last complete disposition date
      (4) TRTEDT: Last date of treatment with valid dose
- **Key Decisions**:
  - Valid dose: `EXSTDTM` not missing and [ `EXDOSE > 0` or (`EXDOSE == 0` and `EXTRT` contains `"PLACEBO"`) ]

### `question_3_tlg/`
- **Objective**: Create visual outputs for adverse events summary using the `pharmaverseadam::adae` dataset and `{gtsummary}`
- **Contents**:
  - `01_create_ae_summary_table.R` uses the `{gtsummary}` package to create a summary table of treatment-emergent adverse events (TEAEs).
  - `02_create_visualizations.R` uses the `{ggplot2}` package to create two adverse events visualizations
  - Outputs and log files generated are included for reference
    - Outputs:
      - `g_ae_sev_dist.png`: Bar chart of AE severity distribution by treatment
      - `g_ae_freq_top10.png`: Forest plot of the top 10 most frequent adverse events along with the 95% confidence intervals for incidence rates
    - Log: `01_create_ae_summary_table.log`, `02_create_visualizations.log`
- **Approach**:
  - Filters to TEAEs (`TRTEMFL == "Y"`)
    - Part 1:
      - Rows: AESOC (System Organ Class), AEDECOD (Preferred Term)
      - Columns: ACTARM (Treatment Groups, Total)
    - Part 2:
      - Subject-level incidence rate (counting distinct `USUBJID` per `AETERM`)
      - Clopper-Pearson exact binomial 95% confidence intervals
- **Key Decisions**:
  - Part 1: Adds a total column using `add_overall()`
  - Part 2: Denominators are the population from ADSL (not just subjects with AEs)
  
### `question_4_genai/` (Bonus) 
- **Objective**: Develop a Generative AI Assistant that translates natural language questions into structured Pandas queries.
- **Contents**:
  - `create_clinical_agent.py`
  - `test_queries.py`
- **Approach**:
  The agent follows a three-stage pipeline for every query:
    Question → LLM Parse → Pandas Execute
  1. The user's free-text question is sent to the LLM along with a crafted schema description that explains every relevant AE column and how to map clinical language to column names
  2. The LLM returns a structured `JSON` object with exactly two fields:   target_column   and   filter_value  
  3. That `JSON` is handed directly to a `Pandas` filter, which returns the unique subject count and subject IDs

- **Key Decisions**:
  - Schema-in-prompt rather than fine-tuning: Easy to update 
  - Case-insensitive matching at filter time: Convert to uppercase before comparing
  - Environment-aware client setup: Local or Replit
    
## Setup and Running
### R (Questions 1–3)
- **R version**: 4.2.0 or above
- **Packages**: `dplyr`, `stringr`, `lubridate`, `ggplot2`, `sdtm.oak`, `admiral`, `gt`, `gtsummary`, `webshot2`, `pharmaverseraw`, `pharmaverseadam`

### Python (Question 4)
- **Python version**: 3.7.1 or above
- **Packages**: `sys`, `os`, `json`, `re`, `pandas`, `openai`

### How to Run
1. Clone this repository
2. Set the working directory to the repo root directory
3. Run scripts:
  ```text\
  source("question_1_sdtm/01_create_ds_domain.R")
  source("question_2_adam/create_adsl.R")
  source("question_3_tlg/01_create_ae_summary_table.R")
  source("question_3_tlg/02_create_visualizations.R")
  ```
  ```text\
  python create_clinical_agent.py  
  python test_queries.py  
  ```