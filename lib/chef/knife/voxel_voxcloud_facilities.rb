require 'chef/knife/voxel_base'

class Chef
  class Knife
    class VoxelVoxcloudFacilities < Knife
      include Knife::VoxelBase

      deps do
        require 'chef/json_compat'
        require 'chef/knife/bootstrap'
        require 'hapi'
        require 'readline'

        Chef::Knife::Bootstrap.load_deps
      end

      banner "knife voxel voxcloud facilities"



      def run

        facilities = hapi.voxel_voxservers_facilities_list

        unless facilities['facilities'].empty?
          facilities['facilities']['facility'].each do |facility|
            puts ui.color("#{facility['label']} (#{facility['description']})\n", :bold)
          end
        end

      end

    end
  end
end