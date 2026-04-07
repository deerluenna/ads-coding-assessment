# ============================================================================== 
# Question 1. SDTM DS Domain Creation using {sdtm.oak}
# ------------------------------------------------------------------------------
# Program:   01_create_ds_domain.R
# Objective: Create an SDTM Disposition (DS) domain dataset from raw clinical
#            trial data using the {sdtm.oak} package.
# Inputs:    pharmaverseraw::ds_raw
#            pharmaversesdtm::dm
#            study_ct.csv
# Outputs:   ds.csv
#            ds.rds
#            01_create_ds_domain_log.txt
# Author:    Luenna Wu
# Date:      April 2026
# ==============================================================================


# ------------------------------------------------------------------------------
#  Set Up Logging
# ------------------------------------------------------------------------------
log_file <- here("question_1_sdtm", "01_create_ds_domain.log")

# Open log connection and redirect all output and messages
con <- file(log_file, open = "wt")
sink(con, type = "output")
sink(con, type = "message")

cat("================================================================================\n")
cat("  EXECUTION LOG: 01_create_ds_domain.R\n")
cat(paste0("  R version     : ", R.version.string, "\n"))
cat(paste0("  sdtm.oak      : ", as.character(packageVersion("sdtm.oak")), "\n"))
cat(paste0("  pharmaverseraw: ", as.character(packageVersion("pharmaverseraw")), "\n"))
cat("================================================================================\n\n")



# ------------------------------------------------------------------------------
#  Load Packages
# ------------------------------------------------------------------------------
library(dplyr)
library(stringr)
library(lubridate)
library(here)
library(sdtm.oak)
library(pharmaverseraw)



# ------------------------------------------------------------------------------
#  Read in Data
# ------------------------------------------------------------------------------

# Raw DS dataset
ds_raw <- pharmaverseraw::ds_raw %>%
  generate_oak_id_vars(pat_var = "PATNUM", raw_src = "ds_raw")

# SDTM DM 
dm <- pharmaversesdtm::dm

# Study Controlled Terminology
study_ct <- read.csv("sdtm_ct.csv")



# ------------------------------------------------------------------------------
#  Map Topic Variable: DSTERM
# ------------------------------------------------------------------------------

# Process DSTERM based on aCRF: Assign OTHERSP if not NA, otherwise assign IT.DSTERM
ds_raw <- ds_raw %>%
  mutate(
    # USUBJID = paste(STUDY, PATNUM, sep = "-"),
    DSTERM0 = coalesce(OTHERSP, IT.DSTERM) # Get OTHERSP if not NA, otherwise IT.DSTERM
    # DSTERM0 = if_else(is.na(OTHERSP), IT.DSTERM, OTHERSP)
  )

# Use assign_no_ct() to map DSTERM
ds <- assign_no_ct(
  raw_dat = ds_raw,
  raw_var = "DSTERM0",
  tgt_var = "DSTERM",
  id_vars = oak_id_vars()
  )



# ------------------------------------------------------------------------------
#  Map Remaining Variables Using Study Controlled Terminology
# ------------------------------------------------------------------------------

# ----- DSDECOD ----- #
# Process DSDECOD based on aCRF: Assign OTHERSP if not NA, otherwise assign IT.DSDECOD
ds_raw <- ds_raw %>% 
  mutate(
    DSDECOD0 = coalesce(OTHERSP, IT.DSDECOD) # Get OTHERSP if not NA, otherwise IT.DSDECOD
  ) %>%
  
  # Fix minor case or spelling issues
  mutate(
    DSDECOD0 = case_when(
      DSDECOD0 == "Completed" ~ "Complete",
      DSDECOD0 == "Lost to Follow-Up" ~ "Lost To Follow-Up", 
      DSDECOD0 == "Screen Failure" ~ "Trial Screen Failure",
      DSDECOD0 == "Study Terminated by Sponsor" ~"Study Terminated By Sponsor",
      TRUE ~ DSDECOD0
    )
  )

# Map the standardized disposition term
ds <- ds %>% 
  assign_ct(
    raw_dat     = ds_raw,
    raw_var     = "DSDECOD0",       
    tgt_var     = "DSDECOD",
    ct_spec     = study_ct,        # Study controlled terminology
    ct_clst     = "C66727",        # Codelist: Disposition Reason
    id_vars = oak_id_vars()
  )  


# ----- DSCAT ----- #
# Process DSCAT based on aCRF: 
# (1) If OTHERSP is NA: If IT.DSDECOD is "Randomized" then assign "PROTOCOL MILESTONE", else assign "DISPOSITION EVENT"
# (2) If OTHERSP is not NA: Assign "OTHER EVENT"
ds_raw <- ds_raw %>% 
  mutate(
    DSCAT0 = if_else(is.na(OTHERSP), 
                if_else(IT.DSDECOD == "Randomized", "PROTOCOL MILESTONE", "DISPOSITION EVENT"), 
                  "OTHER EVENT")
  ) 

# Map the category for disposition event
ds <- ds %>% 
  assign_ct(
    raw_dat = ds_raw,
    raw_var = "DSCAT0",
    tgt_var = "DSCAT",
    ct_spec = study_ct,
    ct_clst = "C74558",
    id_vars = oak_id_vars()
  )


