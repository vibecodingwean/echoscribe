# Historical privacy cleanup note

## Current status

The current repository tree does not contain the previously used private LAN endpoint. A scan of all reachable Git objects found the masked value `192.168.x.x` in five historical commit snapshots and ten historical paths:

- `config/ai_models.json`
- `desktop/linux/README.md`
- `desktop/linux/config.example.toml`
- `desktop/linux/echoscribe/config.py`
- `lib/config/prompts.dart`
- `lib/pages/settings_page.dart`

Commit `9639245c1be4c2f718c8e0bf7b9cd99f0740e512` introduced the value. Commit `fef0f58276836a3741b292fcf776638e9d6d2770` removed it from the current line of development; its resulting tree does not contain the value. The old blobs remain reachable through repository history.

No history rewrite or force-push was performed as part of the repository-hygiene work.

## Optional future history rewrite

A history rewrite is disruptive. It changes commit and tag IDs, invalidates existing clones and open work based on old commits, and requires coordinated replacement of every published ref and cached release source. It should be performed only after explicit approval, a verified backup, collaborator coordination, and a publication freeze.

One possible procedure in a disposable mirror clone is:

1. Create and verify a complete mirror backup.
2. Install and pin a reviewed version of `git-filter-repo`.
3. Read the historic endpoint interactively without placing it in shell history.
4. Create a private replacement-expression file with mode `0600` containing:

   ```text
   literal:<PRIVATE_LAN_ENDPOINT>==>127.0.0.1
   ```

5. Run:

   ```bash
   git filter-repo --replace-text /path/to/private-replacements.txt
   ```

6. Verify every rewritten branch and tag, repeat the secret/PII scan over all rewritten objects, rebuild release artifacts from the rewritten source, and compare intended content changes.
7. Coordinate the required force-update of all affected remote refs. Do not force-push until the owner explicitly approves the exact rewritten repository.
8. Remove the local replacement-expression file after verification and require collaborators to re-clone or carefully rebase onto the rewritten history.

The replacement file must never be committed or attached to a report. Substituting `127.0.0.1` is appropriate only where loopback behavior matches the affected historical examples; otherwise use a clearly non-personal documentation placeholder.

This note is operational guidance, not legal advice and not authorization to rewrite public history.
