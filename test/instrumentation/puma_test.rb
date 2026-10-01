# frozen_string_literal: true

require_relative "../test_helper"
require "minitest/stub_const"
require "prometheus_exporter/instrumentation"

class PrometheusInstrumentationPumaTest < Minitest::Test
  CLUSTERED_STATS = {
    workers: 2,
    phase: 0,
    booted_workers: 2,
    old_workers: 0,
    worker_status: [
      {
        pid: 87_819,
        index: 0,
        phase: 0,
        booted: true,
        last_status: {
          backlog: 0,
          running: 5,
          pool_capacity: 3,
          max_threads: 5,
          busy_threads: 2,
          io_threads: 1,
          requests_count: 40,
          backlog_max: 7,
          reactor_max: 2,
        },
      },
      {
        pid: 87_820,
        index: 1,
        phase: 0,
        booted: true,
        last_status: {
          backlog: 1,
          running: 5,
          pool_capacity: 1,
          max_threads: 5,
          busy_threads: 4,
          io_threads: 2,
          requests_count: 60,
          backlog_max: 3,
          reactor_max: 9,
        },
      },
    ],
  }

  SINGLE_STATS = {
    backlog: 1,
    running: 5,
    pool_capacity: 4,
    max_threads: 5,
    busy_threads: 1,
    io_threads: 0,
    requests_count: 25,
    backlog_max: 2,
    reactor_max: 3,
  }

  def collect(stats)
    stub_puma_stats(stats) { PrometheusExporter::Instrumentation::Puma.new.collect }
  end

  def test_clustered_mode_sums_worker_totals
    metric = collect(CLUSTERED_STATS)

    assert_equal 2, metric[:workers]
    assert_equal 1, metric[:request_backlog]
    assert_equal 10, metric[:running_threads]
    assert_equal 4, metric[:thread_pool_capacity]
    assert_equal 10, metric[:max_threads]
    assert_equal 6, metric[:busy_threads]
    assert_equal 3, metric[:io_threads]
    assert_equal 100, metric[:requests_count]
  end

  def test_clustered_mode_reports_the_peak_of_the_busiest_worker
    metric = collect(CLUSTERED_STATS)

    assert_equal 7, metric[:request_backlog_max]
    assert_equal 9, metric[:reactor_max]
  end

  def test_single_mode_reports_the_lone_worker
    metric = collect(SINGLE_STATS)

    assert_equal 1, metric[:request_backlog]
    assert_equal 0, metric[:io_threads]
    assert_equal 25, metric[:requests_count]
    assert_equal 2, metric[:request_backlog_max]
    assert_equal 3, metric[:reactor_max]
    refute_includes metric, :workers
  end

  def test_stats_puma_does_not_report_are_left_out
    metric = collect(SINGLE_STATS.slice(:backlog, :running, :pool_capacity, :max_threads))

    assert_equal 1, metric[:request_backlog]
    refute_includes metric, :busy_threads
    refute_includes metric, :io_threads
    refute_includes metric, :requests_count
    refute_includes metric, :request_backlog_max
    refute_includes metric, :reactor_max
  end

  def test_a_worker_that_has_not_reported_a_status_is_skipped
    stats =
      CLUSTERED_STATS.merge(worker_status: [{ last_status: {} }, *CLUSTERED_STATS[:worker_status]])

    assert_equal collect(CLUSTERED_STATS), collect(stats)
  end

  private

  def stub_puma_stats(stats, &blk)
    puma = Minitest::Mock.new
    puma.expect(:stats, JSON.dump(stats))

    result = Object.stub_const(:Puma, puma, &blk)
    puma.verify
    result
  end
end
