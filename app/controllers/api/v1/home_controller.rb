module Api
  module V1
    class HomeController < ApplicationController
      def index
        render json: {
          message: "Welcome to School Head Office API v1",
          environment: Rails.env,
          timestamp: Time.current
        }
      end

      def health
        render json: { status: "ok", time: Time.current }
      end
    end
  end
end
