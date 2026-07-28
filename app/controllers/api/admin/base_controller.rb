module Api
  module Admin
    class BaseController < ActionController::API
      include Secured
      wrap_parameters false
      include SchoolResolver

      rescue_from StandardError, with: :handle_unexpected_api_crash
      rescue_from BSON::Error::InvalidObjectId, with: :handle_invalid_object_id
      rescue_from Mongoid::Errors::DocumentNotFound, with: :handle_document_not_found

      private

      def handle_unexpected_api_crash(exception)
        Rails.logger.error "🔥 CRASH IN API ENGINES: #{exception.message}"
        cleaned_trace = BacktraceCleanerUtil.clean(exception.backtrace)
        Rails.logger.error cleaned_trace.join("\n")

        render json: {
          success: false,
          error: "Internal Server Error",
          message: exception.message
        }, status: :internal_server_error
      end

      def handle_invalid_object_id(exception)
        render json: {
          success: false,
          error: "Malformed ID",
          message: "The provided ID is not a valid BSON ObjectId"
        }, status: :bad_request
      end

      def handle_document_not_found(exception)
        render json: {
          success: false,
          error: "Not Found",
          message: "The requested record could not be found"
        }, status: :not_found
      end
    end
  end
end
