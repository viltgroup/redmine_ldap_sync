# encoding: utf-8
require 'yaml'
require 'fileutils'
require 'socket'

module LdapSync
  # Automatic synchronization schedule kept in a file on this node instead of the
  # database. When several Redmine nodes share one database, only the node that
  # holds the file runs the scheduled synchronization.
  #
  # The file lives at <redmine>/config/ldap_sync_local_schedule.yml, unless the
  # LDAP_SYNC_LOCAL_SCHEDULE_FILE environment variable points somewhere else.
  module LocalSchedule

    DEFAULT_PATH = File.join('config', 'ldap_sync_local_schedule.yml')
    FILE_HEADER  = "# Redmine LDAP Sync - schedule of this node only.\n" \
                   "# Managed from Administration > LDAP Synchronization > Schedule.\n"

    # The schedule of one LDAP server; answers the same schedule_* methods as
    # LdapSetting so LdapSync::Scheduler and the schedule form can use either.
    class Entry
      attr_reader :attributes

      def initialize(attributes = nil)
        @attributes = attributes.is_a?(Hash) ? attributes.to_hash.stringify_keys : {}
      end

      def schedule_enabled?
        [true, '1', 'yes'].include? attributes['schedule_enabled']
      end

      def schedule_frequency
        attributes['schedule_frequency'] || 'daily'
      end

      def schedule_hour
        (attributes['schedule_hour'] || 2).to_i
      end

      def schedule_minute
        (attributes['schedule_minute'] || 0).to_i
      end

      def schedule_next_run_at
        attributes['schedule_next_run_at']
      end

      def schedule_last_run_at
        attributes['schedule_last_run_at']
      end
    end

    def self.path
      ENV['LDAP_SYNC_LOCAL_SCHEDULE_FILE'].presence || Rails.root.join(DEFAULT_PATH).to_s
    end

    def self.hostname
      Socket.gethostname
    rescue StandardError
      '?'
    end

    def self.find(source_id)
      Entry.new(read[source_id.to_s])
    end

    # Saves the schedule form params of the given LDAP server
    def self.save(source_id, params)
      frequency = params[:schedule_frequency].to_s
      entry = Entry.new(
        'schedule_enabled'   => params[:schedule_enabled] == '1',
        'schedule_frequency' => Scheduler::FREQUENCIES.key?(frequency) ? frequency : 'daily',
        'schedule_hour'      => params[:schedule_hour].to_i,
        'schedule_minute'    => params[:schedule_minute].to_i
      )
      entry.attributes['schedule_next_run_at'] = Scheduler.next_run_for(entry)&.iso8601

      transaction do |data|
        previous = Entry.new(data[source_id.to_s])
        entry.attributes['schedule_last_run_at'] = previous.schedule_last_run_at
        data[source_id.to_s] = entry.attributes
      end
      entry
    end

    def self.disable!(source_id)
      return unless find(source_id).schedule_enabled?

      transaction do |data|
        data[source_id.to_s] = Entry.new(data[source_id.to_s]).attributes.
          merge('schedule_enabled' => false, 'schedule_next_run_at' => nil)
      end
    end

    # Records a synchronization run (e.g. a manual one) on this node's schedule
    def self.record_run!(source_id, time = Time.current)
      return unless find(source_id).schedule_enabled?

      transaction do |data|
        data[source_id.to_s] = stamp(Entry.new(data[source_id.to_s]), time)
      end
    end

    # Returns true when this node's schedule of the given LDAP server is due, after
    # moving its next run forward. The file lock makes sure only one worker process
    # of this node gets true for the same run.
    def self.claim_due_run!(source_id)
      return false unless File.exist?(path)
      return false unless Scheduler.due?(find(source_id))

      transaction do |data|
        entry = Entry.new(data[source_id.to_s])
        next false unless Scheduler.due?(entry)

        data[source_id.to_s] = stamp(entry, Time.current)
        true
      end
    end

    def self.read
      File.exist?(path) ? parse(File.read(path)) : {}
    end

    # Yields the file contents under an exclusive lock, then writes them back
    def self.transaction
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, File::RDWR | File::CREAT, 0644) do |file|
        file.flock(File::LOCK_EX)
        data = parse(file.read)
        result = yield data
        file.rewind
        file.truncate(0)
        file.write(FILE_HEADER + data.to_yaml)
        file.flush
        result
      end
    end

    def self.parse(content)
      data = YAML.safe_load(content.to_s)
      data.is_a?(Hash) ? data : {}
    rescue Psych::Exception => e
      Rails.logger.error "LdapSync: ignoring unreadable local schedule #{path}: #{e.message}"
      {}
    end

    def self.stamp(entry, time)
      entry.attributes.merge(
        'schedule_last_run_at' => time.iso8601,
        'schedule_next_run_at' => Scheduler.next_run_for(entry)&.iso8601
      )
    end
    private_class_method :parse, :stamp

  end
end
