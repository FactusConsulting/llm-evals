# DeepSeek-V4-Flash-0731 UD-IQ2_M @ FULD 1M kontekst (GX10) — eval

Samme model/kvant som `dsv4-flash-IQ2_M-262k-gx10`, men serveret ved modellens
**native YaRN-kalibrerede 1048576 (1M) kontekst** i stedet for 262144.

## Native kontekst — korrektion
GGUF-metadata (parset direkte): `deepseek4.context_length = 1048576`,
`rope.scaling.type = yarn`, `factor = 16.0`, `original_context_length = 65536`
(65536 × 16 = 1M). **1M er modellens kalibrerede grænse, IKKE ekstrapolation.**
De 262144 var blot en konservativ `--ctx-size`-default. YaRN-parametrene er faste
i modellen uanset `--ctx-size`, så korte prompts får identisk rope-beregning ved
262144 og 1M → kvalitet forventet uændret. Bekræftet nedenfor.

## Knowledge-score (6 Opus-dommere, 2/run × 3 runs, 370 spm)

| Run | Judge A | Judge B | Mean |
|---|---|---|---|
| run1 | 98.24% | 98.78% | 98.51% |
| run2 | 97.84% | 98.38% | 98.11% |
| run3 | 98.51% | 99.05% | 98.78% |

**Overall: 98.47%** (spread 97.8-99.1, stdev 0.42 — strammere end 262144's 0.56).

vs 262144 IQ2_M: **96.46%** (3-run mean). Δ +2.01 pp, KONSISTENT over 3 runs.
**Fortolkning:** model + YaRN-params er IDENTISKE ved 262144 og 1M, og eval-chunks er
korte (<10K tokens, langt under YaRN orig_ctx 65536) → rope-beregning er identisk →
ingen MEKANISME for 1M at være reelt bedre. De +2pt er dommer-varians MELLEM
kampagnerne (forskellige Opus-dommer-kørsler; intra-kampagne stdev 0.42-0.56 <
inter-kampagne 2pt drift). **Robust konklusion: 1M-config degraderer IKKE kvaliteten —
mindst lige så god som 262144.** Samme svære opgaver fejler (SC9-B WAFv2 fabrikeret HCL,
SC3-B ECR/boto3 fiktiv metode) — identisk mønster med 262144/Q2/Q3, uafhængigt af ctx.

## Praktiske grænser for stor faktisk kontekst (målt)
- **Memory er ikke bindingen:** 1M-slot allokeret = 94-95 GB (MLA ~5 KB/token), 25 GB fri.
- **Prefill FALDER ved dybde:** ~200 tok/s ved start → ~165 tok/s ved 293K position.
  At fylde 700K tokens ≈ 70 min; 1M ≈ ~1,9 timer. Dette gør reelt fyldning af
  hele vinduet upraktisk — den dominerende praktiske grænse, ikke memory/kvalitet.
- **Amortisering:** i sessioner betaler KV-prompt-cache kun for nye tokens; det
  er kun engangs-dump af kæmpe input der rammer den fulde prefill-tid.

## Needle-in-haystack OVER 262144 (målt)
Prompt 296.484 tokens, nål ved ~266K position (dybt over den gamle 262144-default).
**NÅL FUNDET: True** — modellen returnerede koden præcist (`VIOLET-TERRAPIN-9317`)
og lokaliserede "IMPORTANT FACT"-linjen i reasoning. wall = 1842s (~31 min, prefill-bundet).
Bekræfter: 1M-vinduet er REELT brugbart, ikke kun nominel kapacitet — modellen henter
information dybt i det kalibrerede vindue. (Testede til ~296K; fuld 1M ville tage ~1,9t
prefill at fylde, men kalibrerings-metadata + 296K-resultat giver høj tillid til hele vinduet.)

Verdict: **1M kontekst er kvalitets-gratis** (kalibreret), memory tillader det,
men fyldning af meget stor kontekst er prefill-bundet og langsom. Production-script
`run-dsv4-iq2.sh` sat til `--ctx-size 1048576 --parallel 1`.
