CREATE SCHEMA IF NOT EXISTS kpi_beacon;

CREATE TABLE IF NOT EXISTS kpi_beacon.kpi_entries (
    id bigserial PRIMARY KEY,
    week_start date NOT NULL,
    metric text NOT NULL,
    value numeric NOT NULL,
    unit text NOT NULL,
    program text,
    source text,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS kpi_entries_week_idx
    ON kpi_beacon.kpi_entries (week_start);

CREATE INDEX IF NOT EXISTS kpi_entries_metric_idx
    ON kpi_beacon.kpi_entries (metric);
