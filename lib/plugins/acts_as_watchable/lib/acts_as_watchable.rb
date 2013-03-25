#-- encoding: UTF-8
# ActsAsWatchable
module Redmine
  module Acts
    module Watchable
      def self.included(base)
        base.extend ClassMethods
      end

      module ClassMethods
        # Marks an ActiveRecord::Model as watchable
        # A watchable model has association with users (watchers) who wish to be informed of changes on it.
        #
        # This also creates the routes necessary for watching/unwatching by adding the model's name to routes. This
        # e.g leads to the following routes when marking issues as watchable:
        #   POST:     issues/1/watch
        #   DELETE:   issues/1/unwatch
        #   GET/POST: issues/1/watchers/new
        #   DELETE:   issues/1/watchers/1
        # Use the :route_prefix option to change the model prefix, e.g. from issues to tickets
        #
        # params:
        #   options:
        #     route_prefix: overrides the route calculation which would normally use the models name.

        def acts_as_watchable(options = {})
          return if self.included_modules.include?(Redmine::Acts::Watchable::InstanceMethods)
          class_eval do
            has_many :watchers, :as => :watchable, :dependent => :delete_all
            has_many :watcher_users, :through => :watchers, :source => :user, :validate => false

            scope :watched_by, lambda { |user_id|
              { :include => :watchers,
                :conditions => ["#{Watcher.table_name}.user_id = ?", user_id] }
            }
            attr_protected :watcher_ids, :watcher_user_ids if accessible_attributes.nil?
          end
          send :include, Redmine::Acts::Watchable::InstanceMethods
          alias_method_chain :watcher_user_ids=, :uniq_ids

          OpenProject::Acts::Watchable::Routes.add_watched(options[:route_prefix] || self.to_s.underscore.pluralize)
        end
      end

      module InstanceMethods
        def self.included(base)
          base.extend ClassMethods
        end

        # Returns an array of users that might be watchers or already are watchers
        def possible_watcher_users
          users = User.all
          if respond_to?(:visible?)
            users.reject! {|user| !visible?(user)}
          else
            warn "Let all users watch me. If this is unintended, implement :visible? on #{self.class.name}"
          end
          users
        end

        # Returns an array of users that are proposed as watchers
        def addable_watcher_users
          possible_watcher_users - self.watcher_users
        end

        # Adds user as a watcher
        def add_watcher(user)
          self.watchers << Watcher.new(:user => user)
        end

        # Removes user from the watchers list
        def remove_watcher(user)
          return nil unless user && user.is_a?(User)
          Watcher.delete_all "watchable_type = '#{self.class}' AND watchable_id = #{self.id} AND user_id = #{user.id}"
        end

        # Adds/removes watcher
        def set_watcher(user, watching=true)
          watching ? add_watcher(user) : remove_watcher(user)
        end

        # Overrides watcher_user_ids= to make user_ids uniq
        def watcher_user_ids_with_uniq_ids=(user_ids)
          if user_ids.is_a?(Array)
            user_ids = user_ids.uniq
          end
          send :watcher_user_ids_without_uniq_ids=, user_ids
        end

        # Returns true if object is watched by +user+
        def watched_by?(user)
          !!(user && self.watcher_user_ids.detect {|uid| uid == user.id })
        end

        # Returns an array of watchers' email addresses
        def watcher_recipients
          notified = watcher_users.active
          notified.reject! {|user| user.mail_notification == 'none'}

          if respond_to?(:visible?)
            notified.reject! {|user| !visible?(user)}
          end
          notified.collect(&:mail).compact
        end

        module ClassMethods; end
      end
    end
  end
end
