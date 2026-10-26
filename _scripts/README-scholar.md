# Google Scholar citation badges

Citation counts are stored in `_data/google_scholar_citations.json`. Jekyll reads this file without making requests to Scholar for individual papers.

The updater adapts the publication-table approach described in [Ben Wooding's article](https://woodingben.substack.com/p/putting-your-google-scholar-stats): one profile request reads up to 100 papers, matched by Scholar article ID. Empty citation cells in validated rows mean zero; blocked or malformed pages never become zero counts.

Refresh locally from the repository root:

```sh
bundle exec ruby _scripts/update_scholar_citations.rb
```

Commit the updated data file to publish locally fetched counts. Deployments also attempt a refresh, at most once per day. Successful results and the last attempt time are retained in GitHub Actions cache; the checked-in snapshot remains the fallback if that cache expires. A failed refresh preserves the last successful counts and timestamp. Counts therefore may be older than the current Scholar profile. There is no scheduled background refresh: the updater runs on deployments or when invoked manually.

Google may still block requests from GitHub. When that happens, run the updater locally once the saved counts are at least a day old and commit the resulting data file. Papers outside the first 100 profile results retain their saved counts until a later successful refresh includes them.

Run the focused checks:

```sh
bundle exec ruby _scripts/tests/test_scholar_citations.rb
```
