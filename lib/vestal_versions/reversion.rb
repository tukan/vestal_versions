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
      
      # Same as revert_to but returns a new object for given value.
      def revision(value)
        obj = self.class.new
        
        self.attributes.each do |key, v|
          obj.write_attribute(key, v)
        end
        
        obj.instance_variable_set("@new_record", self.new_record?)
        obj.revert_to(value)

        obj
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
        options = options.merge(:with_version => false)
        each_revision_in_list([1] + self.versions.to_a, options, &block)
      end
      
      # Like each_revision but also yields version object into block. 
      # For first (version = 1) yields nil for verison.
      def each_revision_with_version(options = {}, &block)
        options = options.merge(:with_version => true)
        each_revision_in_list([1] + self.versions.to_a, options, &block)
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
        each_revision_upto([1] + versions.before(self.version).to_a, options, &block)
      end

      private
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
                        
          current_version = versions_array.to_a.select{|v| v.is_a?(Version) ? v.number == self.version : v == self.version }.first
          current_version = self.version unless current_version
        
          using = versions_array.clone
          using.delete_if{|v| !v.is_a?(Version) }
          
          versions_array.delete_if{|v| v.is_a?(Version) ? v.number == self.version : v == self.version } unless options[:with_current]
                              
          current_revision = self
          if options[:order].to_sym == :desc
            versions_array = versions_array.reverse
            current_revision.send(:revert_from_to, current_version, versions_array.first, using)
          else
            current_revision.send(:revert_from_to, current_version, versions_array.first, using)
          end
        
          to_yield = revision_and_version_to_yield(current_revision, current_version, options[:with_version])
          yield *to_yield
        
          (1..versions_array.length-1).each do |index|
            current_revision.send(:revert_from_to, versions_array[index-1], versions_array[index], using)
            
            to_yield = revision_and_version_to_yield(current_revision, versions_array[index], options[:with_version])
            yield *to_yield
          end
        end
        
        def revision_and_version_to_yield(current_revision, current_version, with_version = false)
          if with_version
            if current_version.is_a?(Fixnum) && current_version == 1
              version_to_yield = nil
            elsif current_version.is_a?(Fixnum)
              version_to_yield = self.versions.at(current_version)
            else
              version_to_yield = current_version
            end
            
            return current_revision, version_to_yield
          else  
            return current_revision
          end
        end
        
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
