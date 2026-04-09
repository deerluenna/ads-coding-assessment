"""
ClinicalTrialDataAgent
===========================
Translates natural language questions into structured Pandas queries
against the AE (Adverse Events) dataset using an LLM.

Flow: User Question → LLM (with schema context) → JSON {target_column, filter_value}
      → Pandas filter → {count, subject_ids}
"""

import os
import json
import re
import pandas as pd
from openai import OpenAI


def _load_api_key() -> str:
    """
    Load the OpenAI API key using this priority order:
    1. api_key.txt file (same folder as this script)
    2. OPENAI_API_KEY environment variable
    3. AI_INTEGRATIONS_OPENAI_API_KEY env var (for Replit)
    """
    key_file = os.path.join(os.path.dirname(__file__), "api_key.txt")
    if os.path.exists(key_file):
        with open(key_file, "r") as f:
            key = f.read().strip()
        if key:
            return key

    for env_var in ("OPENAI_API_KEY", "AI_INTEGRATIONS_OPENAI_API_KEY"):
        key = os.environ.get(env_var, "").strip()
        if key and key != "dummy-key":
            return key

    raise ValueError(
        "No OpenAI API key found.\n"
        "Please either:\n"
        "  1. Create question_4_genai/api_key.txt and paste your key inside, or\n"
        "  2. Set the OPENAI_API_KEY environment variable."
    )


AE_SCHEMA = """
You are a clinical data assistant. The dataset is an Adverse Events (AE) table from pharmaversesdtm.
Below is a description of the relevant columns:

Column Descriptions:
- STUDYID    : Study Identifier
- DOMAIN     : Dataset domain (AE for this dataset)
- USUBJID    : Unique Subject Identifier — identifies each patient/participant uniquely
- AETERM     : Adverse Event Term — the specific medical event or condition (e.g. HEADACHE, NAUSEA, DIARRHOEA)
- AESEV      : Severity of the adverse event. Valid values: MILD, MODERATE, SEVERE
- AESER      : Serious Adverse Event flag. Y = Serious, N = Not serious
- AESOC      : System Organ Class — the body system affected (e.g. CARDIAC DISORDERS, GASTROINTESTINAL DISORDERS, INFECTIONS AND INFESTATIONS, MUSCULOSKELETAL AND CONNECTIVE TISSUE DISORDERS, 
                                                                   NERVOUS SYSTEM DISORDERS, PSYCHIATRIC DISORDERS, RENAL AND URINARY DISORDERS, SKIN AND SUBCUTANEOUS TISSUE DISORDERS)
- AEOUT      : Outcome of the event (e.g. RECOVERED/RESOLVED, NOT RECOVERED/NOT RESOLVED, FATAL)
- AESEQ      : Sequence number of the adverse event per subject

When the user asks about:
- "severity" or "intensity" → use AESEV
- a specific condition or symptom (e.g., "Headache", "Nausea") → use AETERM
- a body system or organ class (e.g., "Cardiac", "Skin", "Nervous system") → use AESOC
- whether an event is serious → use AESER
- outcome or resolution → use AEOUT

IMPORTANT for filter values:
- AESEV values must be: MILD, MODERATE, or SEVERE (uppercase)
- AESER values must be: Y or N
- AETERM values should be uppercase (e.g., HEADACHE)
- AESOC values should be all upper case matching the dataset (e.g., "CARDIAC DISORDERS")
"""

QUERY_PROMPT_TEMPLATE = """
{schema}

The user asks: "{question}"

Based on the question, identify:
1. The most appropriate column to filter on (target_column)
2. The exact value to filter for (filter_value), normalized to match the dataset values

Respond ONLY with a valid JSON object in this format (no explanation, no markdown):
{{"target_column": "<column_name>", "filter_value": "<value>"}}
"""


