# Guided Learning Path

The **Next Coach** card turns each sentence into one small next action instead of a collection of independent tools. Progress remains local in `practice.json` and is backward-compatible with existing recordings.

## Completion Rules

| Stage | Learner action | Completion evidence |
|---|---|---|
| Understand | Listen and confirm the situation and meaning | Learner confirmation, or an existing saved attempt |
| Notice | Keep one valuable sentence frame, fixed expression, collocation, phrasal verb, or discourse marker | Structured target saved locally; whole-sentence practice is valid when none exists |
| Shadow | Copy the reference and record it | Saved Shadowing recording |
| Recall | Produce the hidden line from English context | A completed recall rating |
| Review | Let FSRS schedule the next retrieval | The same rating creates an FSRS event and due date |
| Transform | Keep the learning target but genuinely change the people, time, and details | Saved New Situation recording, or skipped when no reusable target exists |
| Free speak | Speak for 30–60 seconds from personal meaning | Saved Free Speaking recording, or skipped when no reusable target exists |
| Use it | Use the target in real communication and record the outcome | Learner outcome and optional wording, or skipped when no reusable target exists |
| Correct | Analyze an exact attempt and retry | Perfect exact recall, or analysis of a Corrected Retry |

Legacy recordings resolve to `Shadowing`. New open-response recordings have an explicit activity type. `New Situation` and `Free Speaking` attempts are playable and persistent, but exact reference comparison, Azure pronunciation scoring, prosody comparison, and the reference-length rejection rule do not run on them.

## Learning Target Selection

The local extractor only returns high-confidence language patterns. It does not fall back to arbitrary n-grams, names, IDs, numbers, or topic-specific noun phrases. Local Codex can automatically refine the candidates when enabled; Gemini refinement remains an explicit action so the app does not create an unrequested paid call. AI candidates must still pass local validation and remain exact substrings of the source sentence. The selector prefers one strong formulaic sequence over three weak fragments because instruction is most useful when it draws attention to conventional combinations and then gives the learner repeated opportunities to retrieve them.

Returning no target is a valid result. In that case, the learner still listens, shadows, recalls, reviews, and corrects the complete message. The app skips `Transform`, `Free speak`, and `Use it` because asking the learner to transfer an arbitrary whole sentence would create busywork rather than useful language practice.

## Evidence-Informed Responsibilities

| Stage | Learning job | What the app should do | Codex role |
|---|---|---|---|
| Understand | Build meaning from comprehensible authentic input | Real audio first; reveal and translation stay optional | Explain a difficult sentence only when asked |
| Notice | Detect a reusable formulaic sequence or productive frame | Select 0–3 validated targets; never manufacture a chunk | Fast model ranks and explains candidates |
| Shadow | Improve decoding, timing, and fluent reproduction | Compare audio/transcript evidence and preserve the real speaker | No role in ASR, timing, or acoustic scoring |
| Recall | Retrieve without leaning on the written answer | Start from English situation/context; Chinese is a rescue hint | No model call needed |
| Review | Make retrieval durable over time | FSRS schedules the sentence locally | No model call needed |
| Transform | Reuse the target while changing the situation | Require a genuinely new actor, event, or purpose | Fast model checks target use and naturalness |
| Free speak | Construct a message rather than recite one | Evaluate communication, organization, and useful errors | Nuanced model gives selective feedback |
| Use it | Transfer language into real interaction | Save what happened and the learner's actual wording | Fast model reviews wording without inventing listener evidence |
| Correct | Repair the largest supported problem and try again | Keep transcript, pronunciation, and prosody evidence separate | Nuanced model explains evidence and proposes one retry |

Codex is deliberately not used for transcription, word alignment, phoneme scoring, prosody extraction, translation fallback, or review scheduling. Dedicated speech systems and deterministic algorithms are faster and produce inspectable evidence for those jobs.

## Local Codex Model Routing

Shadow Coach reads the signed-in user's local Codex model catalog and chooses the smallest suitable model automatically:

