require 'redmine'

# The vendor/ldap_sync_lib/ directory contains the plugin lib code.
# Zeitwerk does not index the vendor/ directory, avoiding autoload conflicts.
vendor_lib = File.expand_path('vendor/ldap_sync_lib', __dir__)
$LOAD_PATH.unshift(vendor_lib) unless $LOAD_PATH.include?(vendor_lib)

require 'hooks'

Redmine::Plugin.register :redmine_ldap_sync do
  name        'Redmine LDAP Sync'
  author      'Ricardo Santos (original), Gabor Jozsa (Rails 7 port & enhancements)'
  author_url  'https://github.com/thorin/redmine_ldap_sync'
  description 'Synchronizes Redmine users and groups with LDAP/Active Directory. Rails 7 / Redmine 6 compatible.'
  url         'https://github.com/jzsgbr/redmine_ldap_sync'
  version     '3.0.1'

  # Requires Redmine 6.0 or higher (Rails 7 port)
  requires_redmine :version_or_higher => '6.0.0'

  settings :default => {}.with_indifferent_access

  menu :admin_menu, :ldap_sync,
       { :controller => 'ldap_settings', :action => 'index' },
       :caption => :label_ldap_synchronization,
       :html => { :class => 'icon icon-reload' }
end

Rails.application.config.after_initialize do
  require 'core_ext'
  require 'infectors'
  require 'scheduler'
end
