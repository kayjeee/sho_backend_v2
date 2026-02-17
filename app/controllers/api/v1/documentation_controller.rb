# frozen_string_literal: true

module Api
  module V1
    class DocumentationController < ApplicationController
      # GET /api/docs
      def index
        render json: {
          message: 'SchoolHeadOffice API Documentation',
          version: 'v1',
          endpoints: [
            { path: '/api/v1/users', description: 'User management' },
            { path: '/api/v1/schools', description: 'School management' },
            { path: '/api/v1/health', description: 'Health check' }
          ]
        }, status: :ok
      end
    end
  end
end
