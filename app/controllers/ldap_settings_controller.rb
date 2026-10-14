# encoding: utf-8
class LdapSettingsController < ApplicationController
  layout 'admin'
  menu_item :ldap_sync

  before_action :require_admin
  before_action :find_ldap_setting, :only => [:show, :edit, :update, :test, :enable, :disable, :update_schedule, :update_local_schedule, :run_now]
  before_action :update_ldap_setting_from_params, :only => [:edit, :update, :test]

  if respond_to? :skip_before_action
    skip_before_action :verify_authenticity_token, :if => :js_request?
  end

  def index
    @ldap_settings = LdapSetting.all
    respond_to do |format|
      format.html
    end
  end

  def base_settings
    respond_to do |format|
      format.js
    end
  end

  def show
    redirect_to edit_ldap_setting_path(@ldap_setting)
  end

  def edit
    respond_to do |format|
      format.html
    end
  end

  def disable
    @ldap_setting.disable!
    flash[:notice] = l(:text_ldap_setting_successfully_updated)
    redirect_to_referer_or ldap_settings_path
  end

  def enable
    @ldap_setting.active = true
    respond_to do |format|
      if @ldap_setting.save
        format.html { flash[:notice] = l(:text_ldap_setting_successfully_updated); redirect_to_referer_or ldap_settings_path }
      else
        format.html { flash[:error] = l(:error_cannot_enable_with_invalid_settings); redirect_to_referer_or ldap_settings_path }
      end
    end
  end

  def test
    return render 'ldap_setting_invalid' unless @ldap_setting.valid?

    ldap_test = params[:ldap_test] || {}
    users  = ldap_test.fetch(:test_users, '').to_s.split(',')
    groups = ldap_test.fetch(:test_groups, '').to_s.split(',')
    [users, groups].each { |l| l.map(&:strip).reject(&:blank?) }

    @test = LdapTest.new(@ldap_setting)
    @test.bind_user     = ldap_test[:bind_user]
    @test.bind_password = ldap_test[:bind_password]

    if @test.valid?
      @test.run_with_users_and_groups(users, groups)
    else
      render 'ldap_test_invalid'
    end
  end

  def update
    respond_to do |format|
      if @ldap_setting.save
        format.html { flash[:notice] = l(:text_ldap_setting_successfully_updated); redirect_to_referer_or ldap_settings_path }
      else
        format.html { render 'edit' }
      end
    end
  end

  def update_schedule
    @ldap_setting.save_schedule(params[:schedule] || {})
    notices = [l(:text_schedule_successfully_updated)]

    # With both automatic modes enabled this node would run every synchronization twice
    if @ldap_setting.schedule_enabled? && LdapSync::LocalSchedule.find(@ldap_setting.id).schedule_enabled?
      LdapSync::LocalSchedule.disable!(@ldap_setting.id)
      notices << l(:text_local_auto_sync_disabled, :host => LdapSync::LocalSchedule.hostname)
    end
    flash[:notice] = notices.join(' ')
    redirect_to_schedule
  rescue SystemCallError => e
    local_schedule_error(e)
  end

  def update_local_schedule
    schedule = LdapSync::LocalSchedule.save(@ldap_setting.id, params[:schedule] || {})
    notices = [l(:text_schedule_successfully_updated)]

    # The shared schedule would keep running on every node, which is what the local one is meant to avoid
    if schedule.schedule_enabled? && @ldap_setting.schedule_enabled?
      @ldap_setting.disable_schedule!
      notices << l(:text_shared_auto_sync_disabled)
    end
    flash[:notice] = notices.join(' ')
    redirect_to_schedule
  rescue SystemCallError => e
    local_schedule_error(e)
  end

  def run_now
    result = []
    begin
      # Infectorok betöltése ha még nem törtét meg
      vendor_lib = File.expand_path('../../vendor/ldap_sync_lib', __FILE__)
      $LOAD_PATH.unshift(vendor_lib) unless $LOAD_PATH.include?(vendor_lib)
      require 'core_ext'
      require 'infectors'

      source = @ldap_setting.auth_source_ldap

      # running_rake! csak akkor hívható ha az infector be van töltve
      AuthSourceLdap.running_rake! if AuthSourceLdap.respond_to?(:running_rake!)

      result << "▶ Starting manual sync for '#{source.name}'..."
      result << ""

      result << "── Groups ──"
      source.sync_groups
      result << "✓ Groups synchronized"
      result << ""

      result << "── Users ──"
      source.sync_users
      result << "✓ Users synchronized"
      result << ""
      result << "✓ Sync completed successfully."

      # Frissítjük a last_run_at értéket
      next_run = LdapSync::Scheduler.next_run_for(@ldap_setting)
      @ldap_setting.update_schedule_timestamps!(Time.current, next_run)
      LdapSync::LocalSchedule.record_run!(@ldap_setting.id)
    rescue => e
      result << "✗ Error: #{e.message}"
      Rails.logger.error "LdapSync manual run error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    end

    @result = result.join("\n")
    respond_to do |format|
      format.text
    end
  end

  private

    def js_request?
      request.format.js?
    end

    def redirect_to_schedule
      redirect_to edit_ldap_setting_path(@ldap_setting, :tab => 'Schedule')
    end

    # The local schedule file could not be read or written (e.g. no write permission)
    def local_schedule_error(e)
      Rails.logger.error "LdapSync local schedule error: #{e.message}"
      flash[:error] = l(:error_local_schedule_not_saved, :path => LdapSync::LocalSchedule.path, :message => e.message)
      redirect_to_schedule
    end

    def update_ldap_setting_from_params
      %w(user group).each do |e|
        params[:ldap_setting]["#{e}_fields_to_sync"] = params["#{e}_fields_to_sync"]
        params[:ldap_setting]["#{e}_ldap_attrs"]     = params["#{e}_ldap_attrs"]
      end if params[:ldap_setting]
      @ldap_setting.safe_attributes = params[:ldap_setting] if params[:ldap_setting]
    end

    def find_ldap_setting
      @ldap_setting = LdapSetting.find_by_auth_source_ldap_id(params[:id])
      render_404 if @ldap_setting.nil?
    end
end
