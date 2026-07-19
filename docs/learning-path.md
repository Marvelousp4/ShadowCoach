# Guided Learning Path

The **Next Coach** card turns each sentence into one small next action instead of a collection of independent tools. Progress remains local in `practice.json` and is backward-compatible with existing recordings.

## Completion Rules

| Stage | Learner action | Completion evidence |
|---|---|---|
| Understand | Listen and confirm the situation and meaning | Learner confirmation, or an existing saved attempt |
| Notice | Select one reusable chunk | Selected chunk saved locally |
| Shadow | Copy the reference and record it | Saved Shadowing recording |
| Recall | Produce the hidden line from English context | A completed recall rating |
| Review | Let FSRS schedule the next retrieval | The same rating creates an FSRS event and due date |
| Transform | Keep the chunk but change the people, time, and details | Saved New Situation recording |
| Free speak | Speak for 30–60 seconds from personal meaning | Saved Free Speaking recording |
| Use it | Use the chunk in real communication | Honest learner confirmation |
| Correct | Analyze an exact attempt and retry | Perfect exact recall, or analysis of a Corrected Retry |

Legacy recordings resolve to `Shadowing`. New open-response recordings have an explicit activity type. `New Situation` and `Free Speaking` attempts are playable and persistent, but exact reference comparison, Azure pronunciation scoring, and the reference-length rejection rule do not run on them.

## Why The Cue Is Not Chinese By Default

Translation can rescue comprehension, but repeated Chinese-to-English recall trains dependence on translation. The default retrieval cue is English context: the source, nearby line, and situation. Chinese remains available only when the learner is stuck.

## Scheduling

The first honest recall rating both completes unprompted retrieval and activates FSRS. This is intentional: scheduling is not a second quiz immediately after the first one. Future reviews continue independently even after the nine-stage path is complete. Retention target and daily cap stay configurable in Settings.
