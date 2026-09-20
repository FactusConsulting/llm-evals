#!/usr/bin/env python3
"""Summary of one tau2 run. Runs on the eval server, in tau2's environment.

    summarize.py <simulations-dir> <run-dir> [max-tokens]

tau2's own metrics hide two things a reader has to see. Simulations that ended
in infrastructure_error are dropped from the averages with a log line, so a
dead endpoint shrinks the denominator instead of failing the run. And every
simulation that did not end in agent_stop or user_stop scores 0 for the agent,
including user_error — the user simulator breaking its own protocol. Both are
counted here, and so are the turns that spent the whole max_tokens budget and
were cut off. Exits 3 when no simulation reached a verdict.
"""
import json
import sys
from collections import Counter
from pathlib import Path

from tau2.data_model.simulation import Results
from tau2.metrics.agent_metrics import compute_metrics


def find_results(sim_dir: Path) -> Path:
    for candidate in (sim_dir / "results.json", sim_dir):
        if candidate.exists():
            return candidate
    sys.exit(f"tau2 wrote no results under {sim_dir}")


def truncated_turns(results: Results, max_tokens: int) -> dict[str, int]:
    counts = {"agent": 0, "user": 0}
    for sim in results.simulations:
        for message in sim.messages or []:
            spent = (getattr(message, "usage", None) or {}).get("completion_tokens") or 0
            role = {"assistant": "agent", "user": "user"}.get(message.role)
            if role and max_tokens and spent >= max_tokens:
                counts[role] += 1
    return counts


def main(sim_dir: Path, run: Path, max_tokens: int) -> int:
    results = Results.load(find_results(sim_dir))
    num_trials = results.info.num_trials
    metrics = compute_metrics(results)

    terminations = Counter(
        getattr(s.termination_reason, "value", str(s.termination_reason))
        for s in results.simulations
    )
    expected = len(results.tasks) * num_trials
    judged = len(results.simulations) - terminations.get("infrastructure_error", 0)

    summary = {
        "domain": results.info.environment_info.domain_name,
        "agent_llm": results.info.agent_info.llm,
        "user_llm": results.info.user_info.llm,
        "tasks": len(results.tasks),
        "trials": num_trials,
        "simulations_expected": expected,
        "simulations_judged": judged,
        "avg_reward": metrics.avg_reward,
        "pass_hat_k": {str(k): v for k, v in sorted(metrics.pass_hat_ks.items())},
        "terminations": dict(terminations),
        "truncated_turns": truncated_turns(results, max_tokens),
    }
    (run / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")

    print(f"\n{summary['domain']}: {summary['tasks']} tasks x {num_trials} trials, "
          f"{judged} of {expected} simulations judged")
    print(f"  avg reward  {metrics.avg_reward:.3f}")
    for k, v in summary["pass_hat_k"].items():
        print(f"  pass^{k}      {v:.3f}")
    print("  ended by    " + ", ".join(f"{r} {n}" for r, n in terminations.most_common()))

    return 3 if judged == 0 else 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1]), Path(sys.argv[2]),
                  int(sys.argv[3] or 0) if len(sys.argv) > 3 else 0))
