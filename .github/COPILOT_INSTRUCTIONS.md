# Copilot Instructions for RimWorld Mod Publishing Helpers

These instructions describe coding conventions, architecture expectations, and helper utilities in this repository so AI assistance stays consistent.

## Goals
- Automate RimWorld mod maintenance: publishing, metadata updates, translation handling, Steam / GitHub integration.
- Keep scripts idempotent and safe: never destroy user content without explicit confirmation flags.
- Prefer batch operations (e.g., Get-ModInfo with up to 10 steamIds) and caching (10‑minute ModInfo cache, translation cache) to reduce API calls.

## PowerShell Guidelines
- Target Windows PowerShell 7 compatibility first
- Use singular verb-noun function names (Publish-Mod, Get-ModInfo, Update-NoVersionMod, Remove-EmptyFolders etc.).
- Always output objects (hashtables / PSCustomObjects) instead of plain strings where practical. Use WriteMessage helper for user-facing progress, warnings, success, failure.
- Avoid Write-Host except for deliberate, user-visible colored status (prefer WriteMessage wrapper if present).
- Validation: use `if (-not $var)` checks; avoid `IsNullOrWhiteSpace` unless already imported.
- Use `[int]` casts for numeric comparisons of enum values (e.g., `[int][ModCodeSize]::Large`).

## Enums / Types
- Enum ModCodeSize: None,Tiny,Small,Medium,Large,Huge (defined via Add-Type). Compare by casting to [int].

## Caching Patterns
- ModInfo cache: `$Global:ModInfoCache[steamId] = @{ Timestamp = <DateTime>; ModInfo = <object> }` with 10 minute TTL.
- When adding new external calls, add optional `-ForceRefresh` switch to bypass cache.

## XML Handling
- Always load XML via `[xml](Get-Content -Raw -Encoding UTF8)`.
- Use `$xml.DocumentElement` for appending nodes; root element names may string-coerce unexpectedly if empty.
- For loadFolders generation, each version node: `<v1.4><li>/</li><li>1.4</li><li>Assets</li></v1.4>`; ensure Assets li exists.

## Steam Workshop Interaction
- Batch `Get-ModInfo -steamIds` up to 10 IDs per call. Deduplicate steamIds before batching. Preserve version tag lists.
- Extract steamId from URLs with trailing digits using: `-replace '.*?(\d+)$','$1'` or from query with `-replace '.*[?&]id=(\d+).*','$1'`.

## GitHub Integration
- Webhook functions: verify repository existence with Get-RepositoryStatus before POST/DELETE.
- Always handle REST failures in try/catch; bubble minimal failure info via WriteMessage -failure.

## String & Regex
- Prefer regex replacement for complex BBCode / URL mutations. Use `[regex]::Escape()` for dynamic literals.

## Code Size Metrics
- CodeBaseSize (0–100 logarithmic scaling) computed from LinesOfCode + LinesOfXML; store enum classification with Get-ModCodeSize returning [ModCodeSize].

## Error Handling
- Wrap external API calls with retry (3 attempts, small delay) when network/transient.
- Null-safe navigation: check node existence before calling SelectSingleNode.

## New Feature Checklist
1. Input validation & parameter attributes.
2. Caching & batching considered.
3. Respect existing enums & WriteMessage usage.
4. Avoid breaking public function signatures unless necessary; add new parameters at end with sensible defaults.
5. Provide `-WhatIf` or test switches when side effects (file moves, deletions, publishing).

## Testing / Simulation
- For destructive operations, add a `[switch]$Test` that logs intended actions without executing them.

## Performance
- Minimize repeated disk reads/writes inside loops (accumulate then write once when feasible).
- Avoid calling external services for parallel identical inputs—use caches.

## Style Examples
```
function Get-Example {
  [CmdletBinding()] param([string]$Id,[switch]$ForceRefresh)
  if (-not $Id) { return }
  $now = Get-Date
  if (-not $ForceRefresh -and $Global:ExampleCache.ContainsKey($Id)) {
     $entry = $Global:ExampleCache[$Id]
     if ($now - $entry.Timestamp -lt [TimeSpan]::FromMinutes(10)) { return $entry.Value }
  }
  # fetch logic
}
```

## Do / Avoid
- DO: Use `$xml.DocumentElement.AppendChild()`.
- DO: Cast enums to `[int]` for comparisons.
- DO: Batch remote lookups.
- AVOID: Rebuilding large arrays inside tight loops.
- AVOID: Silent catch blocks; always WriteMessage -failure with concise hint.

## Future Ideas
- Add persistence layer for ModInfoCache (JSON on unload) to survive sessions.
- Add centralized retry helper for HTTP/Steam API.
- Expand enum granularity if more scaling resolution needed.

---
Generated guidance for AI-assisted coding in this repository.
