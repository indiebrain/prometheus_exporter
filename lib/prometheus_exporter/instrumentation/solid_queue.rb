# frozen_string_literal: true

# collects stats from Solid Queue
module PrometheusExporter::Instrumentation
  class SolidQueue < PeriodicStats
    def self.start(client: nil, frequency: 30)
      solid_queue_collector = new
      client ||= PrometheusExporter::Client.default

      worker_loop { client.send_json(solid_queue_collector.collect) }

      super
    end

    def collect
      {
        type: "solid_queue",
        scheduled: ::SolidQueue::ScheduledExecution.count,
        claimed: ::SolidQueue::ClaimedExecution.count,
        orphaned: ::SolidQueue::ClaimedExecution.orphaned.count,
        failed: ::SolidQueue::FailedExecution.count,
        blocked: ::SolidQueue::BlockedExecution.count,
        expired_blocked: ::SolidQueue::BlockedExecution.expired.count,
        processes: ::SolidQueue::Process.count,
        dispatcher_lag_seconds: dispatcher_lag_seconds,
        queues: collect_queue_stats,
      }
    end

    private

    # How far past its scheduled time the oldest due job still sits in the
    # scheduled table. Zero means the dispatcher has moved everything due.
    def dispatcher_lag_seconds
      oldest_due = ::SolidQueue::ScheduledExecution.due.minimum(:scheduled_at)

      age_in_seconds(oldest_due)
    end

    def collect_queue_stats
      backlogs = ::SolidQueue::ReadyExecution.group(:queue_name).count
      oldest = ::SolidQueue::ReadyExecution.group(:queue_name).minimum(:created_at)

      backlogs.map do |queue_name, backlog|
        {
          backlog: backlog,
          latency_seconds: age_in_seconds(oldest[queue_name]),
          labels: {
            queue: queue_name,
          },
        }
      end
    end

    def age_in_seconds(time)
      return 0 if time.nil?

      [Time.now.utc - time.to_time.utc, 0].max
    end
  end
end
