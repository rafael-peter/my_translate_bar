# FreeDict offline lookup data

This directory contains the generated English↔Portuguese lookup resources used
as a fast first pass before sentence translation. The files are data, not a
machine translation model: they return one or more dictionary senses for an
exact word or phrase and should fall back to the app's translation engine when
there is no exact match.

The JSON schema is intentionally dependency-free:

```json
{
  "schema_version": 1,
  "source_language": "en",
  "target_language": "pt",
  "entries": {"hello": ["alô", "olá"]}
}
```

The `entries` values are arrays because a word can have several senses. Keys
are stored in the source dictionary's spelling and should be normalized by the
app (trimmed and case-folded) before lookup. Keep diacritics: `não` and `no`
are different Portuguese keys.

## Source and licensing

The source archives are published by [FreeDict](https://freedict.org/):

- [English–Portuguese 0.3](https://download.freedict.org/dictionaries/eng-por/0.3/freedict-eng-por-0.3.stardict.tar.xz)
- [Portuguese–English 0.2](https://download.freedict.org/dictionaries/por-eng/0.2/freedict-por-eng-0.2.stardict.tar.xz)

Each archive declares GNU GPL version 2 or any later version. The corresponding
license text is kept next to each generated JSON file as `*-COPYING`. Preserve
these files, this attribution, the source URL, and the archive checksum when
redistributing the data. The source calls the Portuguese side generic
Portuguese; it does not guarantee that every entry is specifically Brazilian
Portuguese (`pt-BR`).

## Regenerating

From the repository root:

```sh
python3 Resources/FreeDict/scripts/fetch_and_convert.py
```

The script downloads both archives, records their SHA-512 in the generated
metadata, extracts the StarDict index/data, preserves multiple senses, and
writes the two JSON files under `Sources/TranslateBarApp/Resources/FreeDict/data`,
which is the only copy packaged by SwiftPM. Use `--output-dir` when you need a
separate inspection directory.
