# CIR-002: Collect Solid Queue stats

## Intent

Give operators running Solid Queue the same view the exporter already offers Sidekiq,
Resque and GoodJob users: how much work is waiting, how much is stuck, and whether the
queue is being drained as fast as it fills.

## Behavior

- GIVEN a Solid Queue installation
- WHEN the instrumentation collects
- THEN the exporter serves the count of scheduled, claimed, failed and blocked
  executions, and of registered processes

- GIVEN jobs claimed by a worker that is no longer registered
- WHEN the instrumentation collects
- THEN `solid_queue_orphaned` counts them, because they are work nothing is doing

- GIVEN a job whose scheduled time has passed but which the dispatcher has not moved
  into the ready table
- WHEN the instrumentation collects
- THEN `solid_queue_dispatcher_lag_seconds` reports how long the oldest such job has
  waited

- GIVEN nothing is due for dispatch
- WHEN the instrumentation collects
- THEN `solid_queue_dispatcher_lag_seconds` is zero, not absent, so the series stays
  continuous

- GIVEN queues holding ready jobs
- WHEN the instrumentation collects
- THEN each reports `solid_queue_queue_backlog` and `solid_queue_queue_latency_seconds`
  under its own `queue` label

- GIVEN a queue that drains
- WHEN the exporter is next scraped
- THEN that queue's series disappear rather than reporting their last values

- GIVEN the process reporting stats stops
- WHEN the exporter is next scraped
- THEN no Solid Queue metrics are served, so the gap is visible instead of the last
  known numbers persisting

- GIVEN an application not using Solid Queue
- WHEN the exporter runs
- THEN nothing changes: the instrumentation is only started by the application that
  wants it

## Constraints

- Read through Solid Queue's own models and scopes rather than issuing SQL, so the
  schema stays Solid Queue's business.
- One query per metric at most, since the loop runs every 30 seconds against the
  queue database. Per-queue backlog and latency are each a single grouped query
  rather than one per queue.
- Follow the shapes already in the codebase: GoodJob for whole-installation gauges,
  SidekiqQueue for per-queue gauges carrying a label.

## Decisions

- **One instrumentation covering both the installation and its queues, not two.**
  Sidekiq splits these across SidekiqStats and SidekiqQueue because its data comes
  from different Redis structures. Solid Queue's all comes from one database, in one
  collection pass, so splitting it would double the queries and the configuration for
  no gain.
- **Report dispatcher lag as the age of the oldest due job, not a count of due jobs.**
  A count answers how many are late but not by how much, and a dispatcher that is
  keeping up momentarily shows a non-zero count simply because jobs became due between
  polls. Seconds overdue distinguishes a busy dispatcher from a stalled one.
- **Reset the per-queue gauges on each scrape.** A gauge holds its last observation
  forever, so a queue that drains would otherwise report its final backlog
  indefinitely. The whole-installation gauges need no reset, since each collection
  overwrites the single series.
- **Serve nothing once the producing process stops.** Carrying the last known counts
  past the producer's death makes a dead supervisor look like an idle one. An absent
  series is something an alert can see.
- **Leave it to the application to start this in one process.** The queries describe
  the whole installation, so every worker running them would multiply the load without
  adding information. The exporter cannot tell which process should own that, and
  Solid Queue already exposes `supervisor?` for the application to decide.

## Date

2026-09-30
