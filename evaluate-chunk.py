#!/usr/bin/env python3
"""Write evaluation results for a chunk. Called with a JSON ratings file."""
import json, sys, os

def main():
    if len(sys.argv) != 4:
        print("Usage: evaluate-chunk.py <model-dir> <run> <ratings-json-file>")
        sys.exit(1)

    model_dir = sys.argv[1]
    run = sys.argv[2]
    ratings_file = sys.argv[3]

    with open(ratings_file) as f:
        ratings = json.load(f)

    output_dir = os.path.join(model_dir, f"run{run}", "evaluations")
    os.makedirs(output_dir, exist_ok=True)

    for qid, rating in ratings.items():
        result = {
            "evaluator": "claude-opus-4.6",
            "evaluator_version": "2026-03",
            "question_id": qid,
            "section": rating.get("section", ""),
            "difficulty": rating.get("difficulty", ""),
            "model_tested": rating.get("model", ""),
            "rating": rating["rating"],
            "points": rating["points"],
            "max_points": 2,
            "key_points_correct": rating.get("correct", []),
            "key_points_missing": rating.get("missing", []),
            "key_points_wrong": rating.get("wrong", []),
            "brief_justification": rating.get("justification", "")
        }
        with open(os.path.join(output_dir, f"{qid}.json"), 'w') as f:
            json.dump(result, f, indent=2)

    # Summary
    total = sum(r["points"] for r in ratings.values())
    max_pts = len(ratings) * 2
    print(f"Wrote {len(ratings)} evaluations to {output_dir}")
    print(f"Score: {total}/{max_pts} ({100*total/max_pts:.1f}%)")

if __name__ == "__main__":
    main()
