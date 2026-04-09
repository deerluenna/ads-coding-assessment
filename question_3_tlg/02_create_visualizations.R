# ============================================================================== 
# Question 3.  TLG - Adverse Events Reporting
#     Part 2.  Visualizations for
#              (1) AE Severity Distribution: g_ae_sev_dist
#              (2) Top 10 Most Frequent AEs: g_ae_freq_top10
# ------------------------------------------------------------------------------
# Program:   02_create_visualizations.R
# Objective: Create graphs summarizing severity distribution and frequency for 
#            adverse events (AE) using the ADAE dataset and {ggplot2}.
# Inputs:    pharmaverseadam::adsl
#            pharmaverseadam::adae
# Outputs:   g_ae_sev_dist.png
#            g_ae_freq_top10.png
#            02_create_visualizations.log
# Author:    Luenna Wu
# Date:      April 2026
# ==============================================================================


# ------------------------------------------------------------------------------
#  Load Packages
# ------------------------------------------------------------------------------
library(dplyr)
library(here)
library(ggplot2)
library(pharmaverseadam)


# ------------------------------------------------------------------------------
#  Set Up Logging
# ------------------------------------------------------------------------------
log_file <- here("question_3_tlg", "02_create_visualizations.log")

# Open log connection and redirect all output and messages
con <- file(log_file, open = "wt")
sink(con, type = "output")
sink(con, type = "message")

cat("================================================================================\n")
cat("  EXECUTION LOG: 02_create_visualizations.R\n")
cat(paste0("  R version       : ", R.version.string, "\n"))
cat(paste0("  admiral         : ", as.character(packageVersion("gtsummary")), "\n"))
cat(paste0("  pharmaverseadam : ", as.character(packageVersion("pharmaverseadam")), "\n"))
cat(paste0("  gt              : ", as.character(packageVersion("gt")), "\n"))
cat(paste0("  webshot2        : ", as.character(packageVersion("webshot2")), "\n"))
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
  filter(TRTEMFL == "Y") %>% 
  select(USUBJID, ACTARM, AETERM, AESEV)



# ------------------------------------------------------------------------------
#  Create Plot 1: AE Severity Distribution by Treatment
# ------------------------------------------------------------------------------

p1 <- adae_te %>% 
  ggplot(aes(x = ACTARM, fill = AESEV)) +
  geom_bar() +
  labs(
    title = "AE Severity Distribution by Treatment",
    x = "Treatment Arm",
    y = "Count of AEs",
    fill = "Severity/Intensity"
  ) +
  theme_minimal()

p1



# ------------------------------------------------------------------------------
#  Create Plot 2: Top 10 most frequent AEs
# ------------------------------------------------------------------------------

# Process and summarize top 10 most frequent AEs
adae_summary <- adae_te %>% 
  group_by(AETERM) %>% # Group by AE type
  summarise(
    n_teae_pt = n_distinct(USUBJID), # Count unique patients per AE
    .groups = "drop"
  ) %>%
  mutate(
    n_pt = n_distinct(adsl$USUBJID),  # Total n of patients
    rate = n_teae_pt / n_pt # Calculate incidence rate
  ) %>% 
  rowwise() %>%
  mutate(
    # Calculate lower and upper confidence interval
    ci_lower = binom.test(n_teae_pt, n_pt, conf.level = 0.95)$conf.int[1],
    ci_upper  = binom.test(n_teae_pt, n_pt, conf.level = 0.95)$conf.int[2],
  ) %>%
  ungroup() %>%
  arrange(desc(n_teae_pt)) %>% # Arrange AEs by decreasing frequency
  slice(1:10) # Select top 10

# Create forest plot
p2 <- ggplot(adae_summary, 
             aes(x = rate, y = reorder(AETERM, rate), xmin = ci_lower, xmax = ci_upper)) +
  geom_point(position = position_dodge(width = 0.7), size = 3) +
  geom_errorbar(width = 0.2, orientation = "y") +
  scale_x_continuous(
    labels = scales::percent_format(accuracy = 1),
    limits = c(0, NA) # Starts at 0, "NA" lets the upper bound be automatic
  ) +
  labs(
    x = "Percentage of Patients (%)",
    y = "",
    title = "Top 10 Most Frequent Adverse Events (AEs)", 
    subtitle = "n = 306 Subjects; 95% Clopper-Pearson CIs"
  ) +
  theme_minimal() 

p2



# ------------------------------------------------------------------------------
#  Save Outputs
# ------------------------------------------------------------------------------

# Save the ggplot object to allow future updates
# saveRDS(p1, "g_ae_sev_dist.rds")
# saveRDS(p2, "g_ae_freq_top10.rds")

# Save the plots as PNG
ggsave("g_ae_sev_dist.png", p1, width = 8, height = 6)
ggsave("g_ae_freq_top10.png", p2, width = 8, height = 6)



# ------------------------------------------------------------------------------
#  Close Log
# ------------------------------------------------------------------------------

# QC summary printed into log
cat("\n--- QC Summary ---\n")
cat(paste("Total TEAE records          :", nrow(adae_te), "\n"))
cat(paste("Unique subjects on study    :", n_distinct(adsl$USUBJID), "\n"))
cat(paste("Unique subjects with AE     :", n_distinct(adae$USUBJID), "\n"))
cat(paste("Unique subjects with TEAE   :", n_distinct(adae_te$USUBJID), "\n"))

cat("\n--- Treatment-emergent ADAE Head ---\n")
print(head(adae_te, 5))

cat("\n--- Variable Types ---\n")
print(sapply(adae_te, class))

cat("✓ Saved: question_3_tlg/g_ae_sev_dist.png\n")
cat("✓ Saved: question_3_tlg/g_ae_freq_top10.png\n")

cat("\n=== Script completed successfully with NO ERRORS ===\n")
cat("================================================================================\n")

# Restore sinks and close connection
sink(type = "message")
sink(type = "output")
close(con)

message(paste("Log saved to:", log_file))
