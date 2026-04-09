# ============================================================================== 
# Question 3.  TLG - Adverse Events Reporting
#     Part 1.  Summary Table of TEAEs
# ------------------------------------------------------------------------------
# Program:   01_create_ae_summary_table.R
# Objective: Create a summary table of treatment-emergent adverse events (TEAEs) 
#            from ADAE dataset using {gtsummary}
# Inputs:    pharmaverseadam::adsl
#            pharmaverseadam::adae
# Outputs:   t_ae_summary.pdf
#            01_create_ae_summary_table.log
# Author:    Luenna Wu
# Date:      April 2026
# ==============================================================================


# ------------------------------------------------------------------------------
#  Load Packages
# ------------------------------------------------------------------------------
library(dplyr)
library(here)
library(gtsummary)
library(pharmaverseadam)
library(gt)
library(webshot2)



# ------------------------------------------------------------------------------
#  Set Up Logging
# ------------------------------------------------------------------------------
log_file <- here("question_3_tlg", "01_create_ae_summary_table.log")

# Open log connection and redirect all output and messages
con <- file(log_file, open = "wt")
sink(con, type = "output")
sink(con, type = "message")

cat("================================================================================\n")
cat("  EXECUTION LOG: 01_create_ae_summary_table.R\n")
cat(paste0("  R version     : ", R.version.string, "\n"))
cat(paste0("  admiral       : ", as.character(packageVersion("gtsummary")), "\n"))
cat(paste0("  pharmaverseadam: ", as.character(packageVersion("pharmaverseadam")), "\n"))
cat(paste0("  gt            : ", as.character(packageVersion("gt")), "\n"))
cat(paste0("  webshot2      : ", as.character(packageVersion("webshot2")), "\n"))
cat("================================================================================\n\n")



# ------------------------------------------------------------------------------
#  Read in Data
# ------------------------------------------------------------------------------

# ADaM datasets
adae <- pharmaverseadam::adae
adsl <- pharmaverseadam::adsl



# ------------------------------------------------------------------------------
#  Data Pre-processing
# ------------------------------------------------------------------------------

# Filter for treatment-emergent AE records
adae_te <- adae %>%
  filter(TRTEMFL == "Y")



# ------------------------------------------------------------------------------
#  Write Log
# ------------------------------------------------------------------------------

# QC summary printed into log
cat("\n--- QC Summary ---\n")
cat(paste("Total TEAE records  :", nrow(adae_te), "\n"))
cat(paste("Unique subjects   :", n_distinct(adae_te$USUBJID), "\n"))

cat("\n--- Treatment-emergent ADAE Head ---\n")
print(head(adae_te, 5))

cat("\n--- Variable Types ---\n")
print(sapply(adae_te, class))



# ------------------------------------------------------------------------------
#  Create summary table of treatment-emergent adverse events (TEAEs)
# ------------------------------------------------------------------------------

tbl <- tbl_hierarchical( # Create columns for each treatment group
    data = adae_te,  
    variables = c(AESOC, AETERM),
    by = ACTARM, # Stratify by treatment group
    id = USUBJID,
    denominator = adsl,
    overall_row = TRUE,
    label = "..ard_hierarchical_overall.." ~ "Treatment Emergent AEs",
  ) %>% 
  # Add overall column
  add_overall(col_label = "**Total**  \nN = {N}", ) %>% 
  sort_hierarchical() # Sort by overall column in decreasing frequency



# ------------------------------------------------------------------------------
#  Save Outputs
# ------------------------------------------------------------------------------

# Save the gtsummary object to allow future updates
# saveRDS(tbl, "t_ae_summary.rds")

# Save the gt object as PDF
tbl %>% 
  as_gt() %>% # Convert gtsummary object to gt object
  gt::tab_options(
    table.font.size = gt::pct(80)  # Make overall font 80% of default
  ) %>% 
  gt::cols_width(
    stat_0 ~ gt::px(150) # Update column width for Overall column
  ) %>% 
  gt::gtsave("t_ae_summary.pdf") # webshot2 loads gt table (HTML), snapshots it and save as pdf file



# ------------------------------------------------------------------------------
#  Write Log
# ------------------------------------------------------------------------------

# cat("✓ Saved: question_3_tlg/t_ae_summary.rds\n")
cat("✓ Saved: question_3_tlg/t_ae_summary.pdf\n")

cat("\n=== Script completed successfully with NO ERRORS ===\n")
cat("================================================================================\n")



# ------------------------------------------------------------------------------
#  Close Log
# ------------------------------------------------------------------------------
# Restore sinks and close connection
sink(type = "message")
sink(type = "output")
close(con)

message(paste("Log saved to:", log_file))
