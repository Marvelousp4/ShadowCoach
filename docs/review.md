# Adaptive Review

Shadow Coach uses a local FSRS-6 scheduler for practiced sentences. The app stores each card's difficulty, stability, due date, learning state, and review history inside `practice.json`; no account or server is required.

## Learner Flow

1. A saved recording enrolls the sentence in review.
2. Review shows the source and previous English line while keeping the answer hidden.
3. The learner recalls the target aloud, then reveals it.
4. The learner chooses one rating:
   - `Again`: any important part was forgotten.
   - `Hard`: correct recall with serious effort.
   - `Good`: correct recall after normal hesitation.
   - `Easy`: immediate, confident recall.
5. FSRS-6 calculates the next due time. `Hard` must not be used for a forgotten answer.

Chinese translation is a rescue hint, not the default prompt. Translation-to-English recall can help establish meaning, but using it as the only cue overtrains translation-mediated recall. English context better matches the intended transfer task: retrieving and producing English from a situation or prior discourse.

## Settings

- `Memory target`: 85%, 90%, or 95% desired retention. Higher values schedule more reviews. The default is 90%.
- `Daily review cap`: 10, 20, 30, or 50 ratings. The default is 20.

The 21 FSRS weights intentionally remain hidden and use the official defaults until enough review history exists to justify personal optimization.

## Implementation References

- [Official FSRS algorithm and FSRS-6 parameters](https://github.com/open-spaced-repetition/awesome-fsrs/wiki/The-Algorithm)
- [Official FSRS usage guidance](https://github.com/open-spaced-repetition/fsrs4anki/blob/main/docs/tutorial.md)
- [Open Spaced Repetition Python reference implementation](https://github.com/open-spaced-repetition/py-fsrs)
- [Retrieval practice and long-term retention](https://pubmed.ncbi.nlm.nih.gov/16507066/)
