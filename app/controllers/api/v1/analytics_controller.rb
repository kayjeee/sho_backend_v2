# app/controllers/api/v1/analytics_controller.rb
module Api
  module V1
    class AnalyticsController < ApplicationController
      # GET /api/v1/analytics/invites
      def invites
        render json: { message: "Invites analytics" }, status: :ok
      end

      # GET /api/v1/analytics/pr-codes
      def pr_codes
        render json: { message: "PR codes analytics" }, status: :ok
      end

      # GET /api/v1/analytics/engagement
      def engagement
        render json: { message: "Engagement analytics" }, status: :ok
      end
    end
  end
end
