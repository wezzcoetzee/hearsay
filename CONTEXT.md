# Context

Domain vocabulary for What Did I Say. Names here are the words to use in code, tests,
and architecture reviews.

## Core nouns

- **Recording session** — one recording, from start to saved note. Owns the audio tracks
  (system + mic for calls, mic alone for in-person meetings) and metadata. (`RecordingSession`)
- **Source** — where a recording comes from: manual call, in-person meeting, Slack huddle, Teams call, Google Meet.
  (`RecordingSource`)
- **Transcript** — speaker-labelled segments produced from the recorded tracks.
  (`[TranscriptSegment]`)
- **Note** — the markdown file written to the vault: front matter, summary, transcript.
- **Vault** — the user's chosen output folder (often an Obsidian vault).

## Modules

- **Transcript builder** — turns recorded tracks into one speaker-labelled transcript.
  Calls transcribe both tracks, optionally diarize the others track, then merge.
  In-person meetings transcribe and diarize the microphone alone. A failed diarization
  degrades the transcript instead of failing it. (`TranscriptBuilder`)
- **Summary** — turns transcript segments into a short markdown summary via a local (Ollama)
  or cloud (Anthropic) summarizer. Owns segment-to-text flattening, prompt, and backend
  selection. (`Summary`, behind the `Summarizer` seam)
- **Note pipeline** — turns a finished recording session into a saved note. Owns the whole
  post-recording sequence — transcribe, review and name voices, summarize, render, write — and
  reports its stage and outcome. (`NotePipeline`)
  The pipeline stops at the written note. `RecordingController` owns what follows a
  save: marking the session `noted`, adding it to history, and archiving or deleting
  the audio.
- **Call presence detection** — decides when a call starts and ends across mic activity,
  output-stream activity, browser Meet tabs, and app termination. (`CallDetector`,
  `CallActivityMonitor`, `BrowserCallDetector`)
- **Capture** — `MicCapture` and `SystemAudioCapture` write the tracks and report,
  once per recording, if either stops writing mid-call (`onInterrupted`), which the
  menu surfaces as a warning.
