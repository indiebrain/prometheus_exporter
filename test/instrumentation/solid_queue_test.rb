# frozen_string_literal: true

require_relative "../test_helper"
require "minitest/stub_const"
require "prometheus_exporter/instrumentation"

class PrometheusInstrumentationSolidQueueTest < Minitest::Test
  # Stands in for an ActiveRecord relation, answering only what the
  # instrumentation asks of it. `scoped` is what the named scopes return.
  class FakeRelation
    def initialize(count: 0, minimum: nil, scoped: nil)
      @count = count
      @minimum = minimum
      @scoped = scoped
    end

    attr_reader :count

    def minimum(_attribute)
      @minimum
    end

    def group(_attribute)
      self
    end

    def due
      @scoped || self
    end
    alias orphaned due
    alias expired due
  end

  def test_it_counts_each_execution_state
    metric =
      collect(
        scheduled: FakeRelation.new(count: 3),
        claimed: FakeRelation.new(count: 4, scoped: FakeRelation.new(count: 1)),
        failed: FakeRelation.new(count: 9),
        blocked: FakeRelation.new(count: 2, scoped: FakeRelation.new(count: 1)),
        processes: FakeRelation.new(count: 5),
      )

    assert_equal "solid_queue", metric[:type]
    assert_equal 3, metric[:scheduled]
    assert_equal 4, metric[:claimed]
    assert_equal 1, metric[:orphaned]
    assert_equal 9, metric[:failed]
    assert_equal 2, metric[:blocked]
    assert_equal 1, metric[:expired_blocked]
    assert_equal 5, metric[:processes]
  end

  def test_dispatcher_lag_is_the_age_of_the_oldest_due_job
    overdue = Time.now.utc - 12

    metric = collect(scheduled: FakeRelation.new(scoped: FakeRelation.new(minimum: overdue)))

    assert_in_delta 12, metric[:dispatcher_lag_seconds], 1
  end

  def test_dispatcher_lag_is_zero_when_nothing_is_due
    metric = collect(scheduled: FakeRelation.new(scoped: FakeRelation.new(minimum: nil)))

    assert_equal 0, metric[:dispatcher_lag_seconds]
  end

  def test_it_reports_backlog_and_latency_per_queue
    waited = Time.now.utc - 30

    metric =
      collect(
        ready:
          FakeRelation.new(
            count: {
              "default" => 16,
              "mailers" => 2,
            },
            minimum: {
              "default" => waited,
              "mailers" => nil,
            },
          ),
      )

    default, mailers = metric[:queues]

    assert_equal({ queue: "default" }, default[:labels])
    assert_equal 16, default[:backlog]
    assert_in_delta 30, default[:latency_seconds], 1

    assert_equal({ queue: "mailers" }, mailers[:labels])
    assert_equal 2, mailers[:backlog]
    assert_equal 0, mailers[:latency_seconds]
  end

  def test_no_queues_report_when_nothing_is_ready
    metric = collect(ready: FakeRelation.new(count: {}, minimum: {}))

    assert_empty metric[:queues]
  end

  private

  def collect(
    scheduled: FakeRelation.new,
    claimed: FakeRelation.new,
    failed: FakeRelation.new,
    blocked: FakeRelation.new,
    processes: FakeRelation.new,
    ready: FakeRelation.new(count: {}, minimum: {})
  )
    solid_queue = Module.new
    solid_queue.const_set(:ScheduledExecution, scheduled)
    solid_queue.const_set(:ClaimedExecution, claimed)
    solid_queue.const_set(:FailedExecution, failed)
    solid_queue.const_set(:BlockedExecution, blocked)
    solid_queue.const_set(:Process, processes)
    solid_queue.const_set(:ReadyExecution, ready)

    Object.stub_const(:SolidQueue, solid_queue) do
      PrometheusExporter::Instrumentation::SolidQueue.new.collect
    end
  end
end
