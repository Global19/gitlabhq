# frozen_string_literal: true

module Types
  class EnvironmentType < BaseObject
    graphql_name 'Environment'
    description 'Describes where code is deployed for a project'

    authorize :read_environment

    field :name, GraphQL::STRING_TYPE, null: false,
          description: 'Human-readable name of the environment'

    field :id, GraphQL::ID_TYPE, null: false,
          description: 'ID of the environment'

    field :state, GraphQL::STRING_TYPE, null: false,
          description: 'State of the environment, for example: available/stopped'

    field :metrics_dashboard, Types::Metrics::DashboardType, null: true,
          description: 'Metrics dashboard schema for the environment',
          resolver: Resolvers::Metrics::DashboardResolver
  end
end
