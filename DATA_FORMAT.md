# Data formats

V accepts UTF-8 JSON up to 20 MiB. Version 1 allows at most 3,000 exercises, 20,000 entries, 100,000 sets, and 20,000 import receipts. Each entry has 1 to 100 sets. Set values and goal targets are whole numbers from 1 to 999,999. A repetition value counts reps. A duration value counts seconds.

An activity date is a valid `YYYY-MM-DD` calendar date from 1900 onward. Activity cannot be in the future. A goal deadline can be in the future. Audit timestamps use ISO 8601 with the UTC suffix `Z`. Names are trimmed and limited to 80 characters. Name matching ignores case and runs of whitespace. Notes can be null or at most 2,000 characters.

V validates the entire file before allowing confirmation. The first validation error names the field or record that needs correction. Unrecognized fields, unsupported versions, invalid references, and duplicate IDs are errors.

## Full backup

Use `fitness-backup` for a restorable snapshot. IDs are opaque strings up to 80 characters that start with an ASCII letter or digit. Subsequent characters can also include underscores and hyphens. An entry's `order` is a unique positive integer. Within each entry, `position` starts at zero and advances by one. The last set on the latest activity date determines the latest result. A goal belongs to one exercise. An import receipt is the SHA-256 fingerprint of a normalized activity batch.

```json
{
	"format": "fitness-backup",
	"schemaVersion": 1,
	"exportedAt": "2026-11-12T10:00:00.000Z",
	"exercises": [
		{
			"id": "exercise-1", "name": "Push-ups",
			"measurement": "repetitions", "archived": false,
			"createdAt": "2026-11-12T09:00:00.000Z",
			"updatedAt": "2026-11-12T09:00:00.000Z"
		}
	],
	"entries": [
		{
			"id": "entry-1", "exerciseId": "exercise-1",
			"date": "2026-11-12", "notes": null, "order": 1,
			"createdAt": "2026-11-12T09:05:00.000Z",
			"updatedAt": "2026-11-12T09:05:00.000Z",
			"sets": [
				{"id": "set-1", "position": 0, "value": 22},
				{"id": "set-2", "position": 1, "value": 18}
			]
		}
	],
	"goals": [
		{
			"exerciseId": "exercise-1", "target": 30, "deadline": null,
			"updatedAt": "2026-11-12T09:10:00.000Z"
		}
	],
	"settings": {"appearance": "system", "duration": "clock", "haptics": true},
	"importReceipts": []
}
```

Settings accept `system`, `light`, or `dark` for appearance, and `clock` or `seconds` for duration display. A receipt item contains `fingerprint` as 64 lowercase hex characters and `importedAt` as a UTC timestamp.

**Merge** keeps device preferences and skips records with identical IDs and content. For conflicting IDs, the preview states what the local copy keeps and which incoming records are skipped. If a name matches under a different exercise ID, V keeps the local exercise and skips incoming entries and goals tied to the conflicting ID. Entries with different IDs and matching date and set values are flagged and kept when you confirm. New entries take local order numbers after existing entries, in the same relative order as in the backup. Merge comparisons ignore this local renumbering.

**Replace** restores the data and preferences together. It writes a private recovery backup first. If that write fails, V keeps the current database. Open the previous copy under **Settings → Your data → Recovery backups**. The recovery file stays on this device.

## Activity import

`fitness-activity-import` adds activity and leaves preferences and goals alone. The example below is also available from **Import from AI chat**. Each record contains actual sets, in the order entered. Array order matters when several entries share a date. V creates all record IDs.

```json
{
	"format": "fitness-activity-import",
	"schemaVersion": 1,
	"records": [
		{
			"date": "2026-11-12",
			"exercise": {"name": "Push-ups", "measurement": "repetitions"},
			"sets": [22, 20, 18],
			"notes": null
		},
		{
			"date": "2026-11-12",
			"exercise": {"name": "Plank", "measurement": "duration"},
			"sets": [100, 90],
			"notes": null
		}
	]
}
```

The preview suggests a matching active exercise or labels a new exercise to create. A name match with a different measurement or an archived exercise requires a choice. Explicitly mapping to an archived exercise adds records without restoring it.

The fingerprint ignores JSON formatting, object key order, and differences that disappear when normalizing exercise names and trimming notes. It preserves entry and set array order. An already imported batch is blocked unless you select **Import again**. Matching entries from a different batch are flagged without deleting repeats. The records and receipt commit in the same transaction.

## CSV export

CSV is for analysis. It contains one row per set, with its date, exercise, measurement, unit, IDs, set number, value, notes, and UTC timestamps. Timed values remain in seconds regardless of display preferences. V quotes text and prefixes formula-like exercise names and notes with an apostrophe. Use the JSON backup to restore a database.
