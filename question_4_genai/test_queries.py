"""
Test Script: ClinicalTrialDataAgent — 3 Example Queries
=============================================================
Run with:
    python question_4_genai/test_queries.py
"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

from create_clinical_agent import ClinicalTrialDataAgent


def print_result(result: dict):
    print("=" * 60)
    print(f"Question      : {result['question']}")
    print(f"Mapped Column : {result['target_column']}")
    print(f"Filter Value  : {result['filter_value']}")
    print(f"Matching Rows : {result['matching_rows']}")
    print(f"Subject Count : {result['subject_count']}")
    print(f"Subject IDs   :")
    for sid in result["subject_ids"]:
        print(f"               {sid}")
    print("=" * 60)


def main():
    data_path = os.path.join(os.path.dirname(__file__), "ae.csv")
    agent = ClinicalTrialDataAgent(data_path=data_path)

    test_questions = [
        "Give me the subjects who had Adverse events of Moderate severity.",
        "Which patients experienced a Headache?",
        "Show me subjects who had AEs related to the Cardiac body system.",
    ]

    print("\n" + "=" * 60)
    print("  CLINICAL TRIAL DATA AGENT — TEST QUERIES")
    print("=" * 60)

    for question in test_questions:
        result = agent.ask(question)
        print_result(result)


if __name__ == "__main__":
    main()
