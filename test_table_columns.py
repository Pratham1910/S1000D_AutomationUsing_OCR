#!/usr/bin/env python3
"""Test column count detection for flattened tables."""

import re
from S1000D_Converter_Suite import (
    _heuristic_unflatten_pipe_table,
    _is_plausible_adoc_table,
    _looks_like_flattened_pipe_table,
    _table_text_to_adoc_block,
    _sanitize_cell_for_table,
)

def debug_heuristic(raw_text: str):
    """Debug version of heuristic to see internal scoring."""
    t = (raw_text or "").strip()
    if not _looks_like_flattened_pipe_table(t):
        print(f"  Not flattened: {t[:60]}")
        return
    
    tokens = [_sanitize_cell_for_table(c) for c in t.split("|")]
    while tokens and not tokens[0]:
        tokens.pop(0)
    while tokens and not tokens[-1]:
        tokens.pop()
    print(f"  Tokens: {tokens}")
    
    schedule_keywords = sum(1 for tok in tokens if re.search(
        r"\b(daily|weekly|month|year|hour|hrs?|schedule|interval)\b", tok, re.IGNORECASE))
    print(f"  Schedule keywords found: {schedule_keywords}")
    
    col_scores = {}
    for potential_cols in range(2, min(13, len(tokens) // 2 + 1)):
        complete_rows = (len(tokens) + potential_cols - 1) // potential_cols
        score = 1.0 / complete_rows
        if schedule_keywords > 0 and potential_cols in (schedule_keywords, schedule_keywords + 1):
            score *= 2.5
        if 5 <= potential_cols <= 7:
            score *= 1.5
        if complete_rows <= 1:
            score *= 0.3
        col_scores[potential_cols] = (score, complete_rows)
    
    print(f"  Column scores: {col_scores}")
    best_col = max(col_scores.keys(), key=lambda k: col_scores[k][0])
    print(f"  Best column count: {best_col} (score: {col_scores[best_col][0]:.3f})")

# Test case 1: Flattened pipe table that should become multi-column
test1 = "| Daily 8 Hours | 18 Months 500 Hours | Specific Issue | External Link | Notes"

print("=" * 60)
print("Test 1: Flattened pipe-separated string")
print(f"Input: {test1}")
print(f"Looks flattened: {_looks_like_flattened_pipe_table(test1)}")

if _looks_like_flattened_pipe_table(test1):
    heur = _heuristic_unflatten_pipe_table(test1)
    print(f"\nHeuristic result:")
    print(heur)
    print(f"\nIs plausible: {_is_plausible_adoc_table(heur)}")
    if heur:
        col_count = heur.count("|") // max(1, heur.count("\n") - 1)
        print(f"Column count: {col_count}")

print("\n" + "=" * 60)
print("Test 2: Full table conversion")
result = _table_text_to_adoc_block(test1)
print(f"Final result:\n{result}")

# Calculate actual column count
if result:
    pipe_count = result.count("|") - 2  # Subtract the |=== delimiters
    newline_count = result.count("\n")
    if newline_count > 2:
        actual_cols = pipe_count // (newline_count - 2)
        print(f"Actual columns in result: {actual_cols}")

# Test case 3: More realistic mangled table
test2 = "| Line 1 Col A | Line 1 Col B | Line 1 Col C | Line 1 Col D | Line 1 Col E | Line 2 Col A | Line 2 Col B | Line 2 Col C | Line 2 Col D | Line 2 Col E"
print("\n" + "=" * 60)
print("Test 3: Longer pipe-separated string (10 cells)")
print(f"Input length: {len(test2)} chars, cell count: {test2.count('|')}")
debug_heuristic(test2)

if _looks_like_flattened_pipe_table(test2):
    heur = _heuristic_unflatten_pipe_table(test2)
    if heur:
        col_count = heur.count("|") // max(1, heur.count("\n") - 1)
        print(f"Actual column count in output: {col_count}")
        print(f"First 200 chars of heuristic result:\n{heur[:200]}")

result2 = _table_text_to_adoc_block(test2)
print(f"\nFinal result (first 300 chars):\n{result2[:300]}")

# Test case 3: Realistic schedule table with keywords
test3 = "| Activity 1 | Daily | Weekly | Monthly | Yearly | Notes | Activity 2 | Daily | Weekly | Monthly | Yearly | Notes"
print("\n" + "=" * 60)
print("Test 4: Schedule table with keywords")
print(f"Input: {test3[:80]}...")
debug_heuristic(test3)

if _looks_like_flattened_pipe_table(test3):
    heur = _heuristic_unflatten_pipe_table(test3)
    if heur:
        col_count = heur.count("|") // max(1, heur.count("\n") - 1)
        print(f"Actual column count in output: {col_count}")
        print(f"Heuristic result:\n{heur[:300]}")

result3 = _table_text_to_adoc_block(test3)
print(f"\nFinal result:\n{result3[:300]}")
