# frozen_string_literal: true

module PrometheusExporter::Server
  class SolidQueueCollector < TypeCollector
    MAX_METRIC_AGE = 60

    SOLID_QUEUE_GAUGES = {
      "scheduled" => "Number of Solid Queue jobs scheduled to run later.",
      "claimed" => "Number of Solid Queue jobs claimed by a worker.",
      "orphaned" => "Number of claimed Solid Queue jobs whose worker is gone.",
      "failed" => "Number of failed Solid Queue jobs.",
      "blocked" => "Number of Solid Queue jobs blocked by a concurrency limit.",
      "expired_blocked" => "Number of blocked Solid Queue jobs past their expiry.",
      "processes" => "Number of registered Solid Queue processes.",
      "dispatcher_lag_seconds" =>
        "Seconds the oldest due Solid Queue job has waited to be dispatched.",
    }.freeze

    SOLID_QUEUE_QUEUE_GAUGES = {
      "backlog" => "Number of Solid Queue jobs ready to run in the queue.",
      "latency_seconds" => "Seconds the oldest ready job in the queue has waited.",
    }.freeze

    QUEUE_PREFIX = "solid_queue_queue_"

    def initialize
      @solid_queue_metrics = MetricsContainer.new(ttl: MAX_METRIC_AGE)
      @queue_metrics = MetricsContainer.new(ttl: MAX_METRIC_AGE)
      @gauges = {}
    end

    def type
      "solid_queue"
    end

    # A queue stops reporting as soon as it drains, so its gauges are reset
    # each scrape to drop queues that are no longer there. Nothing is reported
    # at all once the producer stops, so a dead worker reads as absent rather
    # than as its last known numbers.
    def metrics
      return [] if solid_queue_metrics.length == 0

      SOLID_QUEUE_QUEUE_GAUGES.each_key { |name| gauges["#{QUEUE_PREFIX}#{name}"]&.reset! }

      solid_queue_metrics.each do |metric|
        observe(SOLID_QUEUE_GAUGES, "solid_queue_", metric, metric.fetch("custom_labels", {}))
      end

      queue_metrics.each do |metric|
        observe(SOLID_QUEUE_QUEUE_GAUGES, QUEUE_PREFIX, metric, metric.fetch("labels", {}))
      end

      gauges.values
    end

    def collect(object)
      @solid_queue_metrics << object

      object.fetch("queues", []).each do |queue|
        queue["labels"] = queue.fetch("labels", {}).merge(object["custom_labels"] || {})
        @queue_metrics << queue
      end
    end

    private

    attr_reader :solid_queue_metrics, :queue_metrics, :gauges

    def observe(definitions, prefix, metric, labels)
      definitions.each do |name, help|
        value = metric[name]
        next if value.nil?

        full_name = "#{prefix}#{name}"
        gauge = gauges[full_name] ||= PrometheusExporter::Metric::Gauge.new(full_name, help)
        gauge.observe(value, labels)
      end
    end
  end
end
