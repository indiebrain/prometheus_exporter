# frozen_string_literal: true

module PrometheusExporter::Server
  class PumaCollector < TypeCollector
    MAX_PUMA_METRIC_AGE = 30

    PUMA_GAUGES = {
      workers: "Number of puma workers.",
      booted_workers: "Number of puma workers booted.",
      old_workers: "Number of old puma workers.",
      running_threads: "Number of puma threads currently running.",
      request_backlog: "Number of requests waiting to be processed by a puma thread.",
      request_backlog_max:
        "Peak number of requests waiting to be processed by a puma thread, since the previous collection.",
      thread_pool_capacity: "Number of puma threads available at current scale.",
      max_threads: "Number of puma threads at available at max scale.",
      busy_threads:
        "Wholistic stat reflecting the overall current state of work to be done and the capacity to do it",
      io_threads:
        "Number of puma threads serving requests marked as IO bound, which are allowed to exceed max_threads.",
      reactor_max:
        "Peak number of requests buffering in puma's reactor, since the previous collection.",
    }.freeze

    def initialize
      @puma_metrics = MetricsContainer.new(ttl: MAX_PUMA_METRIC_AGE)
      @puma_metrics.filter = ->(new_metric, old_metric) do
        new_metric["pid"] == old_metric["pid"] && new_metric["hostname"] == old_metric["hostname"]
      end
    end

    def type
      "puma"
    end

    def metrics
      return [] if @puma_metrics.length == 0

      metrics = {}

      @puma_metrics.map do |m|
        labels = {}
        labels.merge!(phase: m["phase"]) if m["phase"]
        labels.merge!(m["custom_labels"]) if m["custom_labels"]
        labels.merge!(m["metric_labels"]) if m["metric_labels"]

        PUMA_GAUGES.each do |k, help|
          k = k.to_s
          if v = m[k]
            g = metrics[k] ||= PrometheusExporter::Metric::Gauge.new("puma_#{k}", help)
            g.observe(v, labels)
          end
        end

        # Every reporting process counts only the requests it served itself, so
        # the counts add up across processes instead of overwriting each other
        # the way a gauge does.
        if requests = m["requests_count"]
          requests_counter(metrics).observe(requests, labels)
        end
      end

      metrics.values
    end

    def collect(obj)
      @puma_metrics << obj
    end

    private

    def requests_counter(metrics)
      metrics["requests_count"] ||= PrometheusExporter::Metric::Counter.new(
        "puma_requests_total",
        "Number of requests puma has served since its workers booted.",
      )
    end
  end
end
