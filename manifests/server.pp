# This installs a MongoDB server. See README.md for more details.
class mongodb::server (
  Variant[Boolean, String] $ensure                    = $mongodb::params::ensure,
  String $user                                        = $mongodb::params::user,
  String $group                                       = $mongodb::params::group,
  Stdlib::Absolutepath $config                        = $mongodb::params::config,
  Stdlib::Absolutepath $dbpath                        = $mongodb::params::dbpath,
  Boolean $dbpath_fix                                 = $mongodb::params::dbpath_fix,
  Optional[Stdlib::Absolutepath] $pidfilepath         = $mongodb::params::pidfilepath,
  String $pidfilemode                                 = $mongodb::params::pidfilemode,
  Boolean $manage_pidfile                             = $mongodb::params::manage_pidfile,
  String $rcfile                                      = $mongodb::params::rcfile,
  Boolean $service_manage                             = $mongodb::params::service_manage,
  Optional[String] $service_provider                  = $mongodb::params::service_provider,
  Optional[String] $service_name                      = $mongodb::params::service_name,
  Boolean $service_enable                             = $mongodb::params::service_enable,
  Enum['stopped','running'] $service_ensure           = $mongodb::params::service_ensure,
  Optional[Enum['stopped','running']] $service_status = $mongodb::params::service_status,
  Variant[Boolean, String] $package_ensure            = $mongodb::params::package_ensure,
  String $package_name                                = $mongodb::params::server_package_name,
  Variant[Boolean, Stdlib::Absolutepath] $logpath     = $mongodb::params::logpath,
  Array[Stdlib::Compat::Ip_address] $bind_ip          = $mongodb::params::bind_ip,
  Optional[Boolean] $ipv6                             = undef,
  Boolean $logappend                                  = true,
  Optional[String] $system_logrotate                  = undef,
  Optional[Boolean] $fork                             = $mongodb::params::fork,
  Optional[Integer[1, 65535]] $port                   = undef,
  Optional[Boolean] $journal                          = $mongodb::params::journal,
  $nojournal                                          = undef,
  $smallfiles                                         = undef,
  $cpu                                                = undef,
  Boolean $auth                                       = false,
  $noauth                                             = undef,
  $verbose                                            = undef,
  $verbositylevel                                     = undef,
  $objcheck                                           = undef,
  $quota                                              = undef,
  $quotafiles                                         = undef,
  $diaglog                                            = undef,
  $directoryperdb                                     = undef,
  $profile                                            = undef,
  $maxconns                                           = undef,
  $oplog_size                                         = undef,
  $nohints                                            = undef,
  $nohttpinterface                                    = undef,
  $noscripting                                        = undef,
  $notablescan                                        = undef,
  $noprealloc                                         = undef,
  $nssize                                             = undef,
  $mms_token                                          = undef,
  $mms_name                                           = undef,
  $mms_interval                                       = undef,
  $replset                                            = undef,
  Optional[Hash] $replset_config                      = undef,
  Optional[Array] $replset_members                    = undef,
  $configsvr                                          = undef,
  $shardsvr                                           = undef,
  $rest                                               = undef,
  $quiet                                              = undef,
  $slowms                                             = undef,
  Optional[Stdlib::Absolutepath] $keyfile             = undef,
  Optional[String[6]] $key                            = undef,
  $set_parameter                                      = undef,
  Optional[Boolean] $syslog                           = undef,
  $config_content                                     = undef,
  $config_template                                    = undef,
  $config_data                                        = undef,
  Optional[Boolean] $ssl                              = undef,
  Optional[Stdlib::Absolutepath] $ssl_key             = undef,
  Optional[Stdlib::Absolutepath] $ssl_ca              = undef,
  Boolean $ssl_weak_cert                              = false,
  Boolean $ssl_invalid_hostnames                      = false,
  Boolean $restart                                    = $mongodb::params::restart,
  Optional[String] $storage_engine                    = undef,
  Boolean $create_admin                               = $mongodb::params::create_admin,
  String $admin_username                              = $mongodb::params::admin_username,
  Optional[String] $admin_password                    = undef,
  Boolean $handle_creds                               = $mongodb::params::handle_creds,
  Boolean $store_creds                                = $mongodb::params::store_creds,
  Array $admin_roles                                  = $mongodb::params::admin_roles,
) inherits mongodb::params {

  if ($ensure == 'present' or $ensure == true) {
    if $restart {
      anchor { 'mongodb::server::start': }
      -> class { 'mongodb::server::install': }
      # If $restart is true, notify the service on config changes (~>)
      -> class { 'mongodb::server::config': }
      ~> class { 'mongodb::server::service': }
      -> anchor { 'mongodb::server::end': }
    } else {
      anchor { 'mongodb::server::start': }
      -> class { 'mongodb::server::install': }
      # If $restart is false, config changes won't restart the service (->)
      -> class { 'mongodb::server::config': }
      -> class { 'mongodb::server::service': }
      -> anchor { 'mongodb::server::end': }
    }
  } else {
    anchor { 'mongodb::server::start': }
    -> class { 'mongodb::server::service': }
    -> class { 'mongodb::server::config': }
    -> class { 'mongodb::server::install': }
    -> anchor { 'mongodb::server::end': }
  }

  if $create_admin and ($service_ensure == 'running' or $service_ensure == true) {
    mongodb::db { 'admin':
      user     => $admin_username,
      password => $admin_password,
      roles    => $admin_roles,
    }

    # Make sure it runs at the correct point
    Anchor['mongodb::server::end'] -> Mongodb::Db['admin']

    # Make sure it runs before other DB creation
    Mongodb::Db['admin'] -> Mongodb::Db <| title != 'admin' |>
  }

  # Set-up replicasets
  if $replset {
    # Check that we've got either a members array or a replset_config hash
    if $replset_members and $replset_config {
      fail('You can provide either replset_members or replset_config, not both.')
    } elsif !$replset_members and !$replset_config {
      # No members or config provided. Warn about it.
      warning('Replset specified, but no replset_members or replset_config provided.')
    } else {
      if $replset_config {
        # Copy it to REAL value
        $_replset_config = $replset_config

      } else {
        # Build up a config hash
        $_replset_config = {
          "${replset}" => {
            'ensure'   => 'present',
            'members'  => $replset_members,
          },
        }
      }

      # Wrap the replset class
      class { 'mongodb::replset':
        sets => $_replset_config,
      }

      $replset_config_real = $_replset_config  # lint:ignore:variable_is_lowercase required for compatibility

      Anchor['mongodb::server::end'] -> Class['mongodb::replset']

      # Make sure that the ordering is correct
      if $create_admin {
        Class['mongodb::replset'] -> Mongodb::Db['admin']
      }

    }
  }
}
