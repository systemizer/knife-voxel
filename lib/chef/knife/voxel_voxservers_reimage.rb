require 'chef/knife/voxel_base'

class Chef
  class Knife
    class VoxelVoxserversReimage < Knife
      include Knife::VoxelBase

      deps do
        require 'chef/json_compat'
        require 'chef/knife/bootstrap'
        require 'hapi'
        require 'readline'

        Chef::Knife::Bootstrap.load_deps
      end

      banner "knife voxel voxservers reimage DEVICE_ID (options)"

      option :swap_size,
        :long => "--swap-size SIZE",
        :description => "Swap Partition Size, in GB",
        :default => 4

      option :image_id,
        :long => "--image-id IMAGE",
        :description => "Image Id to Install",
        :required => true

      option :hostname,
        :long => "--hostname NAME",
        :description => "The server's hostname",
        :required => true

      option :chef_node_name,
        :short => "-N NAME",
        :long => "--node-name NAME",
        :description => "The Chef node name for your new node"

      option :ssh_user,
        :short => "-x USERNAME",
        :long => "--ssh-user USERNAME",
        :description => "The ssh username; default is 'root'",
        :default => "root"

      option :ssh_password,
        :short => "-P PASSWORD",
        :long => "--ssh-password PASSWORD",
        :description => "The ssh password"

      option :identity_file,
        :short => "-i IDENTITY_FILE",
        :long => "--identity-file IDENTITY_FILE",
        :description => "The SSH identity file used for authentication"

      option :postinstall_script,
        :short => "-s POSTINSTALL_SCRIPT",
        :long => "--postinstall-script POSTINSTALL_SCRIPT",
        :description => "Path to the file you wish to execute upon successful reimage"

      option :prerelease,
        :long => "--prerelease",
        :description => "Install the pre-release chef gems"

      option :bootstrap_version,
        :long => "--bootstrap-version VERSION",
        :description => "The version of Chef to install",
        :proc => Proc.new { |v| Chef::Config[:knife][:bootstrap_version] = v }

      option :distro,
        :short => "-d DISTRO",
        :long => "--distro DISTRO",
        :description => "Bootstrap a distro using a template; default is 'ubuntu10.04-gems'",
        :proc => Proc.new { |d| Chef::Config[:knife][:distro] = d },
        :default => "ubuntu10.04-gems"

      option :template_file,
        :long => "--template-file TEMPLATE",
        :description => "Full path to location of template to use",
        :proc => Proc.new { |t| Chef::Config[:knife][:template_file] = t },
        :default => false

      option :run_list,
        :short => "-r RUN_LIST",
        :long => "--run-list RUN_LIST",
        :description => "Comma separated list of roles/recipes to apply",
        :proc => lambda { |o| o.split(/[\s,]+/) },
        :default => []

      def bootstrap_for_node(device)
        bootstrap = Chef::Knife::Bootstrap.new

        bootstrap.name_args = [device['ipassignments']['ipassignment'].select { |i| i['type'] == 'frontend' }.first['content']]
        bootstrap.config[:run_list] = config[:run_list]
        bootstrap.config[:ssh_user] = config[:ssh_user] || "root"
        bootstrap.config[:ssh_password] = device['accessmethods']['accessmethod'].select { |a| a['type'] == 'admin' }.first['password']
        bootstrap.config[:identity_file] = config[:identity_file]
        bootstrap.config[:chef_node_name] = config[:chef_node_name] || "d#{device['id']}"
        bootstrap.config[:prerelease] = config[:prerelease]
        bootstrap.config[:bootstrap_version] = config[:bootstrap_version]
        bootstrap.config[:distro] = config[:distro]
        bootstrap.config[:use_sudo] = true unless config[:ssh_user] == 'root'
        bootstrap.config[:template_file] = config[:template_file]
        bootstrap.config[:environment] = config[:environment]
        bootstrap
      end

      def tcp_test_ssh(hostname)
        begin
          tcp_socket = TCPSocket.new(hostname, 22)
          readable = IO.select([tcp_socket], nil, nil, 5)
          if readable
            Chef::Log.debug("sshd accepting connections on #{hostname}, banner is #{tcp_socket.gets}")
            yield
            true
          else
            false
          end
        rescue Errno::ETIMEDOUT
          false
        rescue Errno::EPERM
          false
        rescue Errno::ECONNREFUSED
          sleep 2
          false
        rescue Errno::EHOSTUNREACH
          sleep 2
          false
        ensure
          tcp_socket && tcp_socket.close
        end
      end

      def run
        $stdout.sync = true

        unless @name_args.empty?
          postinstall_script = File.read(config[:postinstall_script]) if File.exists?(config[:postinstall_script])
          create = hapi.voxel_voxservers_reimage(
            :device_id        => @name_args.first,
            :image_id         => config[:image_id],
            :hostname         => config[:hostname],
            :swap_space       => config[:swap_size],
            :postinstall_script => postinstall_script
          )

          if create['stat'] == "fail"
            ui.error(create['err']['msg'])
          else
            sleep 2

            device = hapi.voxel_devices_list( :device_id => create['device']['id'], :verbosity => 'extended' )

            if device['stat'] == "fail"
              ui.error(device['err']['msg'])
            else
              device = device['devices']['device']

              puts "#{ui.color("Device ID", :cyan)}: #{device['id']}"
              puts "#{ui.color("Name", :cyan)}: #{device['label']}"
              puts "#{ui.color("Image Id", :cyan)}: #{config[:image_id]}"
              puts "#{ui.color("Facility", :cyan)}: #{device['location']['facility']['code']}"
              puts "#{ui.color("Public IP Address", :cyan)}: #{device['ipassignments']['ipassignment'].select { |i| i['type'] == 'frontend' }.first['content']}"
              puts "#{ui.color("Private IP Address", :cyan)}: #{device['ipassignments']['ipassignment'].select { |i| i['type'] == 'backend' }.first['content']}"
              puts "#{ui.color("Root Password", :cyan)}: #{device['accessmethods']['accessmethod'].select { |a| a['type'] == 'admin' }.first['password']}"

              status = hapi.voxel_voxservers_status( :device_id => device['id'], :verbosity => 'extended' )

              while %w{ QUEUED IN_PROGRESS }.include?( status['devices']['device']['status'] ) do
                print "."
                status = hapi.voxel_voxservers_status( :device_id => device['id'], :verbosity => 'extended' )
                sleep 10
              end

              print "\n#{ui.color("Waiting for sshd", :magenta)}"

              print(".") until tcp_test_ssh(device['ipassignments']['ipassignment'].select { |i| i['type'] == 'frontend' }.first['content']) { sleep @initial_sleep_delay ||= 10; puts("done") }

              bootstrap_for_node(device).run

              puts "#{ui.color("Run List", :cyan)}: #{config[:run_list].join(', ')}"
              puts "#{ui.color("Node Name", :cyan)}: #{config[:node_name] || 'd' + device['id']}"
              puts "#{ui.color("Environment", :cyan)}: #{config[:environment] || '_default'}"
              puts "#{ui.color("Device ID", :cyan)}: #{device['id']}"
              puts "#{ui.color("Name", :cyan)}: #{device['label']}"
              puts "#{ui.color("Image Id", :cyan)}: #{config[:image_id]}"
              puts "#{ui.color("Facility", :cyan)}: #{device['location']['facility']['code']}"
              puts "#{ui.color("Public IP Address", :cyan)}: #{device['ipassignments']['ipassignment'].select { |i| i['type'] == 'frontend' }.first['content']}"
              puts "#{ui.color("Private IP Address", :cyan)}: #{device['ipassignments']['ipassignment'].select { |i| i['type'] == 'backend' }.first['content']}"
              puts "#{ui.color("Root Password", :cyan)}: #{device['accessmethods']['accessmethod'].select { |a| a['type'] == 'admin' }.first['password']}"
            end
          end
        else
          ui.error( "knife voxel voxservers reimage DEVICE_ID (options)" )
        end
      end

    end
  end
end