# ----- DSSTDTC ----- #
# Map DSSTDTC from IT.DSSTDAT
ds <- ds %>% 
  assign_datetime(
    tgt_var = "DSSTDTC",
    raw_dat = ds_raw,
    raw_var = "IT.DSSTDAT",
    raw_fmt = "m-d-y"
  )


# ----- DSDTC ----- #
# Create collection datetime in ISO8601 format
ds <- ds %>% 
  # Map DSDTC from DSDTCOL, DSTMCOL when hours and minutes are available
  assign_datetime(
    tgt_var = "DSDTC_DATE_TIME",
    raw_dat = ds_raw,
    raw_var = c("DSDTCOL", "DSTMCOL"),
    raw_fmt = c("m-d-y", "H:M")
  ) %>%
  # Map DSDTC from DSDTCOL when hours and minutes are unavailable
  assign_datetime(
    tgt_var = "DSDTC_DATE",
    raw_dat = ds_raw,
    raw_var = "DSDTCOL",
    raw_fmt = "m-d-y"
  ) %>%
  # Set DSDTC to m-d-y H:M form when hours and minutes are available,
  #  and  to m-d-y form when hours and minutes are unavailable
  mutate(DSDTC = coalesce(DSDTC_DATE_TIME, DSDTC_DATE)) %>%
  select(-DSDTC_DATE)


# ----- INSTANCE ----- #
# Fix minor  case or spelling issues
ds_raw <- ds_raw %>% 
  mutate(
    INSTANCE = case_when(
      INSTANCE == "Ambul Ecg Removal" ~ "Ambul ECG Removal",
      TRUE ~ INSTANCE
      )
  )

# Map VISIT from INSTANCE 
ds <- ds %>% 
  assign_ct(
    raw_dat = ds_raw,
    raw_var = "INSTANCE",
    tgt_var = "VISIT",
    ct_spec = study_ct,
    ct_clst = "VISIT",
    id_vars = oak_id_vars()
)

# Map VISITNUM from INSTANCE 
ds <- ds %>% 
  assign_ct(
    raw_dat = ds_raw,
    raw_var = "INSTANCE",
    tgt_var = "VISITNUM",
    ct_spec = study_ct,
    ct_clst = "VISITNUM",
    id_vars = oak_id_vars()
)

# For the unscheduled visits not mapped, extract the numeric part and save as VISITNUM
ds <- ds %>% 
  mutate(
    VISITNUM_clean = case_when(
      # For the unscheduled visits not mapped, extract the numeric part and save as VISITNUM
      str_detect(toupper(VISITNUM), "^UNSCHEDULED") ~  str_extract(VISITNUM, "[0-9]+\\.?[0-9]*"),
      # Else if VISITNUM contains only numbers, then save as is 
      str_detect(VISITNUM, "^[0-9]+\\.?[0-9]*$") ~ VISITNUM,
      TRUE ~ NA_character_
    ),
     # Convert to numeric
    VISITNUM = as.numeric(VISITNUM_clean)
  ) %>% 
  select(-VISITNUM_clean)




# ------------------------------------------------------------------------------
#  Create SDTM derived variables
# ------------------------------------------------------------------------------
ds_final <- ds %>%
  mutate(
    STUDYID = ds_raw$STUDY,
    DOMAIN = "DS",
    USUBJID = paste0("01-", patient_number), # Concatenate "01-" and patient_number to get USUBJID
    DSTERM = toupper(DSTERM), # Uppercase DSTERM
    VISIT = toupper(VISIT), # Uppercase  unscheduled visits not included in the study ct
  ) %>%
  
  # Derive sequence
  derive_seq(
    tgt_var = "DSSEQ",
    rec_vars = c("USUBJID", "DSTERM")
  ) %>%
  
  # Derive study day of start of event relative to sponsor defined RFSTDTC
  derive_study_day(
    sdtm_in = .,
    dm_domain = dm,
    tgdt = "DSSTDTC",
    refdt = "RFSTDTC",
    study_day_var = "DSSTDY",
    merge_key = "USUBJID"
  ) %>%
  select(
    "STUDYID", "DOMAIN", "USUBJID", "DSSEQ", "DSTERM", "DSDECOD", 
    "DSCAT", "VISITNUM", "VISIT", "DSDTC", "DSSTDTC", "DSSTDY"
  )



# ------------------------------------------------------------------------------
#  Save Outputs
# ------------------------------------------------------------------------------
saveRDS(ds_final, "ds_sdtm.rds")
write.csv(ds_final, "ds_sdtm.csv", row.names = FALSE, na = "") # Make NA empty



# ------------------------------------------------------------------------------
#  Close Log
# ------------------------------------------------------------------------------
# QC summary printed into log
cat("\n--- QC Summary ---\n")
cat(paste("Total DS records  :", nrow(ds_final), "\n"))
cat(paste("Unique subjects   :", n_distinct(ds_final$USUBJID), "\n"))

cat("\n--- Final DS Head ---\n")
print(head(ds_final, 5))

cat("\n--- Variable Types ---\n")
print(sapply(ds_final, class))

cat("✓ Saved: question_1_sdtm/ds_sdtm.rds\n")
cat("✓ Saved: question_1_sdtm/ds_sdtm.csv\n")

cat("\n=== Script completed successfully with NO ERRORS ===\n")
cat("================================================================================\n")

# Restore sinks and close connection
sink(type = "message")
sink(type = "output")
close(con)

message(paste("Log saved to:", log_file))
