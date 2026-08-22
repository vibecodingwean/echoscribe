# Historical privacy cleanup note

## Current status

The current repository tree does not contain the previously used private LAN endpoint. EchoScribe is Android, GNOME, and Chrome only; Windows, iOS, Flutter web, Firefox, and Edge trees are no longer in the product. Historical blobs that named those paths were part of an earlier LAN-endpoint cleanup scan, not current product surfaces.

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
