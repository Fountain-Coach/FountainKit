# AudioTalk CLI

A small CLI to interact with the AudioTalk service using the generated `AudioTalkAPI` client.

## Build

```
swift build
```

## Usage

By default the CLI targets `http://127.0.0.1:8080`. Override with `--base-url`.

### Health

```
swift run --package-path Packages/FountainApps audiotalk-cli health --base-url http://127.0.0.1:8080
```

### Dictionary

- List
```
swift run --package-path Packages/FountainApps audiotalk-cli dictionary list
```
- Upsert
```
swift run --package-path Packages/FountainApps audiotalk-cli dictionary upsert --token warm --value 'timbre:warmth:+0.4'
```

### Intent

```
swift run --package-path Packages/FountainApps audiotalk-cli intent parse "legato crescendo warm"
```

- Apply plan to notation session from tokens
```
swift run --package-path Packages/FountainApps audiotalk-cli intent apply --if-match <etag> <session-id> legato crescendo warm
```

### Notation

- New session
```
swift run --package-path Packages/FountainApps audiotalk-cli notation new-session
```
- Get score
```
swift run --package-path Packages/FountainApps audiotalk-cli notation get-score <id>
```
- Put score
```
swift run --package-path Packages/FountainApps audiotalk-cli notation put-score <id> --if-match <etag> "% lily\n c'4"
```

### Screenplay (.fountain)

- New session
```
swift run --package-path Packages/FountainApps audiotalk-cli screenplay new-session
```
- Get source
```
swift run --package-path Packages/FountainApps audiotalk-cli screenplay get-source <id>
```
- Put source
```
swift run --package-path Packages/FountainApps audiotalk-cli screenplay put-source <id> --if-match <etag> "INT. ROOM - DAY"
```
- Parse screenplay
```
swift run --package-path Packages/FountainApps audiotalk-cli screenplay parse <id> | jq
```
- Map cues (persisted)
```
swift run --package-path Packages/FountainApps audiotalk-cli screenplay map-cues <id>
```
- Cue sheet (JSON)
```
swift run --package-path Packages/FountainApps audiotalk-cli screenplay cue-sheet <id> | jq
```

### UMP (MIDI 2.0)

```
swift run --package-path Packages/FountainApps audiotalk-cli ump send <session> 40196000 40964001
```

The CLI prints basic outputs (JSON, IDs, or tags). Use with `jq` for pretty output.

### Journal

- List
```
swift run --package-path Packages/FountainApps audiotalk-cli journal list | jq
```
