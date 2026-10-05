# encoding: utf-8
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

    # Ellenőrzi és futtatja az esedékes szinkronizációkat
    # DB lock: a next_run_at-et atomikusan frissítjük mielőtt futtatunk
    def self.check_and_run_all
      require 'core_ext'
      require 'infectors'
      AuthSourceLdap.all.each do |source|
        setting = LdapSetting.find_by_auth_source_ldap_id(source.id)
        next unless setting&.schedule_enabled?

        next_run_str = setting.schedule_next_run_at
        next if next_run_str.blank?

        next_run = Time.parse(next_run_str.to_s) rescue nil
        next if next_run.nil? || next_run > Time.current

        # Azonnal frissítjük a next_run_at-et hogy más worker ne fusson be
        new_next = next_run_for(setting)
        setting.update_schedule_timestamps!(Time.current, new_next)

        # Háttérszálban futtatjuk hogy ne blokkolja a kérést
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
    rescue => e
      Rails.logger.error "LdapSync Scheduler check failed: #{e.message}"
    end

  end
end
