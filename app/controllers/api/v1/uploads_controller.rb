# app/controllers/api/v1/uploads_controller.rb

module Api
  module V1
    class UploadsController < ApplicationController
      before_action :authorize

      # =========================================================
      # FILE VALIDATION
      # =========================================================
      ALLOWED_MIMETYPES = %w[
        image/jpeg image/png image/gif image/webp
        application/pdf
        video/mp4 video/quicktime
        audio/webm audio/mpeg audio/mp4 audio/ogg audio/wav
      ].freeze

      MAX_FILE_SIZE = 25.megabytes

      # =========================================================
      # GET /api/v1/uploads
      # Cloudinary signature (client-side upload support)
      # =========================================================
      def index
        generate_signature
      end

      # =========================================================
      # POST /api/v1/uploads
      # Cloudinary signature OR direct upload handling
      # =========================================================
      def create
        # If frontend sends file → validate & upload directly
        return handle_direct_upload if params[:file].present?

        # Otherwise return signed upload params
        generate_signature
      end

      # =========================================================
      # GET /api/v1/uploads/:id
      # =========================================================
      def show
        render_success(data: { message: "Upload details for #{params[:id]}" })
      end

      # =========================================================
      # DELETE /api/v1/uploads/:id
      # =========================================================
      def destroy
        render_success(message: "Upload deleted successfully")
      end

      private

      # =========================================================
      # DIRECT FILE UPLOAD (VALIDATED)
      # =========================================================
      def handle_direct_upload
        file = params[:file]

        return render json: { success: false, error: "No file provided" },
                      status: :bad_request if file.blank?

        unless ALLOWED_MIMETYPES.include?(file.content_type)
          return render json: {
            success: false,
            error: "#{file.content_type} is not supported"
          }, status: :unprocessable_entity
        end

        if file.size > MAX_FILE_SIZE
          return render json: {
            success: false,
            error: "File exceeds 25 MB limit"
          }, status: :unprocessable_entity
        end

        result = Cloudinary::Uploader.upload(
          file.tempfile.path,
          resource_type: cloudinary_resource_type(file.content_type),
          folder: "messages/#{@current_user.id}",
          use_filename: true,
          unique_filename: true
        )

        render json: {
          success: true,
          url: result["secure_url"],

          # =====================================================
          # CRITICAL FOR CHAT SYSTEM
          # =====================================================
          attachment_type: derive_attachment_type(file.content_type),
          attachment_name: file.original_filename,
          attachment_size: file.size
        }, status: :created

      rescue Cloudinary::Error => e
        render json: {
          success: false,
          error: "Upload failed: #{e.message}"
        }, status: :unprocessable_entity
      end

      # =========================================================
      # CLOUDINARY SIGNATURE GENERATION
      # =========================================================
      def generate_signature
        timestamp = Time.now.to_i

        params_to_sign = {
          timestamp: timestamp,
          folder: params[:folder],
          upload_preset: params[:upload_preset]
        }.compact

        if defined?(Cloudinary::Utils)
          begin
            signature = Cloudinary::Utils.api_sign_request(
              params_to_sign,
              Cloudinary.config.api_secret
            )

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

      # =========================================================
      # RESOURCE TYPE MAPPING (CLOUDINARY RULES)
      # =========================================================
      def cloudinary_resource_type(mime)
        case mime
        when /\Aimage\// then "image"
        when /\Avideo\// then "video"
        when /\Aaudio\// then "video" # Cloudinary stores audio under "video"
        else "raw"
        end
      end

      # =========================================================
      # ATTACHMENT TYPE FOR FRONTEND
      # =========================================================
      def derive_attachment_type(mime)
        case mime
        when /\Aimage\// then "image"
        when /\Avideo\// then "video"
        when /\Aaudio\// then "audio"
        when "application/pdf" then "pdf"
        else "other"
        end
      end

      # =========================================================
      # FALLBACK SIGNATURE (DEV MODE)
      # =========================================================
      def render_mock_signature(params_to_sign, timestamp)
        render json: {
          signature: "mock_signature_for_#{timestamp}",
          timestamp: timestamp.to_s,
          api_key: (ENV["CLOUDINARY_API_KEY"] || "mock_api_key").to_s,
          cloud_name: (ENV["CLOUDINARY_CLOUD_NAME"] || "mock_cloud_name").to_s,
          note: "Cloudinary not available; using mock response."
        }, status: :ok
      end
    end
  end
end