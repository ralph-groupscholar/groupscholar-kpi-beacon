# Group Scholar KPI Beacon

CLI for logging and summarizing weekly operational KPIs into the Group Scholar Postgres database.

## Features
- Create the KPI schema/table in Postgres.
- Log weekly KPI entries with optional program/source context.
- List recent entries with optional week filters.
- Summarize a week by KPI metric.

## Tech
- Erlang (escript)
- Postgres (via epgsql)

## Setup

Install deps and build the escript:

```sh
rebar3 escriptize
```

Set environment variables for Postgres:

```sh
export GS_KPI_BEACON_DB_HOST=db-acupinir.groupscholar.com
export GS_KPI_BEACON_DB_PORT=23947
export GS_KPI_BEACON_DB_NAME=postgres
export GS_KPI_BEACON_DB_USER=ralph
export GS_KPI_BEACON_DB_PASSWORD=your_password
```

## Usage

```sh
_build/default/bin/gs-kpi-beacon init
_build/default/bin/gs-kpi-beacon seed
_build/default/bin/gs-kpi-beacon log --week 2026-02-02 --metric applications_reviewed --value 142 --unit applications --program scholarships --source review-team --notes "Week of review sprint"
_build/default/bin/gs-kpi-beacon list --limit 10
_build/default/bin/gs-kpi-beacon list --week 2026-02-02
_build/default/bin/gs-kpi-beacon summary --week 2026-02-02
```

## Testing

```sh
rebar3 eunit
```
