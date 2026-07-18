# Context

Domain vocabulary for what-did-i-say. Names here are the words to use in code, tests,
and architecture reviews.

## Core nouns

- **Recording session** — one call, from start to saved note. Owns the two audio tracks
  (system + mic) and the metadata gathered along the way. (`RecordingSession`)
- **Source** — where a call comes from: manual, Slack huddle, Teams call, Google Meet.
  (`RecordingSource`)
- **Transcript** — the merged, speaker-labelled segments produced from both tracks.
  (`[TranscriptSegment]`)
- **Note** — the markdown file written to the vault: front matter, summary, transcript.
- **Vault** — the user's chosen output folder (often an Obsidian vault).

## Modules

- **Transcript builder** — turns the two recorded tracks into one merged, speaker-labelled
  transcript. Owns the recipe: transcribe each track, diarize the others track when asked,
  then merge. Callers ask for a transcript and get one. (`TranscriptBuilder`)
- **Summary** — turns transcript segments into a short markdown summary via a local (Ollama)
  or cloud (Anthropic) summarizer. Owns segment-to-text flattening, prompt, and backend
  selection. (`Summary`, behind the `Summarizer` seam)
- **Note pipeline** — turns a finished recording session into a saved note. Owns the whole
  post-recording sequence — transcribe, summarize, review participants, render, write — and
  reports its stage and outcome. (`NotePipeline`)
- **Call presence detection** — decides when a call starts and ends across mic activity,
  output-stream activity, browser Meet tabs, and app termination. (`CallDetector`,
  `CallActivityMonitor`, `BrowserCallDetector`)
