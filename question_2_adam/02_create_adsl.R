# ============================================================================== 
# Question 1. ADaM ADSL Dataset Creation using {admiral}
# ------------------------------------------------------------------------------
# Program:   02_create_adsl.R
# Objective: Create ADaM ADSL dataset using {admiral} and pharmaversesdtm
# Inputs:    pharmaversesdtm::dm
#            pharmaversesdtm::vs
#            pharmaversesdtm::ex
#            pharmaversesdtm::ds
#            pharmaversesdtm::ae
# Outputs:   adsl.csv
#            adsl.rds
#            02_create_adsl.log
# Author:    Luenna Wu
# Date:      April 2026
# ==============================================================================


# ------------------------------------------------------------------------------
#  Set Up Logging
# ------------------------------------------------------------------------------
log_file <- here("question_2_adam", "02_create_adsl.log")

# Open log connection and redirect all output and messages
con <- file(log_file, open = "wt")
sink(con, type = "output")
sink(con, type = "message")

cat("================================================================================\n")
cat("  EXECUTION LOG: 02_create_adsl.R\n")
cat(paste0("  R version     : ", R.version.string, "\n"))
cat(paste0("  admiral      : ", as.character(packageVersion("admiral")), "\n"))
cat(paste0("  pharmaversesdtm: ", as.character(packageVersion("pharmaversesdtm")), "\n"))
cat("================================================================================\n\n")



# ------------------------------------------------------------------------------
#  Load Packages
# ------------------------------------------------------------------------------
library(dplyr)
library(stringr)
library(lubridate)
library(here)
library(admiral)
library(pharmaversesdtm)



# ------------------------------------------------------------------------------
#  Read in Data
# ------------------------------------------------------------------------------

# Raw DS dataset
dm <- pharmaversesdtm::dm # Demographics
vs <- pharmaversesdtm::vs # Vital signs 
ex <- pharmaversesdtm::ex # Exposure 
ds <- pharmaversesdtm::ds # Disposition
ae <- pharmaversesdtm::ae # Adverse event 
suppdm <- pharmaversesdtm::suppdm

# Preprocess datasets: convert blanks to NA
dm <- convert_blanks_to_na(dm)  
vs <- convert_blanks_to_na(vs) 
ex <- convert_blanks_to_na(ex) 
ds <- convert_blanks_to_na(ds)  
ae <- convert_blanks_to_na(ae) 



# ------------------------------------------------------------------------------
#  Initialize ADSL Object with DM Domain
# ------------------------------------------------------------------------------

# Assign DM to ADSL and remove DOMAIN variable
adsl <- dm %>%
  select(-DOMAIN)



# ------------------------------------------------------------------------------
#  Derive Variables
# ------------------------------------------------------------------------------

# ----- AGEGR9, AGEGR9N ----- #
# Derive age grouping variables
adsl <- adsl %>%
  mutate(
    AGEGR9 = case_when(
      AGE < 18 ~ "<18",
      AGE >= 18 & AGE <= 50 ~ "18-50",
      AGE > 50 ~ ">50",
      TRUE ~ NA_character_ # Handles missing values
    ),AGEGR9N = case_when(
      AGE < 18 ~ 1,
      AGE >= 18 & AGE <= 50 ~ 2,
      AGE > 50 ~ 3, 
      TRUE ~ NA_integer_
    )
  )


# ----- TRTSDTM, TRTSTMF ----- #
# Derive treatment start/end date-time variables
ex_ext <- ex %>%
  # Derive treatment start date
  derive_vars_dtm(
    dtc = EXSTDTC, # Treatment start date-time 
    new_vars_prefix = "EXST", # Start of variable names created 
    time_imputation = "first", # If time is missing, impute the earliest possible time
    ignore_seconds_flag = TRUE # If only seconds are missing, do not populate imputation flag
  )%>%
  # Derive treatment start date
  derive_vars_dtm(
    dtc = EXENDTC, # Treatment end date-time 
    new_vars_prefix = "EXEN",
    time_imputation = "last" # If time is missing, impute the latest possible time
  )

adsl_1 <- adsl %>%
  derive_vars_merged(
    dataset_add = ex_ext, # Add variables to ADSL from ex_ext
    # Choose valid dose: date exist and [dose>0 or placebo]
    filter_add = (EXDOSE > 0 |
                    (EXDOSE == 0 &
                       str_detect(EXTRT, "PLACEBO"))) & !is.na(EXSTDTM),
    new_vars = exprs(TRTSDTM = EXSTDTM, TRTSTMF = EXSTTMF), # Set the names of new treatment start variables added
    order = exprs(EXSTDTM, EXSEQ), # Sort in start date-time order and exposure sequence
    mode = "first",
    by_vars = exprs(STUDYID, USUBJID)
  )%>%
  derive_vars_merged(
    dataset_add = ex_ext,
    # Choose valid dose: date exist and [dose>0 or placebo]
    filter_add = (EXDOSE > 0 |
                    (EXDOSE == 0 &
                       str_detect(EXTRT, "PLACEBO"))) & !is.na(EXENDTM),
    new_vars = exprs(TRTEDTM = EXENDTM, TRTETMF = EXENTMF), # Set the names of new treatment end variables added
    order = exprs(EXENDTM, EXSEQ), # Sort in end date-time order and exposure sequence
    mode = "last",
    by_vars = exprs(STUDYID, USUBJID)
  )


