# frozen_string_literal: true

module Decidim
  module Admin
    # This command gets called when permissions for a component are updated
    # in the admin panel.
    class UpdateComponentPermissions < Rectify::Command
      # Public: Initializes the command.
      #
      # form    - The form from which the data in this component comes from.
      # component - The component to update.
      # resource - The resource to update.
      def initialize(form, component, resource)
        @form = form
        @component = component
        @resource = resource
      end

      # Public: Sets the permissions for a component.
      #
      # Broadcasts :ok if created, :invalid otherwise.
      def call
        return broadcast(:invalid) unless form.valid?

        transaction do
          update_permissions
          run_hooks
        end

        broadcast(:ok)
      end

      private

      attr_reader :form, :component, :resource

      # TODO: esta implementación es para salir del paso
      def configured_permissions
        form.permissions.select do |action, permission|
          permission.authorization_handlers || overriding_component_permissions?(action)
        end
      end

      # TODO: esta implementación es para salir del paso
      def update_permissions
        permissions = configured_permissions.inject({}) do |result, (key, value)|
          handlers_content = {}

          present_authorization_handlers = value.authorization_handlers.except("").except(nil)

          present_authorization_handlers.each do |handler_key, handler_value|
            handlers_content[handler_key] = if handler_value && handler_value[:options] && handler_value[:options].keys.any?
                                              { "options" => handler_value[:options] }
                                            else
                                              {}
                                            end
          end

          serialized = {
            "authorization_handlers": handlers_content
          }

          result.update(key => present_authorization_handlers.keys.any? ? serialized : {})
        end

        if resource
          resource_permissions.update!(permissions: different_from_component_permissions(permissions))
        else
          component.update!(permissions: permissions)
        end
      end

      def run_hooks
        component.manifest.run_hooks(:permission_update, component: component, resource: resource)
      end

      def resource_permissions
        @resource_permissions ||= resource.resource_permission || resource.build_resource_permission
      end

      def different_from_component_permissions(permissions)
        return permissions unless component.permissions

        permissions.deep_stringify_keys.reject do |action, config|
          HashDiff.diff(config, component.permissions[action]).empty?
        end
      end

      def overriding_component_permissions?(action)
        resource && component&.permissions&.fetch(action, nil)
      end
    end
  end
end
