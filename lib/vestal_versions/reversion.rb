module VestalVersions
  # Enables versioned ActiveRecord::Base instances to revert to a previously saved version.
  module Reversion
    def self.included(base) # :nodoc:
      base.class_eval do
        include InstanceMethods
      end
    end

    # Provides the base instance methods required to revert a versioned instance.
    module InstanceMethods
      # Returns the current version number for the versioned object.
      def version
        self[:version] ? self[:version] : @version ||= last_version
      end
      
      # Returns true if current version is the last version
      def last_version?
        self.version == last_version
      end
      
      # Returns the number of the last created version in the object's version history.
      #
      # If no associated versions exist, the object is considered at version 1.
      def last_version
        @last_version ||= versions.maximum(:number) || 1
      end

      # Accepts a value corresponding to a specific version record, builds a history of changes
      # between that version and the current version, and then iterates over that history updating
      # the object's attributes until the it's reverted to its prior state.
      #
      # The single argument should adhere to one of the formats as documented in the +at+ method of
      # VestalVersions::Versions.
      #
      # After the object is reverted to the target version, it is not saved. In order to save the
      # object after the reversion, use the +revert_to!+ method.
      #
      # The version number of the object will reflect whatever version has been reverted to, and
      # the return value of the +revert_to+ method is also the target version number.
      def revert_to(value)
        to_number = versions.number_at(value)

        changes_between(version, to_number).each do |attribute, change|
          write_attribute(attribute, change.last)
        end

        reset_version(to_number)
      end

      # Behaves similarly to the +revert_to+ method except that it automatically saves the record
      # after the reversion. The return value is the success of the save.
      def revert_to!(value)
        revert_to(value)
        reset_version if saved = save
        saved
      end

      # Returns a boolean specifying whether the object has been reverted to a previous version or
      # if the object represents the latest version in the version history.
      def reverted?
        version != last_version
      end

      # Iterates over all object revision and yields then into block
      # It is more optimal that using revert_to in loop because this methods
      # uses only one SQL query to fetch all versions.
      #
      # +options+:
      # +order+: (default +asc+) +asc+ or +desc+. Order of versions to iterate over
      # +with_current+: (default +true+) set to +false+ if you don't want the current
      # revision to be included in the iteration.
      def each_revision(options = {}, &block)
        each_revision_in_list(self.versions.to_a, options, &block)
      end
      
      # Iterates over all object revision from +from+ to +to+ version.
      # It is more optimal that using revert_to in loop because this methods
      # uses only one SQL query to fetch all versions.
      #
      # +options+:
      # +order+: (default +asc+) +asc+ or +desc+. Order of versions to iterate over
      # +with_current+: (default +true+) set to +false+ if you don't want the current
      # revision to be included in the iteration.
      def each_revision_in_slice(from, to, options = {}, &block)
        each_revision_in_list(versions.between(from, to).to_a, options, &block)
      end
      
      # Iterates over all object revision from the first revision to current revision.
      # It is more optimal that using revert_to in loop because this methods
      # uses only one SQL query to fetch all versions.
      #
      # +options+:
      # +order+: (default +asc+) +asc+ or +desc+. Order of versions to iterate over
      # +with_current+: (default +true+) set to +false+ if you don't want the current
      # revision to be included in the iteration.
      def each_revision_upto_current(options = {}, &block)
        each_revision_upto(versions.before(self.version).to_a, options, &block)
      end
      
      # Iterates over all object revision for versions in the +list+
      # It is more optimal that using revert_to in loop because this methods
      # uses only one SQL query to fetch all versions.
      #
      # +options+:
      # +order+: (default +asc+) +asc+ or +desc+. Order of versions to iterate over
      # +with_current+: (default +true+) set to +false+ if you don't want the current
      # revision to be included in the iteration.
      def each_revision_in_list(versions_array, options = {}, &block)
        return if versions_array.length < 2
        
        options = options.reverse_merge({ :order => :asc, :with_current => true })
                        
        current_version = versions_array.to_a.select{|v| v.number == self.version}.first
        current_version = self.version unless current_version
        
        versions_array.delete_if{|v| v.number == self.version} unless options[:with_current]        
        
        current_revision = self
        if options[:order].to_sym == :desc
          versions_array = versions_array.reverse
          current_revision.send(:revert_from_to, current_version, versions_array.first, versions_array)
        else
          current_revision.send(:revert_from_to, current_version, versions_array.first, versions_array)
        end
        
        yield current_revision
        
        (1..versions_array.length-1).each do |index|
          current_revision.send(:revert_from_to, versions_array[index-1], versions_array[index], versions_array)

          yield current_revision
        end
      end

      private
        # Clears the cached version number instance variables so that they can be recalculated.
        # Useful after a new version is created.
        def reset_version(version = nil)
          @last_version = nil if version.nil?
          self[:version] ? self.version = version : @version = version
        end
        
        # This is internal method to revert from two revisions without any additional SQL queries.
        # If +from+ and +two+ are two neighbouring versions then no sql queries are needed. If there are
        # some versions between them then you could pass them as +using+ and they will be used for
        # calculating changes between revisions. 
        def revert_from_to(from, to, using = [])
          to_number = versions.number_at(to)

          changes_between(from, to, using).each do |attribute, change|
            write_attribute(attribute, change.last)
          end

          reset_version(to_number)
        end
    end
  end
end
