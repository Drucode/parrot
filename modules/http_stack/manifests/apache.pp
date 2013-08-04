class http_stack::apache(
  $apache_http_port  = 8080,
  $apache_https_port = 443
) {
  package { 'apache2': }
  package { 'libapache2-mod-php5': }

  file { '/etc/apache2/ports.conf':
    content => template('http_stack/apache/ports.conf.erb'),
    ensure => "present",
    owner => 'root',
    group => 'root',
    notify => Service['apache2']
  }

   # Ensure that mod-rewrite is running.
  exec { 'a2enmod-rewrite':
    command => '/usr/sbin/a2enmod rewrite',
    require => Package['apache2'],
    creates => '/etc/apache2/mods-enabled/rewrite.load',
    user => 'root',
    group => 'root',
  }

  # Ensure that mod-ssl is running.
  exec { 'a2enmod-ssl':
    command => '/usr/sbin/a2enmod ssl',
    require => Package['apache2'],
    creates => '/etc/apache2/mods-enabled/ssl.load',
    user => 'root',
    group => 'root',
  }

  class { 'phpmyadmin': }

  file { "/etc/apache2/conf.d/xhprof":
    source => 'puppet:///modules/http_stack/apache/xhprof',
    owner => 'root',
    group => 'root',
    require => Package['apache2'],
    notify => Service['apache2'],
  }

  # Restart Apache after the config file is deployed.
  service { 'apache2':  }

  # Make sure the SSL directory exists.
  file { "/etc/apache2/ssl.d":
    owner => 'root',
    group => 'root',
    require => Package['apache2'],
    ensure => "directory",
  }

  file { "/etc/apache2/ssl.d/parrot-ca":
    owner => 'root',
    group => 'root',
    require => File["/etc/apache2/ssl.d"],
    ensure => "directory",
  }

  file { "/etc/apache2/ssl.d/parrot-ca/certs":
    owner => 'root',
    group => 'root',
    require => File["/etc/apache2/ssl.d/parrot-ca"],
    ensure => "directory",
  }

  file { "/etc/apache2/ssl.d/parrot-ca/newcerts":
    owner => 'root',
    group => 'root',
    require => File["/etc/apache2/ssl.d/parrot-ca"],
    ensure => "directory",
  }

  file { "/etc/apache2/ssl.d/parrot-ca/crl":
    owner => 'root',
    group => 'root',
    require => File["/etc/apache2/ssl.d/parrot-ca"],
    ensure => "directory",
  }

  exec { "/bin/cat /dev/null > /etc/apache2/ssl.d/parrot-ca/index.txt":
    user => 'root',
    group => 'root',
    require => File["/etc/apache2/ssl.d/parrot-ca"],
    creates => "/etc/apache2/ssl.d/parrot-ca/index.txt",
  }

  exec { "/bin/echo '01' > /etc/apache2/ssl.d/parrot-ca/serial":
    user => 'root',
    group => 'root',
    require => File["/etc/apache2/ssl.d/parrot-ca"],
    creates => "/etc/apache2/ssl.d/parrot-ca/serial",
  }

  exec { "/bin/echo '01' > /etc/apache2/ssl.d/parrot-ca/crlnumber":
    user => 'root',
    group => 'root',
    require => File["/etc/apache2/ssl.d/parrot-ca"],
    creates => "/etc/apache2/ssl.d/parrot-ca/crlnumber",
  }

  file { "/etc/apache2/ssl.d/local-ca":
    owner => 'root',
    group => 'root',
    require => File["/etc/apache2/ssl.d"],
    ensure => "directory",
  }

  # Generate our CA certs.
  exec { "ssl-ca-cert":
    command => "/usr/bin/openssl req -new -x509 -extensions v3_ca -nodes -keyout parrot-ca.key -out parrot-ca.crt -subj '/O=Company/OU=Department/CN=Parrot Certificate Authority'",
    require => File['/etc/apache2/ssl.d/local-ca'],
    cwd => '/etc/apache2/ssl.d/local-ca',
    creates => "/etc/apache2/ssl.d/local-ca/parrot-ca.crt",
    user => 'root',
    group => 'root',
  }

  file { "/etc/apache2/ssl.d/parrot-ca/parrot-ca.key":
    owner => 'root',
    group => 'root',
    require => [File["/etc/apache2/ssl.d/parrot-ca"], Exec["ssl-ca-cert"]],
    ensure => "file",
    source => [
      "/vagrant_parrot_config/apache/ca/ca.key",
      "/etc/apache2/ssl.d/local-ca/parrot-ca.key",
    ]
  }

  file { "/etc/apache2/ssl.d/parrot-ca/parrot-ca.crt":
    owner => 'root',
    group => 'root',
    require => [File["/etc/apache2/ssl.d/parrot-ca"], Exec["ssl-ca-cert"]],
    ensure => "file",
    source => [
      "/vagrant_parrot_config/apache/ca/ca.crt",
      "/etc/apache2/ssl.d/local-ca/parrot-ca.crt",
    ]
  }

  file { "/etc/apache2/ssl.d/parrot-ca/openssl.cnf":
    owner => 'root',
    group => 'root',
    require => [File["/etc/apache2/ssl.d/parrot-ca",
                    "/etc/apache2/ssl.d/parrot-ca/certs",
                    "/etc/apache2/ssl.d/parrot-ca/newcerts",
                    "/etc/apache2/ssl.d/parrot-ca/crl"
                     ],
                Exec["/bin/cat /dev/null > /etc/apache2/ssl.d/parrot-ca/index.txt",
                     "/bin/echo '01' > /etc/apache2/ssl.d/parrot-ca/serial",
                     "/bin/echo '01' > /etc/apache2/ssl.d/parrot-ca/crlnumber"]
                ],
    ensure => "file",
    source => "puppet:///modules/http_stack/apache/openssl.cnf",
  }

  # Find the cores.
  $site_names_string = generate('/usr/bin/find', '-L', '/vagrant_sites/' , '-type', 'd', '-printf', '%f\0', '-maxdepth', '1', '-mindepth', '1')
  $site_names = split($site_names_string, '\0')

  # Set up the cores
  define apacheSiteResource {
    # The file in sites-available.
    file {"/etc/apache2/sites-available/$name":
      ensure => 'file',
      content => template('http_stack/apache/vhost.erb'),
      notify => Service['apache2'],
      require => Package['apache2'],
      owner => 'root',
      group => 'root',
    }
    # The symlink in sites-enabled.
    file {"/etc/apache2/sites-enabled/20-$name":
      ensure => 'link',
      target => "/etc/apache2/sites-available/$name",
      notify => Service['apache2'],
      require => Package['apache2'],
      owner => 'root',
      group => 'root',
    }

    # Add this virtual host to the hosts file
    host { $name:
      ip => '127.0.0.1',
      comment => 'Added automatically by Parrot',
      ensure => 'present',
    }

    # Add an SSL cert just for this host.
    exec { "ssl-req-$name":
      command => "/usr/bin/openssl req -new -days 3650 -sha1 -newkey rsa:1024 -nodes -keyout $name.key -out $name.csr -subj '/O=Company/OU=Department/CN=$name'",
      require => File['/etc/apache2/ssl.d'],
      cwd => '/etc/apache2/ssl.d',
      creates => "/etc/apache2/ssl.d/$name.csr",
      user => 'root',
      group => 'root',
    }

    exec { "ssl-cert-$name":
      command => "/usr/bin/openssl ca -batch -config /etc/apache2/ssl.d/parrot-ca/openssl.cnf -keyfile /etc/apache2/ssl.d/parrot-ca/parrot-ca.key -cert /etc/apache2/ssl.d/parrot-ca/parrot-ca.crt -policy policy_anything -out $name.crt -in $name.csr",
      require => [Exec["ssl-req-$name"], File["/etc/apache2/ssl.d/parrot-ca/openssl.cnf"]],
      cwd => '/etc/apache2/ssl.d',
      creates => "/etc/apache2/ssl.d/$name.crt",
      user => 'root',
      group => 'root',
    }

  }
  # Puppet magically turns our array into lots of resources.
  apacheSiteResource { $site_names: }





}
