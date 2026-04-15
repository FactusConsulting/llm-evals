# Sådan tester vi modeller (kort version)

> For den detaljerede AI-runbook, se `HOW-TO-DRIVE-EVAL.md`.
> For metodologi og hvorfor vi gør det sådan, se `METHODOLOGY.md`.

## Hvad vi tester

To uafhængige eval-suiter pr. model:

1. **Knowledge eval** — 9 chunks med ~370 tekniske spørgsmål (networking, k8s, terraform, ansible, go, rust, .net, python, bash, ps, arkitektur, scenarier). Mål: hvor ofte modellen rent faktisk **løser** problemet.
2. **Loop-detection** — 12 scenarier designet til at teste om modellen kan stoppe rent, ikke spiraler i gentagelser, ikke over-forklarer.

## Hvordan vi scorer

Vi bruger den dedikerede `/judge` skill i `skills/judge-llm-eval/` der orkestrerer en **stable two-judge architecture**:

```
For hver run af modellen:
  1. To uafhængige Opus-judges (A og B) scorer ALLE spørgsmål parallelt
     - De læser samme rubric + reference answer key
     - Reference er "gold standard, NOT contract" — judges krediterer 
       valide alternativer som pass via alternative_acceptable flag
     - Hver judge emitterer JSON: rating + points + justification per question
  
  2. Aggregeringen tager mean(A,B) per question
     - Når begge er enige → den rating
     - Når de er uenige → mean (rounded toward higher when borderline)
  
  3. (Valgfrit) Super-judge agent ser specifikke disagreements 
     for audit-trail, men ændrer ikke scoren
```

**Hvorfor to judges?** Én Opus-agent har ±2.4pp varians på samme model på tværs af runs. Mean(A,B) skaler det ned til ~0.7pp — næsten støjgulvet. Inter-judge agreement ligger typisk på 96-98%.

**Hvorfor "default to pass"?** Tidlige forsøg viste at judges ubevidst brugte reference som checklist og dømte valide alternativer som "weaker than reference". Den nuværende rubric beder eksplicit judges om at evaluere "does this solve the problem?" først, og kun bruge reference til at fact-checke specifikke claims (numbers, syntax, command flags).

## Hvordan vi kører det (workflow)

For at evaluere en ny model X på ai-infer2:

```bash
# 1) Kør evalen 3 gange (tager ~30 min total)
cd /home/lars/source/llm-evals
mkdir -p results/<model-name>/run{1,2,3}
# (write a run-chunk.sh wrapper pointing at the new model's API)
for run in 1 2 3; do
  for chunk in chunk{1..9}-*.txt; do
    ./results/<model-name>/run-chunk.sh chunks/$chunk results/<model-name>/run$run/${chunk%.txt}-response.txt
  done
done

# 2) Kør loop-detection (tager ~10 min)
cd loop-detection
./run-eval.sh --model-url http://<host>:8001 --model-name <model-name>-run1

# 3) Judge alle runs med /judge skill
# (en AI-orkestrator spawner 6 sub-agenter parallelt — se HOW-TO-DRIVE-EVAL.md)
```

For at validere chunk 9 Part B kode deterministisk:

```bash
python3 skills/judge-llm-eval/validators/validate-part-b.py \
  results/<model-name>/run1/chunk9-response.txt
```

## Hvad vi rapporterer

Per model gemmer vi i `results/<model-name>/`:

- `run{1,2,3}/chunk*-response.txt` — rå model output
- `run{1,2,3}/judge.json` — fuld per-question audit fra både judges + final rating
- `judge-summary.md` — per-run scores + variance + agreement stats
- `verdict.md` — model-level konklusion + sammenligning med baseline + produktions-anbefaling

Plus per-eval-runs i `loop-detection/results/<model-name>-run<N>/` med spiral-flag JSON.

## Den nuværende baseline

`gemma4-26b-q6k-458k-turbo4-v2-ai-infer2` (Gemma 4 26B Q6_K, llama.cpp b8753-turbo, ny chat template, turbo4 KV):

- **98.56%** mean over 3 runs
- 0.67pp range (very stable)
- 14.6% alternative_acceptable rate (judges krediterer valide alternativer)
- Persistente fail-spots: AWS WAFv2 HCL (SC9-B), Terraform NFS CSI (SC4-B), Transit Gateway (SC6-B), Patroni Ansible (SC10-B), bash `$!`/`!$` (B11)

Ny modeller skal sammenlignes med dette tal som baseline.