class ClinicalTrialDataAgent:
    """
    AI-powered clinical data agent that maps natural language questions to Pandas queries
    on the AE (Adverse Events) clinical trial dataset.
    """

    def __init__(self, data_path: str):
        """
        Initialize the agent with a path to the AE csv file.

        Parameters
        ----------
        data_path : str
            Path to ae.csv
        """
        self.df = pd.read_csv(data_path)
        self._normalize_data()

        replit_base_url = os.environ.get("AI_INTEGRATIONS_OPENAI_BASE_URL")

        if replit_base_url:
            replit_key = os.environ.get("AI_INTEGRATIONS_OPENAI_API_KEY", "dummy-key")
            self.client = OpenAI(base_url=replit_base_url, api_key=replit_key)
            self.model = "gpt-5.2"
        else:
            api_key = _load_api_key()
            self.client = OpenAI(api_key=api_key)
            self.model = "gpt-4o-mini"

    def _normalize_data(self):
        """Normalize string columns to uppercase for consistent matching."""
        str_cols = ["AETERM", "AESEV", "AESER", "AEOUT", "AESOC"]
        for col in str_cols:
            if col in self.df.columns:
                self.df[col] = self.df[col].str.strip().str.upper()

    def _parse_question_with_llm(self, question: str) -> dict:
        """
        Send the user's question to the LLM and get back a structured
        JSON with target_column and filter_value.

        Parameters
        ----------
        question : str
            The free-text clinical question

        Returns
        -------
        dict
            {"target_column": str, "filter_value": str}
        """
        prompt = QUERY_PROMPT_TEMPLATE.format(
            schema=AE_SCHEMA,
            question=question
        )

        response = self.client.chat.completions.create(
            model=self.model,
            max_completion_tokens=256,
            messages=[
                {"role": "system", "content": "You are a clinical data parsing assistant. Always respond with valid JSON only."},
                {"role": "user", "content": prompt}
            ]
        )

        raw_text = response.choices[0].message.content.strip()

        json_match = re.search(r'\{.*\}', raw_text, re.DOTALL)
        if json_match:
            raw_text = json_match.group(0)

        parsed = json.loads(raw_text)

        if "target_column" not in parsed or "filter_value" not in parsed:
            raise ValueError(f"LLM returned unexpected JSON structure: {parsed}")

        return parsed

    def _apply_filter(self, target_column: str, filter_value: str) -> dict:
        """
        Apply a Pandas filter to the AE dataframe based on structured output.

        Parameters
        ----------
        target_column : str
            The column to filter on (e.g., AESEV, AETERM, AESOC)
        filter_value : str
            The value to search for (case-insensitive matching)

        Returns
        -------
        dict
            {
              "target_column": str,
              "filter_value": str,
              "subject_count": int,
              "subject_ids": list[str],
              "matching_rows": int
            }
        """
        if target_column not in self.df.columns:
            raise ValueError(
                f"Column '{target_column}' not found in dataset. "
                f"Available columns: {list(self.df.columns)}"
            )

        col_data = self.df[target_column].astype(str).str.upper()
        search_value = str(filter_value).strip().upper()

        mask = col_data.str.contains(search_value, na=False)
        filtered_df = self.df[mask]

        unique_subjects = filtered_df["USUBJID"].unique().tolist()
        subject_count = len(unique_subjects)

        return {
            "target_column": target_column,
            "filter_value": filter_value,
            "subject_count": subject_count,
            "subject_ids": sorted(unique_subjects),
            "matching_rows": len(filtered_df)
        }

    def ask(self, question: str) -> dict:
        """
        Main entry point: translate a natural language question into a
        Pandas query and return results.
        Full pipeline: Question → LLM Parse → Structured JSON → Pandas Filter → Results

        Parameters
        ----------
        question : str
            Natural language clinical question

        Returns
        -------
        dict
            {
              "question": str,
              "target_column": str,
              "filter_value": str,
              "subject_count": int,
              "subject_ids": list[str],
              "matching_rows": int
            }
        """
        print(f"\n[AGENT] Question: {question}")

        structured = self._parse_question_with_llm(question)
        print(f"[AGENT] LLM parsed → target_column='{structured['target_column']}', "
              f"filter_value='{structured['filter_value']}'")

        results = self._apply_filter(structured["target_column"], structured["filter_value"])
        results["question"] = question

        return results
