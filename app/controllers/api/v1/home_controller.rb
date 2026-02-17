# frozen_string_literal: true

module Api
  module V1
    class HomeController < ApplicationController
      # GET /api/v1
      # root 'api/v1/home#index'
      def index
        render json: {
          message: 'Welcome to the SchoolHeadOffice API v1 🚀',
          version: 'v1',
          docs: '/api/docs',
          timestamp: Time.current.iso8601
        }, status: :ok
      end

      # GET /api/v1/health
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