# ----- ITTFL ----- #
# Derive randomization flag
adsl_2 <- adsl_1 %>%
  derive_vars_merged(
    dataset_add = dm, # Add variable to ADSL from DM
    new_vars = exprs(
      # If ARM is populated (not NA), then set ITTFL to "Y"
      #  else if ARM is not populated (NA), set ITTFL to "N"
      ITTFL = if_else(!is.na(ARM), "Y", "N")
    ),
    by_vars = exprs(STUDYID, USUBJID) # Join on STUDYID and USUBJID
  )


# ----- LSTAVLDT ----- #
# Derive last know alive date: set to max date of
# (1) LSTVSDT: Last complete date of vital assessment with valid result
# (2) LSTAEDT : Last complete AE onset date
# (3) LSTDSDT : Last complete disposition date
# (4) TRTEDT: Last date of treatment with valid dose (already derived, only need conversion to date)

# (1) LSTVSDT: Last complete date of vital assessment with valid result
vs_last <- vs %>%
  mutate(
    VSDT = as.Date(substr(VSDTC, 1, 10)), # Convert VSDTC date part from character to date
    VS_VALID = !(is.na(VSSTRESN) & (is.na(VSSTRESC) | VSSTRESC == "")) # VSSTRESN and VSSTRESC not missing
  ) %>%
  filter(!is.na(VSDT)) %>% # VSDTC date part not missing
  filter(VS_VALID == TRUE) %>% # Valid VS result
  group_by(STUDYID, USUBJID) %>%
  summarise(LSTVSDT = max(VSDT, na.rm = TRUE), .groups = "drop") # Get last date

# (2) LSTAEDT : Last complete AE onset date
ae_last <- ae %>%
  mutate(
    AESTDT  = as.Date(substr(AESTDTC, 1, 10)), # Convert AESTDTC date part from character to date
  ) %>%
  filter(!is.na(AESTDT)) %>% # AESTDTC date part not missing
  group_by(STUDYID, USUBJID) %>%
  summarise(LSTAEDT  = max(AESTDT, na.rm = TRUE), .groups = "drop") # Get last date

# (3) LSTDSDT : Last complete disposition date
ds_last <- ds %>%
  mutate(
    DSSTDT  = as.Date(substr(DSSTDTC, 1, 10)), # Convert DSSTDTC date part from character to date
  ) %>%
  filter(!is.na(DSSTDT)) %>% # DSSTDTC date part not missing
  group_by(STUDYID, USUBJID) %>%
  summarise(LSTDSDT  = max(DSSTDT, na.rm = TRUE), .groups = "drop") # Get last date


# Merge last dates into ADSL
adsl_final <- adsl_2 %>%
  left_join(vs_last, by = c("STUDYID", "USUBJID")) %>%
  left_join(ae_last, by = c("STUDYID", "USUBJID")) %>%
  left_join(ds_last, by = c("STUDYID", "USUBJID")) %>%
  mutate(
    TRTEDT = as.Date(substr(TRTEDTM, 1, 10)), # Convert TRTEDTM date part from character to date
    LSTAVLDT = pmax(LSTVSDT, LSTAEDT, LSTDSDT, TRTEDT, na.rm = TRUE), # Get max of the last dates
  ) %>% 
  select(-LSTVSDT, -LSTAEDT, -LSTDSDT) %>% 
  arrange(USUBJID)



# ------------------------------------------------------------------------------
#  Save Outputs
# ------------------------------------------------------------------------------
saveRDS(adsl_final, "adsl.rds")
write.csv(adsl_final, "adsl.csv", row.names = FALSE, na = "") # Make NA empty



# ------------------------------------------------------------------------------
#  Close Log
# ------------------------------------------------------------------------------
# QC summary printed into log
cat("\n--- QC Summary ---\n")
cat(paste("Total ADSL records  :", nrow(adsl_final), "\n"))
cat(paste("Unique subjects   :", n_distinct(adsl_final$USUBJID), "\n"))

cat("\n--- Final ADSL Head ---\n")
print(head(adsl_final, 5))

cat("\n--- Variable Types ---\n")
print(sapply(adsl_final, class))

cat("✓ Saved: question_2_adam/adsl.rds\n")
cat("✓ Saved: question_2_adam/adsl_.csv\n")

cat("\n=== Script completed successfully with NO ERRORS ===\n")
cat("================================================================================\n")

# Restore sinks and close connection
sink(type = "message")
sink(type = "output")
close(con)

message(paste("Log saved to:", log_file))
