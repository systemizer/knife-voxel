require 'chef/knife/voxel_base'

class Chef
  class Knife
    class VoxelVoxcloudFacilitiesList < Knife
      include Knife::VoxelBase

      banner "knife voxel voxcloud facilities list"

      def run
        facilities = hapi.voxel_voxcloud_facilities_list

        unless facilities['facilities'].empty?
          facilities['facilities']['facility'].each do |facility|
            puts ui.color("#{facility['label']} (#{facility['description']})\n", :bold)
          end
        end

      end

    end
  end
end