- Fast route: target selection, practice generation, changed-situation feedback, real-use wording, and short transformation follow-up. It prefers `gpt-5.6-luna`, then `gpt-5.4-mini`.
- Nuanced route: exact meaning comparison, free-speaking feedback, and deeper follow-up. It prefers `gpt-5.6-terra`, then a capable general fallback.
- Both routes use no extra reasoning effort for these bounded text tasks. `gpt-5.6-sol` is never preferred for routine coaching.
- The actual model is stored with each cached result. Analyze Again recomputes with the current route and replaces the prior result.

This follows the same general workload pattern OpenAI recommends: use smaller, faster models for narrow high-volume work and reserve larger models for judgment. The exact local model names may differ by account, so the route degrades to models present in the user's own catalog.

## Stage-Aware Feedback

- `Shadowing` and `Corrected Retry` compare the spoken words with the reference and may use optional pronunciation or prosody evidence.
- `New Situation` checks whether the context genuinely changed, whether the target's slots and meaning were preserved, and whether the new sentence is natural.
- `Free Speaking` checks communication, organization, natural spoken English, and whether the target was used appropriately. It never assigns an exact-recall score.
- `Use it` stores `Worked`, `Hesitated`, or `Didn't land`. AI evaluates wording only when the learner supplies what they actually said; without that evidence, the app saves the outcome and gives a non-diagnostic next step.

Transcripts, stage feedback, and Codex follow-up conversations are cached with the recording. Choosing Analyze Again deliberately recomputes and replaces the previous stage result.

## Why The Cue Is Not Chinese By Default

Translation can rescue comprehension, but repeated Chinese-to-English recall trains dependence on translation. The default retrieval cue is English context: the source, nearby line, and situation. Chinese remains available only when the learner is stuck.

## Scheduling

The first honest recall rating both completes unprompted retrieval and activates FSRS. This is intentional: scheduling is not a second quiz immediately after the first one. Future reviews continue independently even after the nine-stage path is complete. Retention target and daily cap stay configurable in Settings.

FSRS is the scheduling implementation, not the scientific claim by itself. The underlying evidence supports retrieval and spacing for durable learning; it does not imply that repeating the same sentence many times in one sitting guarantees transfer. Exact task repetition can improve immediate fluency, but massed repetition can also increase verbatim repetition. Shadow Coach therefore moves from imitation to a changed situation and free expression, then schedules later retrieval.

## Research Basis

- [Formulaic-sequence intervention review](https://www.cambridge.org/core/journals/annual-review-of-applied-linguistics/article/abs/experimental-and-intervention-studies-on-formulaic-sequences-in-a-second-language/A2ACDF54604CFAC4443240748360C403): attention, lookup/corpus support, and deliberate memory work are the main instructional families.
- [Spaced practice in second-language learning meta-analysis](https://onlinelibrary.wiley.com/doi/full/10.1111/lang.12479): spacing showed a medium-to-large overall effect across 48 experiments, with longer spacing helping delayed tests more than short spacing.
- [Shadowing for second-language pronunciation systematic review](https://www.tandfonline.com/doi/full/10.1080/29984475.2025.2546827): evidence is strongest for fluency-related outcomes; transfer to spontaneous speaking remains less established.
- [Speaking task repetition study](https://www.cambridge.org/core/journals/studies-in-second-language-acquisition/article/massed-task-repetition-is-a-doubleedged-sword-for-fluency-development/D28EDD7E3D0FA15630165538D706E80F): repetition can help fluency, while massed repetition may also slow articulation and increase verbatim repetition.
- [Oral corrective feedback meta-analysis](https://www.cambridge.org/core/journals/studies-in-second-language-acquisition/article/abs/oral-feedback-in-classroom-sla/4999EE1C8379B2BF026B148EAF373CA1): corrective feedback had durable effects, with prompts outperforming recasts and stronger effects on freely constructed responses.
- [OpenAI model-routing guidance](https://openai.com/index/introducing-gpt-5-4-mini-and-nano/): narrow, high-volume tasks can be delegated to smaller fast models while larger models handle final judgment.
