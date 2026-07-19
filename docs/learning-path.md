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
| Transform | Keep the learning target but genuinely change the people, time, and details | Saved New Situation recording |
| Free speak | Speak for 30–60 seconds from personal meaning | Saved Free Speaking recording |
| Use it | Use the target in real communication and record the outcome | Learner outcome, optional actual wording, and optional stage feedback |
| Correct | Analyze an exact attempt and retry | Perfect exact recall, or analysis of a Corrected Retry |

Legacy recordings resolve to `Shadowing`. New open-response recordings have an explicit activity type. `New Situation` and `Free Speaking` attempts are playable and persistent, but exact reference comparison, Azure pronunciation scoring, prosody comparison, and the reference-length rejection rule do not run on them.

## Learning Target Selection

The local extractor only returns high-confidence language patterns. It does not fall back to arbitrary n-grams, names, IDs, numbers, or topic-specific noun phrases. Local Codex can automatically refine the candidates when enabled; Gemini refinement remains an explicit action so the app does not create an unrequested paid call. AI candidates must still pass local validation and remain exact substrings of the source sentence.

Returning no target is a valid result. In that case, the learner practices the complete message instead of memorizing a weak fragment.

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
