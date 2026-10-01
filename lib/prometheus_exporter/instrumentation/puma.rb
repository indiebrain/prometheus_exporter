# frozen_string_literal: true

require "json"

# collects stats from puma
module PrometheusExporter::Instrumentation
  class Puma < PeriodicStats
    # Per-worker stats whose worker values add up to a meaningful total. Maps the
    # name Puma reports to the name this gem exports.
    SUMMED_WORKER_STATS = {
      "backlog" => :request_backlog,
      "running" => :running_threads,
      "pool_capacity" => :thread_pool_capacity,
      "max_threads" => :max_threads,
      "busy_threads" => :busy_threads,
      "io_threads" => :io_threads,
      "requests_count" => :requests_total,
    }.freeze

    # Per-worker high water marks, which Puma resets every time it is asked for
    # stats. Summing peaks would report a total no worker ever reached, so these
    # carry the peak of the busiest worker instead.
    PEAK_WORKER_STATS = {
      "backlog_max" => :request_backlog_max,
      "reactor_max" => :reactor_max,
    }.freeze

    def self.start(client: nil, frequency: 30, labels: {})
      puma_collector = new(labels)
      client ||= PrometheusExporter::Client.default

      worker_loop do
        metric = puma_collector.collect
        client.send_json metric
      end

      super
    end

    def initialize(metric_labels = {})
      @metric_labels = metric_labels
    end

    def collect
      metric = {
        pid: pid,
        type: "puma",
        hostname: ::PrometheusExporter.hostname,
        metric_labels: @metric_labels,
      }
      collect_puma_stats(metric)
      metric
    end

    def pid
      @pid = ::Process.pid
    end

    def collect_puma_stats(metric)
      stats = JSON.parse(::Puma.stats)

      if stats.key?("workers")
        metric[:phase] = stats["phase"]
        metric[:workers] = stats["workers"]
        metric[:booted_workers] = stats["booted_workers"]
        metric[:old_workers] = stats["old_workers"]

        stats["worker_status"].each do |worker|
          next if worker["last_status"].empty?
          collect_worker_status(metric, worker["last_status"])
        end
      else
        collect_worker_status(metric, stats)
      end
    end

    private

    # Which stats a worker reports varies by Puma version and configuration, so
    # only the ones Puma actually reported are carried into the metric. A stat
    # left out of the metric is left out of the exported metrics too, rather than
    # being exported as a zero the server never measured.
    def collect_worker_status(metric, status)
      SUMMED_WORKER_STATS.each do |stat, name|
        next unless status.key?(stat)
        metric[name] = (metric[name] || 0) + status[stat]
      end

      PEAK_WORKER_STATS.each do |stat, name|
        next unless status.key?(stat)
        metric[name] = [metric[name] || 0, status[stat]].max
      end
    end
  end
end
