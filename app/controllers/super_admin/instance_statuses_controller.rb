class SuperAdmin::InstanceStatusesController < SuperAdmin::ApplicationController
  def show
    @metrics = {}
    chatwoot_version
    sha
    postgres_status
    redis_metrics
    blob_storage_metrics
    disk_metrics
    chatwoot_edition
    instance_meta
  end

  def chatwoot_edition
    @metrics['Chatwoot edition'] = if ChatwootApp.enterprise?
                                     'Enterprise'
                                   elsif ChatwootApp.custom?
                                     'Custom'
                                   else
                                     'Community'
                                   end
  end

  def instance_meta
    @metrics['Database Migrations'] = ActiveRecord::Base.connection.migration_context.needs_migration? ? 'pending' : 'completed'
  end

  def chatwoot_version
    @metrics['Chatwoot version'] = Chatwoot.config[:version]
  end

  def sha
    @metrics['Git SHA'] = GIT_HASH
  end

  def postgres_status
    @metrics['Postgres alive'] = if ActiveRecord::Base.connection.active?
                                   'true'
                                 else
                                   'false'
                                 end
  end

  def redis_metrics
    r = Redis.new(Redis::Config.app)
    if r.ping == 'PONG'
      redis_server = r.info
      @metrics['Redis alive'] = 'true'
      @metrics['Redis version'] = redis_server['redis_version']
      @metrics['Redis number of connected clients'] = redis_server['connected_clients']
      @metrics["Redis 'maxclients' setting"] = redis_server['maxclients']
      @metrics['Redis memory used'] = redis_server['used_memory_human']
      @metrics['Redis memory peak'] = redis_server['used_memory_peak_human']
      @metrics['Redis total memory available'] = redis_server['total_system_memory_human']
      @metrics["Redis 'maxmemory' setting"] = redis_server['maxmemory']
      @metrics["Redis 'maxmemory_policy' setting"] = redis_server['maxmemory_policy']
    end
  rescue Redis::CannotConnectError
    @metrics['Redis alive'] = false
  end

  # Attachments live in the configured ActiveStorage service (Azure Blob in production).
  # Object stores expose no capacity ceiling to read back, so we report what Rails tracks
  # and only render a total when STORAGE_QUOTA_GB is set — as a budget marker, not a hard limit.
  def blob_storage_metrics
    used = ActiveStorage::Blob.sum(:byte_size)
    quota = storage_quota_bytes

    usage = human_size(used)
    usage += " / #{human_size(quota)} (#{percent_of(used, quota)}%)" if quota

    @metrics["Blob storage (#{storage_service_name})"] = "#{usage} in #{ActiveStorage::Blob.count} files"
  rescue StandardError => e
    @metrics['Blob storage'] = "unavailable (#{e.class})"
  end

  # `df` inside the container reports the filesystem backing the overlay, which is the VM
  # disk itself — where Postgres, Redis and the Docker images live. Unlike the object store,
  # this one can actually fill up and take the instance down.
  def disk_metrics
    total, used = disk_usage
    return if total.zero?

    @metrics['Disk'] = "#{human_size(used)} / #{human_size(total)} (#{percent_of(used, total)}%)"
  end

  private

  def storage_service_name
    ActiveStorage::Blob.service.class.name.demodulize.delete_suffix('Service')
  end

  def storage_quota_bytes
    gb = InstallationConfig.find_by(name: 'STORAGE_QUOTA_GB')&.value.to_f
    return if gb <= 0

    (gb * (1024**3)).round
  end

  def disk_usage
    fields = `df -kP /`.lines[1].to_s.split
    return [0, 0] if fields.size < 3

    [fields[1].to_i * 1024, fields[2].to_i * 1024]
  rescue StandardError
    [0, 0]
  end

  def human_size(bytes)
    ActiveSupport::NumberHelper.number_to_human_size(bytes)
  end

  def percent_of(part, whole)
    return 0 if whole.to_i.zero?

    (part * 100.0 / whole).round(1)
  end
end
