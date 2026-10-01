# frozen_string_literal: true

require_relative "../test_helper"
require "mini_racer"
require "prometheus_exporter/server"
require "prometheus_exporter/instrumentation"

class PrometheusPumaCollectorTest < Minitest::Test
  include CollectorHelper

  def collector
    @collector ||= PrometheusExporter::Server::PumaCollector.new
  end

  def test_collecting_metrics_for_different_hosts_without_custom_labels
    collector.collect(
      "type" => "puma",
      "pid" => "1000",
      "hostname" => "test1.example.com",
      "phase" => 0,
      "workers" => 2,
      "booted_workers" => 2,
      "old_workers" => 0,
      "request_backlog" => 0,
      "running_threads" => 4,
      "thread_pool_capacity" => 10,
      "max_threads" => 10,
      "busy_threads" => 2,
    )

    collector.collect(
      "type" => "puma",
      "pid" => "1000",
      "hostname" => "test2.example.com",
      "phase" => 0,
      "workers" => 4,
      "booted_workers" => 4,
      "old_workers" => 0,
      "request_backlog" => 1,
      "running_threads" => 9,
      "thread_pool_capacity" => 10,
      "max_threads" => 10,
      "busy_threads" => 3,
    )

    # overwriting previous metrics from first host
    collector.collect(
      "type" => "puma",
      "pid" => "1000",
      "hostname" => "test1.example.com",
      "phase" => 0,
      "workers" => 3,
      "booted_workers" => 3,
      "old_workers" => 0,
      "request_backlog" => 2,
      "running_threads" => 8,
      "thread_pool_capacity" => 10,
      "max_threads" => 10,
      "busy_threads" => 4,
    )

    metrics = collector.metrics
    assert_equal 8, metrics.size
    assert_equal "puma_workers{phase=\"0\"} 3", metrics.first.metric_text
  end

  def test_collecting_metrics_for_different_hosts_with_custom_labels
    collector.collect(
      "type" => "puma",
      "pid" => "1000",
      "hostname" => "test1.example.com",
      "phase" => 0,
      "workers" => 2,
      "booted_workers" => 2,
      "old_workers" => 0,
      "request_backlog" => 0,
      "running_threads" => 4,
      "thread_pool_capacity" => 10,
      "max_threads" => 10,
      "busy_threads" => 2,
      "custom_labels" => {
        "hostname" => "test1.example.com",
      },
    )

    collector.collect(
      "type" => "puma",
      "pid" => "1000",
      "hostname" => "test2.example.com",
      "phase" => 0,
      "workers" => 4,
      "booted_workers" => 4,
      "old_workers" => 0,
      "request_backlog" => 1,
      "running_threads" => 9,
      "thread_pool_capacity" => 10,
      "max_threads" => 10,
      "busy_threads" => 3,
      "custom_labels" => {
        "hostname" => "test2.example.com",
      },
    )

    # overwriting previous metrics from first host
    collector.collect(
      "type" => "puma",
      "pid" => "1000",
      "hostname" => "test1.example.com",
      "phase" => 0,
      "workers" => 3,
      "booted_workers" => 3,
      "old_workers" => 0,
      "request_backlog" => 2,
      "running_threads" => 8,
      "thread_pool_capacity" => 10,
      "max_threads" => 10,
      "busy_threads" => 4,
      "custom_labels" => {
        "hostname" => "test1.example.com",
      },
    )

    metrics = collector.metrics
    assert_equal 8, metrics.size
    assert_equal "puma_workers{phase=\"0\",hostname=\"test2.example.com\"} 4\n" \
                   "puma_workers{phase=\"0\",hostname=\"test1.example.com\"} 3",
                 metrics.first.metric_text
  end

  def test_collecting_puma_8_metrics
    collector.collect(
      "type" => "puma",
      "pid" => "1000",
      "hostname" => "test1.example.com",
      "request_backlog" => 1,
      "request_backlog_max" => 7,
      "io_threads" => 3,
      "reactor_max" => 9,
      "requests_count" => 100,
    )

    assert_collector_metric_lines [
                                    "puma_request_backlog 1",
                                    "puma_request_backlog_max 7",
                                    "puma_io_threads 3",
                                    "puma_reactor_max 9",
                                    "puma_requests_total 100",
                                  ]
  end

  def test_requests_are_counted_rather_than_gauged
    collector.collect(
      "type" => "puma",
      "pid" => "1000",
      "hostname" => "test1.example.com",
      "requests_count" => 100,
    )

    requests = collector.metrics.first

    assert_equal "counter", requests.type
    assert_equal "puma_requests_total", requests.name
  end

  def test_requests_from_every_process_add_up
    collector.collect(
      "type" => "puma",
      "pid" => "1000",
      "hostname" => "test1.example.com",
      "requests_count" => 100,
    )

    collector.collect(
      "type" => "puma",
      "pid" => "1001",
      "hostname" => "test1.example.com",
      "requests_count" => 60,
    )

    assert_collector_metric_lines ["puma_requests_total 160"]
    # The counter is rebuilt from the reported totals on each scrape, so asking
    # twice reports the same total rather than doubling it.
    assert_collector_metric_lines ["puma_requests_total 160"]
  end

  def test_stats_the_client_did_not_report_are_not_exported
    collector.collect(
      "type" => "puma",
      "pid" => "1000",
      "hostname" => "test1.example.com",
      "request_backlog" => 1,
    )

    assert_collector_metric_lines ["puma_request_backlog 1"]
  end
end
