# frozen_string_literal: true

require_relative "../test_helper"
require "prometheus_exporter/server"
require "prometheus_exporter/instrumentation"

class PrometheusSolidQueueCollectorTest < Minitest::Test
  include CollectorHelper

  def collector
    @collector ||= PrometheusExporter::Server::SolidQueueCollector.new
  end

  def test_collecting_metrics
    collector.collect(
      "scheduled" => 3,
      "claimed" => 4,
      "orphaned" => 1,
      "failed" => 9,
      "blocked" => 2,
      "expired_blocked" => 0,
      "processes" => 5,
      "dispatcher_lag_seconds" => 12,
    )

    assert_collector_metric_lines(
      [
        "solid_queue_scheduled 3",
        "solid_queue_claimed 4",
        "solid_queue_orphaned 1",
        "solid_queue_failed 9",
        "solid_queue_blocked 2",
        "solid_queue_expired_blocked 0",
        "solid_queue_processes 5",
        "solid_queue_dispatcher_lag_seconds 12",
      ],
    )
  end

  def test_collecting_per_queue_metrics
    collector.collect(
      "processes" => 1,
      "queues" => [
        { "backlog" => 16, "latency_seconds" => 7, "labels" => { "queue" => "default" } },
        { "backlog" => 2, "latency_seconds" => 0, "labels" => { "queue" => "mailers" } },
      ],
    )

    assert_collector_metric_lines(
      [
        "solid_queue_processes 1",
        'solid_queue_queue_backlog{queue="default"} 16',
        'solid_queue_queue_backlog{queue="mailers"} 2',
        'solid_queue_queue_latency_seconds{queue="default"} 7',
        'solid_queue_queue_latency_seconds{queue="mailers"} 0',
      ],
    )
  end

  def test_a_drained_queue_stops_reporting
    stub_monotonic_clock(0) do
      collector.collect(
        "processes" => 1,
        "queues" => [
          { "backlog" => 16, "latency_seconds" => 7, "labels" => { "queue" => "default" } },
          { "backlog" => 2, "latency_seconds" => 0, "labels" => { "queue" => "mailers" } },
        ],
      )
      collector.metrics
    end

    stub_monotonic_clock(max_metric_age + 1) do
      collector.collect("processes" => 1, "queues" => [])

      assert_collector_metric_lines(["solid_queue_processes 1"])
    end
  end

  def test_collecting_metrics_with_client_default_labels
    collector.collect(
      "processes" => 2,
      "custom_labels" => {
        "service" => "jobs",
      },
      "queues" => [{ "backlog" => 16, "latency_seconds" => 7, "labels" => { "queue" => "default" } }],
    )

    assert_collector_metric_lines(
      [
        'solid_queue_processes{service="jobs"} 2',
        'solid_queue_queue_backlog{queue="default",service="jobs"} 16',
        'solid_queue_queue_latency_seconds{queue="default",service="jobs"} 7',
      ],
    )
  end

  def test_a_stopped_producer_stops_reporting
    stub_monotonic_clock(0) do
      collector.collect("processes" => 2)

      assert_equal 1, collector.metrics.size
    end

    stub_monotonic_clock(max_metric_age + 1) { assert_empty collector.metrics }
  end
end
