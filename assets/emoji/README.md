# Deltiecord emoji names and aliases

Edit `aliases.json` to change the canonical `:name:` or add aliases without
modifying the upstream emoji catalogue in `emojis.json`.

Each top-level key is the emoji itself. `name` replaces its displayed/searchable
name and every item in `aliases` becomes an accepted colon completion. An
optional `category` can be one of:

`smileysAndPeople`, `animalsAndNature`, `foodAndDrink`, `travelAndPlaces`,
`activities`, `objects`, `symbols`, or `flags`.

New emoji can also be added in this file by supplying all three fields. JSON
requires double quotes and does not support comments. Rebuild/restart the app
after editing because the file is bundled into the application.
