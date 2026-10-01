# CIR-001: Collect the Puma 8 stats the exporter was dropping

## Intent

Export every stat `Puma.stats` reports, so operators running Puma 8 can see IO-bound
thread use, request throughput, and the queue depth peaks that a 30-second poll
would otherwise step over.

## Behavior

- GIVEN a Puma that reports `io_threads`, `requests_count`, `backlog_max`, and `reactor_max`
- WHEN the instrumentation collects
- THEN the exporter serves `puma_io_threads`, `puma_requests_total`,
  `puma_request_backlog_max`, and `puma_reactor_max`

- GIVEN a Puma old enough that it does not report a stat
- WHEN the instrumentation collects
- THEN that stat's metric is absent, instead of being served as zero

- GIVEN several processes reporting `requests_count` under one set of labels
- WHEN the exporter is scraped
- THEN `puma_requests_total` is their sum, and repeated scrapes report the same
  sum rather than accumulating

- GIVEN clustered Puma, where each worker reports its own peaks
- WHEN the instrumentation collects
- THEN `puma_request_backlog_max` and `puma_reactor_max` report the highest value
  one worker reached

- GIVEN the metrics that existed before this change
- WHEN a Puma reports the stats behind them
- THEN their names, labels, and values SHOULD NOT change

## Constraints

- `Puma.stats` is the only source. Nothing here reads Puma internals or adds a
  dependency on the puma gem.
- Both halves of the gem's existing shape are kept: the instrumentation aggregates
  worker stats into one payload, and the type collector turns that payload into
  metrics with no knowledge of Puma.
- Stat names already exported under a different name (`backlog` as
  `request_backlog`) keep that name, so `backlog_max` exports as
  `request_backlog_max`.

## Decisions

- **`requests_count` is exported as a counter named `puma_requests_total`, not a
  gauge.** It is monotonic per worker, so the counter type lets `rate()` account
  for the resets a restart causes. The gem's `Gauge` refuses a `_total` suffix,
  which would have forced a name that reads like a gauge.
- **Counter values from separate processes are summed; gauge values still
  overwrite.** Each process counts only the requests it served, so a sum is the
  fleet total. The collector rebuilds its metrics on every scrape, so summing
  cannot double-count across scrapes.
- **The high water marks report the busiest worker, not the sum of the workers.**
  Puma resets them on every stats call, so each is a peak over the poll interval.
  Summing peaks reports a depth no worker ever reached; the maximum answers whether
  any worker backed up. Summing was the alternative, and would have been consistent
  with how the other worker stats aggregate.
- **A stat Puma does not report is left out of the payload.** It used to be sent as
  zero, which made an old Puma look like a healthy one. Reporting only what Puma
  measured also retires the version check that gated `busy_threads`: that check read
  the Puma version of the *exporter* process, which for a standalone exporter has no
  Puma loaded at all, so the gauge was dropped no matter what the instrumented
  application sent.

## Date

2026-09-30
