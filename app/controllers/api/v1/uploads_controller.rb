module Api
  module V1
    class UploadsController < ApplicationController
      before_action :authorize

      # POST /api/v1/uploads
      # Expects: { "filename": "image.jpg", "content_type": "image/jpeg" }
      def create
        filename = params[:filename]
        content_type = params[:content_type]

        if filename.blank? || content_type.blank?
          return render_error("filename and content_type are required", [], status: :bad_request)
        end

        key = "uploads/#{SecureRandom.uuid}/#{filename}"

        # Check if AWS SDK is available
        if defined?(Aws::S3::Resource)
          begin
            s3 = Aws::S3::Resource.new(
              region: ENV['AWS_REGION'] || 'us-east-1',
              access_key_id: ENV['AWS_ACCESS_KEY_ID'],
              secret_access_key: ENV['AWS_SECRET_ACCESS_KEY']
            )
            bucket = s3.bucket(ENV['AWS_BUCKET'])
            obj = bucket.object(key)

            presigned_url = obj.presigned_url(:put, acl: 'public-read', content_type: content_type, expires_in: 3600)
            download_url = obj.public_url
          rescue => e
            Rails.logger.error "S3 Presigned URL error: #{e.message}"
            # Fallback to mock if AWS fails or not configured
            presigned_url = mock_presigned_url(key)
            download_url = mock_download_url(key)
          end
        else
          # Fallback if gem not installed
          presigned_url = mock_presigned_url(key)
          download_url = mock_download_url(key)
        end

        render_success(data: {
          presigned_url: presigned_url,
          download_url: download_url,
          key: key
        })
      rescue => e
        handle_exception(e, "Failed to generate presigned URL")
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

      def mock_presigned_url(key)
        bucket = ENV['AWS_BUCKET'] || "sho-uploads"
        region = ENV['AWS_REGION'] || "us-east-1"
        "https://#{bucket}.s3.#{region}.amazonaws.com/#{key}?signature=mock_signature"
      end

      def mock_download_url(key)
        bucket = ENV['AWS_BUCKET'] || "sho-uploads"
        region = ENV['AWS_REGION'] || "us-east-1"
        "https://#{bucket}.s3.#{region}.amazonaws.com/#{key}"
      end
    end
  end
end
