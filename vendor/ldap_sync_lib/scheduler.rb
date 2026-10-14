# encoding: utf-8
require 'local_schedule'

module LdapSync
  module Scheduler

    FREQUENCIES = {
      'every_15_min' => 15.minutes,
      'every_30_min' => 30.minutes,
      'hourly'       => 1.hour,
      'daily'        => 1.day
    }.freeze

    # Kiszámolja a következő futás időpontját a beállítások alapján
    def self.next_run_for(setting)
      return nil unless setting.schedule_enabled?

      freq = setting.schedule_frequency
      now  = Time.current

      case freq
      when 'every_15_min', 'every_30_min'
        interval = FREQUENCIES[freq]
        base = now.beginning_of_hour
        base += interval while base <= now
        base

      when 'hourly'
        minute = setting.schedule_minute.to_i
        base   = now.beginning_of_hour + minute.minutes
        base  += 1.hour if base <= now
        base

      when 'daily'
        hour   = setting.schedule_hour.to_i
        minute = setting.schedule_minute.to_i
        candidate = now.beginning_of_day + hour.hours + minute.minutes
        candidate += 1.day if candidate <= now
        candidate
      end
    end

    # Whether the schedule (an LdapSetting or a LocalSchedule::Entry) is enabled and its next run has passed
    def self.due?(schedule)
      return false unless schedule&.schedule_enabled?

      next_run = Time.parse(schedule.schedule_next_run_at.to_s) rescue nil
      next_run.present? && next_run <= Time.current
    end

    # Ellenőrzi és futtatja az esedékes szinkronizációkat
    # DB lock: a next_run_at-et atomikusan frissítjük mielőtt futtatunk
    def self.check_and_run_all
      require 'core_ext'
      require 'infectors'
      AuthSourceLdap.all.each do |source|
        setting = LdapSetting.find_by_auth_source_ldap_id(source.id)
        if due?(setting)
          # Azonnal frissítjük a next_run_at-et hogy más worker ne fusson be
          setting.update_schedule_timestamps!(Time.current, next_run_for(setting))
          run_in_background(source)
        end

        # Schedule saved locally: only runs on the node that has it
        run_in_background(source) if LocalSchedule.claim_due_run!(source.id)
      end
    rescue => e
      Rails.logger.error "LdapSync Scheduler check failed: #{e.message}"
    end

    # Háttérszálban futtatjuk hogy ne blokkolja a kérést
    def self.run_in_background(source)
      Thread.new do
        begin
          AuthSourceLdap.running_rake!
          source.sync_groups
          source.sync_users
        rescue => e
          Rails.logger.error "LdapSync Scheduler error for #{source.name}: #{e.message}"
        end
      end
    end

  end
end
