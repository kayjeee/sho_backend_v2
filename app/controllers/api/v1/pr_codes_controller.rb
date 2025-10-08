module Api
  module V1
    class PrCodesController < ApplicationController
      before_action :set_school

      def create
        pr_code = @school.pr_codes.new(pr_code_params)
        pr_code.code = generate_unique_code

        if pr_code.save
          render json: { success: true, pr_code: pr_code }, status: :created
        else
          render json: { success: false, errors: pr_code.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def set_school
        @school = School.find(params[:school_id])
      rescue Mongoid::Errors::DocumentNotFound
        render json: { success: false, message: 'School not found' }, status: :not_found
      end

      def pr_code_params
        params.require(:pr_code).permit(:purpose, :academic_year, metadata: {})
      end

      def generate_unique_code
        loop do
          code = SecureRandom.hex(3).upcase
          break code unless PrCode.exists?(code: code)
        end
      end
    end
  end
end