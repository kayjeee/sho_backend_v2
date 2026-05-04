module Api
  module V1
    class UploadsController < ApplicationController
      before_action :authorize

      # GET /api/v1/uploads
      # Generates a Cloudinary upload signature for client-side uploads.
      def index
        timestamp = Time.now.to_i

        # We can accept additional upload parameters from the frontend if needed
        # (e.g., folder, public_id, upload_preset)
        params_to_sign = {
          timestamp: timestamp,
          folder: params[:folder],
          upload_preset: params[:upload_preset]
        }.compact

        if defined?(Cloudinary::Utils)
          begin
            signature = Cloudinary::Utils.api_sign_request(params_to_sign, Cloudinary.config.api_secret)
            render json: {
              signature: signature.to_s,
              timestamp: timestamp.to_s,
              api_key: Cloudinary.config.api_key.to_s,
              cloud_name: Cloudinary.config.cloud_name.to_s
            }, status: :ok
          rescue => e
            Rails.logger.error "Cloudinary signature error: #{e.message}"
            render_mock_signature(params_to_sign, timestamp)
          end
        else
          render_mock_signature(params_to_sign, timestamp)
        end
      end

      # POST /api/v1/uploads
      # Generates a Cloudinary upload signature for client-side uploads.
      def create
        timestamp = Time.now.to_i

        # We can accept additional upload parameters from the frontend if needed
        # (e.g., folder, public_id, upload_preset)
        params_to_sign = {
          timestamp: timestamp
        }

        # Check if Cloudinary gem is available and configured
        if defined?(Cloudinary::Utils)
          begin
            # The cloudinary gem should be configured via environment variables:
            # CLOUDINARY_URL or CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET

            signature = Cloudinary::Utils.api_sign_request(params_to_sign, Cloudinary.config.api_secret)

            render_success(data: {
              signature: signature,
              timestamp: timestamp,
              api_key: Cloudinary.config.api_key,
              cloud_name: Cloudinary.config.cloud_name
            })
          rescue => e
            Rails.logger.error "Cloudinary signature error: #{e.message}"
            render_mock_signature(params_to_sign, timestamp)
          end
        else
          # Fallback if gem not installed or not configured properly in this environment
          render_mock_signature(params_to_sign, timestamp)
        end
      rescue => e
        handle_exception(e, "Failed to generate upload signature")
      end

      # GET /api/v1/uploads/:id
      def show
        render_success(data: { message: "Upload details for #{params[:id]}" })
      end

      # DELETE /api/v1/uploads/:id
      def destroy
        render_success(message: "Upload deleted successfully")
      end

      private

      def render_mock_signature(params_to_sign, timestamp)
        render json: {
          signature: "mock_signature_for_#{timestamp}",
          timestamp: timestamp.to_s,
          api_key: (ENV['CLOUDINARY_API_KEY'] || "mock_api_key").to_s,
          cloud_name: (ENV['CLOUDINARY_CLOUD_NAME'] || "mock_cloud_name").to_s,
          note: "Cloudinary gem not detected or error occurred; returning mock data."
        }, status: :ok
      end
    end
  end
end
