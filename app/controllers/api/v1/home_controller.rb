module Api
  module V1
    class HomeController < ApplicationController
      skip_before_action :authorize, only: [:index, :health], raise: false

      def index
        render json: {
          message: 'Welcome to the SchoolHeadOffice API v1 🚀',
          version: 'v1',
          docs: '/api/docs',
          timestamp: Time.current.iso8601
        }, status: :ok
      end

      def health
        render json: {
          status: 'healthy',
          env: Rails.env,
          time: Time.current.iso8601
        }, status: :ok
      end
    end
  end
end
