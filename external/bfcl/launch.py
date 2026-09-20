#!/usr/bin/env python3
"""bfcl's CLI, with the model under test registered first.

bfcl resolves --model through a table compiled into the package
(bfcl_eval.constants.model_config.MODEL_CONFIG_MAPPING). A name that is not in
the table is rejected before any request is made, so an arbitrary model behind
an OpenAI-compatible endpoint cannot be named on bfcl's command line. This adds
one entry to the table, in this process only, and hands over to bfcl's own CLI:
generation, checking and scoring are upstream's code and nothing in
site-packages is edited.

The entry uses EndpointHandler below, a thin subclass of bfcl's
OpenAICompletionsHandler, which calls /v1/chat/completions through the openai
SDK and takes the endpoint and key from OPENAI_BASE_URL and OPENAI_API_KEY. bfcl
loads <BFCL_PROJECT_ROOT>/.env over the environment; the run directory has no
.env, so the environment is the only source of the key.

bfcl's handlers for open-weight models are not used: they render the chat
template client-side from a Hugging Face tokenizer and call /v1/completions,
which bypasses the server's template and tool-call parser — the parts of the
serving stack an agent depends on.

Environment:
  BFCL_MODEL       model name sent to the endpoint; also the --model value
  BFCL_MODE        fc      functions go in the request's `tools` field and the
                           answer is read from `tool_calls`
                   prompt  functions are described in the system prompt and the
                           answer is parsed from text
  BFCL_CATEGORIES  comma-separated categories or category groups
  BFCL_TEMPERATURE     if set, sent with every request; otherwise none is sent
  BFCL_MAX_TOKENS      if set and not 0, sent as max_tokens with every request
  BFCL_REQUEST_TIMEOUT seconds before the client gives up on one request
  BFCL_LIMIT       if set, `generate` runs only N cases of each category: the
                   ids are written to the project root's
                   test_case_ids_to_generate.json, which `--run-ids` reads.
                   The N are the cases whose sha256(id) sorts first — the same
                   cases for every model, and not the head of a file that
                   upstream orders by topic.
"""
import hashlib
import json
import os
import sys

from bfcl_eval.__main__ import cli
from bfcl_eval.constants.eval_config import TEST_IDS_TO_GENERATE_PATH
from bfcl_eval.constants.model_config import MODEL_CONFIG_MAPPING, ModelConfig
from bfcl_eval.model_handler.api_inference.openai_completion import (
    OpenAICompletionsHandler,
)
from bfcl_eval.utils import load_dataset_entry, parse_test_category_argument


class EndpointHandler(OpenAICompletionsHandler):
    """The upstream handler, with the request settings an unattended run against
    a shared self-hosted endpoint needs.

    bfcl sends temperature 0.001, no max_tokens, and does not stream.
    Near-greedy decoding is what reasoning models are documented to loop on,
    and a loop has no natural end. The ai-infer boxes put an nginx in front of
    llama-server that drops a response which has produced no bytes for 300 s,
    LiteLLM then sends the request once more, and the openai SDK's default of
    two retries repeats the whole thing: one looping case holds a slot for half
    an hour and ends as an error. A client that gives up does not end it
    either — the router goes on retrying for a caller that has left.

    So: no temperature unless one was asked for (the endpoint's own sampling
    applies), a max_tokens small enough that a capped answer arrives inside
    300 s, a client timeout that outlasts the router's retry, and no retries
    from here.
    """

    def _build_client_kwargs(self):
        kwargs = super()._build_client_kwargs()
        kwargs["timeout"] = float(os.environ.get("BFCL_REQUEST_TIMEOUT") or 1800)
        kwargs["max_retries"] = 0
        return kwargs

    def generate_with_backoff(self, **kwargs):
        if not os.environ.get("BFCL_TEMPERATURE"):
            kwargs.pop("temperature", None)
        if max_tokens := int(os.environ.get("BFCL_MAX_TOKENS") or 0):
            kwargs["max_tokens"] = max_tokens
        return super().generate_with_backoff(**kwargs)


def register(model: str, mode: str) -> None:
    fc = mode == "fc"
    MODEL_CONFIG_MAPPING[model] = ModelConfig(
        model_name=model,
        display_name=f"{model} ({'FC' if fc else 'Prompt'})",
        url=os.environ.get("OPENAI_BASE_URL", ""),
        org="self-hosted",
        license="n/a",
        model_handler=EndpointHandler,
        is_fc_model=fc,
        # In FC mode the handler rewrites "." in function names to "_", because
        # the OpenAI schema forbids dots; the checker has to map them back.
        underscore_to_dot=fc,
    )


def write_limited_ids(categories: str, limit: int) -> None:
    def chosen(category: str) -> list[str]:
        ids = [entry["id"] for entry in load_dataset_entry(category)]
        return sorted(ids, key=lambda i: hashlib.sha256(i.encode()).hexdigest())[:limit]

    ids = {
        category: chosen(category)
        for category in parse_test_category_argument(categories.split(","))
    }
    # bfcl's score aggregation takes statistics.stdev of the latencies and
    # raises on a single data point, after the case has been scored.
    if sum(len(v) for v in ids.values()) < 2:
        sys.exit("bfcl cannot aggregate a run of fewer than two cases: "
                 "raise --limit or name more than one category")
    TEST_IDS_TO_GENERATE_PATH.write_text(json.dumps(ids, indent=2))


def main() -> None:
    mode = os.environ.get("BFCL_MODE", "fc")
    if mode not in ("fc", "prompt"):
        sys.exit(f"BFCL_MODE must be fc or prompt, not {mode!r}")
    register(os.environ["BFCL_MODEL"], mode)

    limit = os.environ.get("BFCL_LIMIT", "")
    if limit and len(sys.argv) > 1 and sys.argv[1] == "generate":
        write_limited_ids(os.environ["BFCL_CATEGORIES"], int(limit))

    sys.argv[0] = "bfcl"
    cli()


if __name__ == "__main__":
    main()
