# Integration preparation

Baseline inspected: `26a04d173fbcacc4161e77048de04f1cea8f03e7`, local `main`.
Product edits and merges are gated on the leader's INTEGRATE message.

## Planned evidence matrix

| Scenario | Invocation/surface | Binary observable | Planned artifact |
|---|---|---|---|
| Existing hashes, localization, archive parser/contracts | Existing Node scripts listed in README | Every process exits 0 | `checks.txt` |
| Existing search | `node scripts/check-document-search.mjs` with installed omowright loader and owned Chrome | All recorded DOM assertions true | `search/dom-results.json`, screenshots |
| Rendered keyboard editing and unsupported source | Worker A browser checks plus integrated keyboard scenario | DOM editing changes serialized Markdown; protected source survives | `editor/` |
| Korean composition | Dispatch composition lifecycle and inspect bridge events; actual keyboard IME remains device QA | No partial composition is emitted for save; final composed value is emitted | `editor/` |
| Stable anchors through edits/history | Worker B/C fixtures and integrated layout scenario | Stable ID or explicit detachment, never unrelated retarget | `layout/` |
| Range projection and repeated reflow | Worker C browser checks on integrated page | Current line fragments change with wrapping; repeated layout is equal | `layout/` |
| Blank/Markdown insertions | Integrated page insert/edit/resize/move/remove/undo | Reserved height pushes downstream blocks; original position restored by undo | `integration/` |
| Composed supplement images | Existing archive-renderer checks plus supplement collection case | Actual supplement references included; code examples excluded | `integration/` |
| Dependency integrity | Reproducible bundle and npm audit on worker manifests | Bundle reproducible, audit result recorded without suppressing vulnerabilities | `dependencies/` |
| Swift save/reopen, sidecar migration, ZIP/PDF, Pencil | Read source and write Mac/iPad guide; execute only with available toolchain | Explicitly UNRUN here: Swift/Xcode not present | `native-review.md`, QA guide |

No native result will be inferred from Node success. Integration test commands and actual artifact paths will replace planned entries after execution.

## Tooling verified

- Node and npm exist; Swift and xcodebuild were not found via Get-Command.
- Chrome exists at `C:/Program Files/Google/Chrome/Application/chrome.exe`.
- Browser engine environment restriction unset; owned temporary profile permitted.
- Browser skill SHA-256: `76D063D0A112CD61F635BAA95BFAD85AB0A7D3F15BA4612A689DD43F0B1917C3`.
- Git master skill SHA-256: `7CF754F2CC328ADBD5A168A0D6717D05ACFC4A847CDF8BEACA49CE32AD4B68FC`.
- Leader explicitly selected this evidence directory; no loop workflow is active.
